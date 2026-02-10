defmodule Sexy do
  @moduledoc """
  Sexy - Telegram Bot framework for Elixir.

  Public API delegated to Sexy.Api.
  Legacy short names kept as delegates for backward compatibility during migration.
  """

  # ── New readable API (delegates) ───────────────────────────────

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

  # ── Legacy short names (backward compat, will be removed) ─────

  defdelegate gogo(offset), to: Sexy.Api, as: :get_updates
  defdelegate pm(id, text), to: Sexy.Api, as: :send_message
  defdelegate pm(body), to: Sexy.Api, as: :send_message
  defdelegate p(body), to: Sexy.Api, as: :send_photo
  defdelegate v(body), to: Sexy.Api, as: :send_video
  defdelegate a(body), to: Sexy.Api, as: :send_animation
  defdelegate quiz(body), to: Sexy.Api, as: :send_poll
  defdelegate uf(id, file, name, text, kb), to: Sexy.Api, as: :send_document
  defdelegate um(body), to: Sexy.Api, as: :edit_text
  defdelegate ui(body), to: Sexy.Api, as: :edit_reply_markup
  defdelegate umm(body), to: Sexy.Api, as: :edit_media
  defdelegate dm(id, mid), to: Sexy.Api, as: :delete_message
  defdelegate shout(id, text, alert), to: Sexy.Api, as: :answer_callback
  defdelegate shout(obj), to: Sexy.Api, as: :answer_callback
  defdelegate getme(), to: Sexy.Api, as: :get_me
  defdelegate getu(id), to: Sexy.Api, as: :get_chat
  defdelegate uph(id), to: Sexy.Api, as: :get_user_photo
  defdelegate setmenu(string), to: Sexy.Api, as: :set_commands
  defdelegate delmenu(), to: Sexy.Api, as: :delete_commands
  defdelegate dice(id, type), to: Sexy.Api, as: :send_dice
  defdelegate act(id, type), to: Sexy.Api, as: :send_chat_action
  defdelegate share(body), to: Sexy.Api, as: :forward_message
  defdelegate copy(where, from, msg), to: Sexy.Api, as: :copy_message
  defdelegate uni(body, method), to: Sexy.Api, as: :request
  defdelegate walletInit(cur, sum, id, info, user), to: Sexy.Api, as: :wallet_init
end
