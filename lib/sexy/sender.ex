defmodule Sexy.Sender do
  @moduledoc """
  Sends Object to Telegram. Handles type detection, mid lifecycle, session updates.
  """

  alias Sexy.{Api, Utils}
  require Logger

  @doc """
  Send an Object (or list of Objects) to Telegram.

  Options:
    - `update_mid: true` (default) — delete previous message, save new mid via Session
    - `update_mid: false` — send without touching current screen state
  """
  def deliver(items, opts \\ [])

  def deliver(items, opts) when is_list(items) do
    Enum.each(items, &deliver(&1, opts))
  end

  def deliver(%{chat_id: nil} = item, _opts) do
    Logger.warning("Sexy.Sender | chat_id is nil\n#{inspect(item, pretty: true)}")
  end

  def deliver(object, opts) do
    update_mid = Keyword.get(opts, :update_mid, true)
    objtype = Utils.Object.detect_object_type(object)

    {parse, text} =
      if object.entity == [],
        do: {"HTML", object.text},
        else: {"", object.text}

    message =
      cond do
        objtype == "txt" ->
          %{
            chat_id: object.chat_id,
            text: text,
            entities: object.entity,
            parse_mode: parse,
            reply_markup: object.kb
          }
          |> Jason.encode!()
          |> Api.send_message()

        objtype == "file" ->
          Api.send_document(
            object.chat_id,
            object.file,
            object.filename,
            object.text,
            Jason.encode!(object.kb)
          )

        true ->
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

    case message do
      %{"ok" => true} ->
        if update_mid do
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

      error ->
        Logger.error("Sexy.Sender | Failed to send message: #{error["description"]}")
        Logger.info(inspect(object, pretty: true))
    end

    message
  end

  defp session_module do
    :persistent_term.get({Sexy, :session})
  end
end
