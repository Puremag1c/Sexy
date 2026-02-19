defmodule Sexy.Bot.Sender do
  @moduledoc """
  Delivers `Sexy.Utils.Object` structs to Telegram and manages the message lifecycle.

  This is the engine behind `Sexy.Bot.send/2`. You typically don't call it directly.

  ## How it works

  1. Detects content type via `Sexy.Utils.Object.detect_object_type/1`
  2. Calls the appropriate `Sexy.Bot.Api` method (`send_message`, `send_photo`,
     `send_document`, etc.)
  3. If `update_mid: true` (default):
     - Deletes the old message via `Session.get_message_id/1`
     - Saves the new message id via `Session.on_message_sent/4`

  ## Content type detection

  | `Object.media` value | Type | API method |
  |---|---|---|
  | `nil` | text | `sendMessage` |
  | `"file"` | document | `sendDocument` (multipart) |
  | starts with `"A"` | photo | `sendPhoto` |
  | starts with `"B"` | video | `sendVideo` |
  | starts with `"C"` | animation | `sendAnimation` |
  """

  alias Sexy.Bot.Api
  alias Sexy.Utils
  require Logger

  @doc """
  Send an Object (or list of Objects) to Telegram.

  ## Options

    * `:update_mid` — `true` (default) to delete old message and save new mid,
      `false` to send without modifying screen state
  """
  @type tg_response :: map()

  @spec deliver(Sexy.Utils.Object.t() | [Sexy.Utils.Object.t()], keyword()) :: tg_response() | :ok
  def deliver(items, opts \\ [])

  def deliver(items, opts) when is_list(items) do
    Enum.each(items, &deliver(&1, opts))
  end

  def deliver(%{chat_id: nil} = item, _opts) do
    Logger.warning("Sexy.Bot.Sender | chat_id is nil\n#{inspect(item, pretty: true)}")
  end

  def deliver(object, opts) do
    update_mid = Keyword.get(opts, :update_mid, true)
    objtype = Utils.Object.detect_object_type(object)
    {parse, text} = parse_mode(object)
    message = send_by_type(objtype, object, parse, text)

    case message do
      %{"ok" => true} ->
        if update_mid, do: update_screen(objtype, object, message)

      error ->
        Logger.error("Sexy.Bot.Sender | Failed to send message: #{error["description"]}")
        Logger.info(inspect(object, pretty: true))
    end

    message
  end

  defp parse_mode(%{entity: [], text: text}), do: {"HTML", text}
  defp parse_mode(%{text: text}), do: {"", text}

  defp send_by_type("txt", object, parse, text) do
    %{
      chat_id: object.chat_id,
      text: text,
      entities: object.entity,
      parse_mode: parse,
      reply_markup: object.kb
    }
    |> Jason.encode!()
    |> Api.send_message()
  end

  defp send_by_type("file", object, _parse, _text) do
    Api.send_document(
      object.chat_id,
      object.file,
      object.filename,
      object.text,
      Jason.encode!(object.kb)
    )
  end

  defp send_by_type(objtype, object, parse, text) do
    %{
      objtype => object.media,
      chat_id: object.chat_id,
      caption_entities: object.entity,
      parse_mode: parse,
      caption: text,
      reply_markup: object.kb
    }
    |> Jason.encode!()
    |> Api.request("send" <> String.capitalize(objtype))
  end

  defp update_screen(objtype, object, message) do
    mtype = if objtype == "txt", do: "txt", else: "media"
    session = session_module()
    old_mid = session.get_message_id(object.chat_id)
    if old_mid, do: Api.delete_message(object.chat_id, old_mid)

    session.on_message_sent(
      object.chat_id,
      message["result"]["message_id"],
      mtype,
      object.update_data
    )
  end

  defp session_module do
    :persistent_term.get({Sexy.Bot, :session})
  end
end
