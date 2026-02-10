defmodule Sexy.Poller do
  use GenServer
  require Logger

  # Server

  def start_link(_g) do
    Logger.log(:info, "Started poller")
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    update()
    {:ok, 0}
  end

  def handle_cast(:update, offset) do
    new_offset =
      Sexy.Api.get_updates(offset)
      |> process_messages

    {:noreply, new_offset + 1, 100}
  end

  def handle_info(:timeout, offset) do
    update()
    {:noreply, offset}
  end

  # Client

  def update do
    GenServer.cast(__MODULE__, :update)
  end

  # Helpers

  defp process_messages({:ok, []}), do: -1

  defp process_messages({:ok, results}) do
    # По моему эта конструкция так и не заработала, протестировать.
    # Task.async_stream(results, fn m -> process_message(m) end, maxconcurrency: 10, timeout: 200000) |> Stream.run()

    for el <- results, do: match_update(el)

    results
    |> Enum.map(fn %{update_id: id} -> id end)
    |> List.last()
  end

  defp process_messages({:error, error}) do
    Logger.log(:error, Atom.to_string(error))

    -1
  end

  defp process_messages(:error) do
    Logger.log(:error, "КАКАЯ ТО ХУЙНЯ В ПОЛЛЕРЕ")

    -1
  end

  defp match_update(%{message: message} = u) do
    if Map.has_key?(message, :text) and String.first(u.message.text) == "/",
      do: Task.start(fn -> apply_command(u) end),
      else: Task.start(fn -> apply_message(u) end)
  end

  defp match_update(%{callback_query: query} = u) do
    case Sexy.Utils.Bot.get_command_name(query.data) do
      "_delete" ->
        Task.start(fn -> handle_builtin_delete(query) end)

      _ ->
        Task.start(fn -> apply_query(u) end)
    end
  end

  defp match_update(%{poll: _poll} = u),
    do: Task.start(fn -> apply_poll(u) end)

  defp match_update(%{my_chat_member: _chat_member} = u),
    do: Task.start(fn -> apply_chat_member(u) end)

  defp match_update(u),
    do: Logger.warning("Unknown update in poller\n\n#{inspect(u, pretty: true)}")

  defp handle_builtin_delete(query) do
    params = Sexy.Utils.get_query(query.data)
    chat_id = query.message.chat.id
    Sexy.Api.delete_message(chat_id, params.mid)
    Sexy.Api.answer_callback(query.id, "", false)
  end


  def apply_command(u) do
    app_name = Application.get_application(__MODULE__)
    module = Application.get_env(app_name, :handler_module)
    func = Application.get_env(app_name, :command_handler)
    apply(module, func, [u])
  end

  def apply_message(u) do
    app_name = Application.get_application(__MODULE__)
    module = Application.get_env(app_name, :handler_module)
    func = Application.get_env(app_name, :message_handler)
    apply(module, func, [u])
  end

  def apply_query(u) do
    app_name = Application.get_application(__MODULE__)
    module = Application.get_env(app_name, :handler_module)
    func = Application.get_env(app_name, :query_handler)
    apply(module, func, [u])
  end

  def apply_poll(u) do
    app_name = Application.get_application(__MODULE__)
    module = Application.get_env(app_name, :handler_module)
    func = Application.get_env(app_name, :poll_handler)
    apply(module, func, [u])
  end

  def apply_chat_member(u) do
    app_name = Application.get_application(__MODULE__)
    module = Application.get_env(app_name, :handler_module)
    func = Application.get_env(app_name, :chat_member_handler)
    apply(module, func, [u])
  end

end
