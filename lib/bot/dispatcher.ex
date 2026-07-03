defmodule Sexy.Bot.Dispatcher do
  @moduledoc """
  Serial update executor — your `Sexy.Bot.Session` callbacks run here.

  The `Sexy.Bot.Poller` routes each update to one of the partitions
  (a `PartitionSupervisor` pool) keyed by chat id, so updates of the **same
  chat are processed in order** — the session state machine never sees them
  race — while different chats run concurrently across partitions.

  A crashing handler is logged and the partition's queue moves on: isolation
  without losing ordering.

  Note the ceiling: a slow handler delays other chats that hash into the same
  partition (head-of-line blocking).
  """
  # ponytail: hashed pool → HOL blocking within a partition. Per-chat
  # processes are the upgrade if that matters.
  use GenServer

  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok)

  @impl true
  def init(:ok), do: {:ok, :ok}

  @impl true
  def handle_cast({:dispatch, fun}, state) do
    try do
      fun.()
    rescue
      e ->
        Logger.error(
          "Sexy.Bot update handler crashed: #{Exception.format(:error, e, __STACKTRACE__)}"
        )
    catch
      kind, reason ->
        Logger.error("Sexy.Bot update handler #{kind}: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
