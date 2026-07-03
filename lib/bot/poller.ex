defmodule Sexy.Bot.Poller do
  @moduledoc """
  GenServer that polls Telegram for updates and routes them to `Sexy.Bot.Session` callbacks.

  Started automatically as a child of `Sexy.Bot`. Each incoming update is dispatched
  through `Sexy.Bot.Dispatcher` partitions, so a malformed update or a crashing
  handler can never kill the polling loop.

  ## Delivery semantics

  Updates are confirmed to Telegram on the poll *after* they were dispatched, and the
  offset survives poller restarts — so delivery is **at-least-once**: after a crash in
  the confirmation window a batch can be dispatched twice. Handlers with side effects
  (payments!) should be idempotent, e.g. deduplicate by `update_id`.

  Updates of the **same chat are processed in order** (they land in the same
  dispatcher partition); different chats run concurrently.

  ## Routing rules

  | Update type | Condition | Session callback |
  |---|---|---|
  | `message` | text starts with `/` | `handle_command/1` |
  | `message` | otherwise | `handle_message/1` |
  | `callback_query` | data starts with `/_delete` | built-in: deletes the message |
  | `callback_query` | data starts with `/_transit` | built-in: deletes + `handle_transit/3` |
  | `callback_query` | otherwise | `handle_query/1` |
  | `message` | has `successful_payment` | `handle_successful_payment/1` |
  | `pre_checkout_query` | — | `handle_pre_checkout/1` |
  | `poll` / `poll_answer` | — | `handle_poll/1` |
  | `my_chat_member` | — | `handle_chat_member/1` |

  ## Built-in routes

    * `/_delete mid=<id>` — deletes message with given id, answers the callback
    * `/_transit mid=<id>-cmd=<command>-...` — deletes message, answers callback,
      then calls `Session.handle_transit(chat_id, command, query_params)`

  Callback data is client-controlled: malformed built-in routes (missing `mid`/`cmd`)
  are answered with a no-op instead of raising.
  """
  use GenServer

  alias Sexy.Bot.Api
  alias Sexy.Utils

  require Logger

  @poll_interval 100
  @backoff 5_000

  # Server

  def start_link(_g) do
    Logger.log(:info, "Started poller")
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    send(self(), :poll)
    {:ok, restore_offset()}
  end

  # The loop is driven by send_after, not GenServer timeouts — a GenServer
  # timeout is cancelled by ANY arriving message, so a single stray message
  # (e.g. a socket message leaked by the HTTP pool) would stop polling forever.
  def handle_info(:poll, offset) do
    {new_offset, delay} = poll(offset)
    Process.send_after(self(), :poll, delay)
    {:noreply, new_offset}
  end

  def handle_info(msg, offset) do
    Logger.debug("Sexy.Bot.Poller ignored message: #{inspect(msg)}")
    {:noreply, offset}
  end

  # One-off extra poll; the send_after loop keeps its own schedule.
  def handle_cast(:update, offset) do
    {new_offset, _delay} = poll(offset)
    {:noreply, new_offset}
  end

  # Client

  def update do
    GenServer.cast(__MODULE__, :update)
  end

  # Helpers

  defp poll(offset) do
    Api.get_updates(offset)
    |> process_messages(offset)
  end

  # Empty/error polls keep the current offset (never reset to 0), so an
  # unconfirmed batch isn't replayed after a transport failure. Errors also
  # back off the poll interval instead of hot-looping.
  defp process_messages({:ok, []}, offset), do: {offset, @poll_interval}

  defp process_messages({:ok, results}, _offset) do
    # All routing (including reading update contents) runs inside Dispatcher
    # partitions: a poison update can never crash the polling loop itself, and
    # updates of the same chat land in the same partition — processed in order.
    for u <- results do
      GenServer.cast(
        {:via, PartitionSupervisor, {Sexy.Bot.Dispatchers, chat_key(u)}},
        {:dispatch, fn -> match_update(u) end}
      )
    end

    last = results |> Enum.map(fn %{update_id: id} -> id end) |> List.last()
    {save_offset(last + 1), @poll_interval}
  end

  defp process_messages({:error, error}, offset) do
    Logger.log(:error, inspect(error))

    {offset, @backoff}
  end

  defp process_messages(:error, offset) do
    Logger.log(:error, "Unexpected error format in poller")

    {offset, @backoff}
  end

  # Partition key: chat id where the update has one (per-chat ordering),
  # user id for payments, update_id otherwise (spreads chat-less updates).
  defp chat_key(%{message: %{chat: %{id: id}}}), do: id
  defp chat_key(%{callback_query: %{message: %{chat: %{id: id}}}}), do: id
  defp chat_key(%{my_chat_member: %{chat: %{id: id}}}), do: id
  defp chat_key(%{pre_checkout_query: %{from: %{id: id}}}), do: id
  defp chat_key(%{update_id: id}), do: id

  # Offset survives poller restarts (atomics ref owned by Sexy.Bot.Config),
  # so a crash never replays the already-dispatched batch.
  defp restore_offset, do: :atomics.get(offset_ref(), 1)

  defp save_offset(offset) do
    :atomics.put(offset_ref(), 1, offset)
    offset
  end

  defp offset_ref, do: :persistent_term.get({Sexy.Bot, :offset_ref})

  defp match_update(%{message: %{successful_payment: _}} = u),
    do: apply_successful_payment(u)

  defp match_update(%{message: message} = u) do
    if Map.has_key?(message, :text) and String.first(message.text) == "/",
      do: apply_command(u),
      else: apply_message(u)
  end

  defp match_update(%{callback_query: query} = u) do
    # :data is optional per the Bot API (e.g. game buttons) — route dataless
    # queries to the consumer handler instead of crashing.
    case Utils.Bot.get_command_name(Map.get(query, :data, "")) do
      "_delete" -> handle_builtin_delete(query)
      "_transit" -> handle_builtin_transit(query)
      _ -> apply_query(u)
    end
  end

  defp match_update(%{pre_checkout_query: _} = u),
    do: apply_pre_checkout(u)

  defp match_update(%{poll: _poll} = u),
    do: apply_poll(u)

  defp match_update(%{poll_answer: _poll_answer} = u),
    do: apply_poll(u)

  defp match_update(%{my_chat_member: _chat_member} = u),
    do: apply_chat_member(u)

  defp match_update(u),
    do: Logger.warning("Unknown update in poller\n\n#{inspect(u, pretty: true)}")

  defp handle_builtin_delete(query) do
    case Utils.get_query(Map.get(query, :data, "")) do
      %{mid: mid} -> Api.delete_message(query.message.chat.id, mid)
      _ -> :ok
    end

    Api.answer_callback(query.id, "", false)
  end

  defp handle_builtin_transit(query) do
    params = Utils.get_query(Map.get(query, :data, ""))

    # Check the optional callback BEFORE any side effect: forged /_transit data
    # must not delete a message when there is no handler to continue the flow.
    with %{mid: mid, cmd: cmd} <- params,
         true <- function_exported?(session(), :handle_transit, 3) do
      chat_id = query.message.chat.id
      Api.delete_message(chat_id, mid)
      Api.answer_callback(query.id, "", false)
      session().handle_transit(chat_id, cmd, Map.drop(params, [:mid, :cmd]))
    else
      _ -> Api.answer_callback(query.id, "", false)
    end
  end

  # The session module is loaded at boot by Sexy.Bot.start_link
  # (Code.ensure_loaded!), so function_exported? checks here are reliable.
  defp session, do: :persistent_term.get({Sexy.Bot, :session})

  def apply_command(u), do: session().handle_command(u)
  def apply_message(u), do: session().handle_message(u)
  def apply_query(u), do: session().handle_query(u)
  def apply_chat_member(u), do: session().handle_chat_member(u)

  def apply_poll(u) do
    if function_exported?(session(), :handle_poll, 1) do
      session().handle_poll(u)
    else
      Logger.info("Received poll update, no handle_poll defined")
    end
  end

  def apply_pre_checkout(u) do
    if function_exported?(session(), :handle_pre_checkout, 1) do
      session().handle_pre_checkout(u)
    else
      Api.answer_pre_checkout(u.pre_checkout_query.id)
    end
  end

  def apply_successful_payment(u) do
    if function_exported?(session(), :handle_successful_payment, 1) do
      session().handle_successful_payment(u)
    else
      Logger.info("Received successful_payment, no handler defined")
    end
  end
end
