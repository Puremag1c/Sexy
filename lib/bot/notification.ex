defmodule Sexy.Bot.Notification do
  @moduledoc """
  Send notification messages with dismiss and navigate buttons.

  Notifications are messages sent to a chat that are separate from the main screen flow.
  They support two modes:

  ## Overlay mode (default)

  Sends a message **without** replacing the current screen. Adds a dismiss button
  so the user can remove the notification:

      Sexy.Bot.notify(chat_id, %{text: "Action completed!"})

  ## Replace mode

  Replaces the current active screen. The notification **becomes** the new screen
  (mid is updated via Session):

      Sexy.Bot.notify(chat_id, %{text: "Payment received!"}, replace: true)

  ## Navigation buttons

  Add a button that deletes the notification and navigates to a command.
  Sexy wraps this into the built-in `/_transit` route:

      Sexy.Bot.notify(chat_id, %{text: "New order #42"},
        navigate: {"View Order", "/order id=42"}
      )

  You can also pass a function for custom callback data:

      Sexy.Bot.notify(chat_id, %{text: "Alert"},
        navigate: {"Details", fn mid -> "/show mid=\#{mid}" end}
      )

  ## Options

    * `:replace` — `false` (default) for overlay, `true` to replace screen
    * `:navigate` — `{button_text, path}` or `{button_text, fn mid -> callback end}`
    * `:dismiss_text` — custom dismiss button text (default: `"OK"`)
    * `:extra_buttons` — additional button rows as `[[%{text: ..., callback_data: ...}]]`
  """

  alias Sexy.Bot.{Api, Screen, Sender}
  require Logger

  @doc """
  Send a notification to a chat.

  `message` is a map like `%{text: "..."}` or `%{media: "file", file: "...", filename: "..."}`.

  Options:
    - `navigate: {"Button Text", "/command query"}` — transit button (auto-wraps to /_transit)
    - `navigate: {"Button Text", fn mid -> "..." end}` — custom callback with mid injection
    - `replace: false` (default) — overlay mode, dismissable
    - `replace: true` — replaces current screen, no dismiss
    - `extra_buttons: [[%{text: ..., ...}]]` — extra button rows appended after navigate/dismiss
    - `dismiss_text: "text"` — custom dismiss button text
  """
  @type navigate_opt :: {String.t(), String.t()} | {String.t(), (integer() -> String.t())}

  @type notify_opt ::
          {:replace, boolean()}
          | {:navigate, navigate_opt()}
          | {:dismiss_text, String.t()}
          | {:extra_buttons, [[map()]]}

  @spec notify(integer(), map(), [notify_opt()]) :: map()
  def notify(chat_id, message, opts \\ []) do
    replace = Keyword.get(opts, :replace, false)

    object =
      message
      |> Map.put(:chat_id, chat_id)
      |> Screen.build()

    response = Sender.deliver(object, update_mid: replace)

    case response do
      %{"ok" => true} ->
        mid = response["result"]["message_id"]
        buttons = build_buttons(chat_id, mid, opts)
        edit_buttons(chat_id, mid, buttons)

      _ ->
        Logger.warning("Sexy.Bot.Notification | send failed: #{inspect(response)}")
    end

    response
  end

  defp build_buttons(_chat_id, mid, opts) do
    replace = Keyword.get(opts, :replace, false)
    navigate = Keyword.get(opts, :navigate, nil)
    extra_buttons = Keyword.get(opts, :extra_buttons, [])
    dismiss_text = Keyword.get(opts, :dismiss_text, default_dismiss_text())

    nav_row =
      case navigate do
        {text, callback_fn} when is_function(callback_fn) ->
          [[%{text: text, callback_data: callback_fn.(mid)}]]

        {text, path} when is_binary(path) ->
          [[%{text: text, callback_data: transit_callback(mid, path)}]]

        nil ->
          []
      end

    dismiss_row =
      if replace,
        do: [],
        else: [[%{text: dismiss_text, callback_data: "/_delete mid=#{mid}"}]]

    nav_row ++ dismiss_row ++ extra_buttons
  end

  defp edit_buttons(_chat_id, _mid, []), do: :ok

  defp edit_buttons(chat_id, mid, buttons) do
    %{
      chat_id: chat_id,
      message_id: mid,
      reply_markup: %{inline_keyboard: buttons}
    }
    |> Jason.encode!()
    |> Api.edit_reply_markup()
  end

  defp transit_callback(mid, path) do
    trimmed = String.trim_leading(path, "/")

    {cmd, query_part} =
      case String.split(trimmed, " ", parts: 2) do
        [cmd, query] when query != "" -> {cmd, "-" <> query}
        [cmd | _] -> {cmd, ""}
      end

    "/_transit mid=#{mid}-cmd=#{cmd}#{query_part}"
  end

  defp default_dismiss_text, do: "OK"
end
