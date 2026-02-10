defmodule Sexy do
  @moduledoc """
  Sexy - Telegram Bot framework for Elixir.

  Public API delegated to Sexy.Api.
  """

  # ── Telegram API ────────────────────────────────────────────────

  defdelegate get_updates(offset), to: Sexy.Api
  defdelegate send_message(chat_id, text), to: Sexy.Api
  defdelegate send_message(body), to: Sexy.Api
  defdelegate send_photo(body), to: Sexy.Api
  defdelegate send_video(body), to: Sexy.Api
  defdelegate send_animation(body), to: Sexy.Api
  defdelegate send_poll(body), to: Sexy.Api
  defdelegate send_document(chat_id, file, name, text, kb), to: Sexy.Api
  defdelegate send_dice(chat_id, type), to: Sexy.Api
  defdelegate send_chat_action(chat_id, type), to: Sexy.Api
  defdelegate edit_text(body), to: Sexy.Api
  defdelegate edit_reply_markup(body), to: Sexy.Api
  defdelegate edit_media(body), to: Sexy.Api
  defdelegate delete_message(chat_id, message_id), to: Sexy.Api
  defdelegate answer_callback(callback_id, text, alert), to: Sexy.Api
  defdelegate answer_callback(obj), to: Sexy.Api
  defdelegate get_me(), to: Sexy.Api
  defdelegate get_chat(chat_id), to: Sexy.Api
  defdelegate get_chat_member(chat_id, user_id), to: Sexy.Api
  defdelegate get_user_photo(user_id), to: Sexy.Api
  defdelegate set_commands(string), to: Sexy.Api
  defdelegate delete_commands(), to: Sexy.Api
  defdelegate forward_message(body), to: Sexy.Api
  defdelegate copy_message(chat_id, from_chat_id, message_id), to: Sexy.Api
  defdelegate request(body, method), to: Sexy.Api
  defdelegate wallet_init(cur, sum, id, info, user), to: Sexy.Api
end
