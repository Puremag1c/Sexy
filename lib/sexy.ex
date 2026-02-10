defmodule Sexy do
  @moduledoc """
  Sexy - Single-message Telegram Bot framework for Elixir.

  Start as a child of your application supervisor:

      {Sexy, token: "BOT_TOKEN", session: MyApp.TelegramSession}

  Public API: build/1, send/1-2, notify/2-3, plus Telegram API delegates.
  """

  use Supervisor
  import Kernel, except: [send: 2]

  def start_link(opts) do
    token = Keyword.fetch!(opts, :token)
    session = Keyword.fetch!(opts, :session)
    :persistent_term.put({Sexy, :api_url}, "https://api.telegram.org/bot#{token}")
    :persistent_term.put({Sexy, :session}, session)
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [Sexy.Poller]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ── Core API ──────────────────────────────────────────────────

  def build(map), do: Sexy.Screen.build(map)
  def send(object, opts \\ []), do: Sexy.Sender.deliver(object, opts)
  def notify(chat_id, msg, opts \\ []), do: Sexy.Notification.notify(chat_id, msg, opts)

  # ── Telegram API ──────────────────────────────────────────────

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
