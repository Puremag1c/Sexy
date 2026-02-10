defmodule Sexy.Notification do
  @moduledoc """
  Send notification messages with dismiss/navigate buttons.

  Supports two modes:
  - overlay (replace: false) — sends without touching current screen, adds dismiss button
  - replace (replace: true) — replaces current screen, saves new mid, no dismiss button
  """

  alias Sexy.{Api, Sender, Screen}
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
        Logger.warning("Sexy.Notification | send failed: #{inspect(response)}")
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
