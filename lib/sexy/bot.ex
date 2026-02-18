defmodule Sexy.Bot do
  @moduledoc """
  Telegram Bot API framework for Elixir.

  Start as a child of your application supervisor:

      {Sexy.Bot, token: "BOT_TOKEN", session: MyApp.TelegramSession}

  Public API: build/1, send/1-2, notify/2-3, plus Telegram API delegates.
  """

  use Supervisor
  import Kernel, except: [send: 2]

  def start_link(opts) do
    token = Keyword.fetch!(opts, :token)
    session = Keyword.fetch!(opts, :session)
    :persistent_term.put({Sexy.Bot, :api_url}, "https://api.telegram.org/bot#{token}")
    :persistent_term.put({Sexy.Bot, :session}, session)
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [Sexy.Bot.Poller]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ── Core API ──────────────────────────────────────────────────

  def build(map), do: Sexy.Bot.Screen.build(map)
  def send(object, opts \\ []), do: Sexy.Bot.Sender.deliver(object, opts)
  def notify(chat_id, msg, opts \\ []), do: Sexy.Bot.Notification.notify(chat_id, msg, opts)

  # ── Telegram API ──────────────────────────────────────────────

  defdelegate get_updates(offset), to: Sexy.Bot.Api
  defdelegate send_message(chat_id, text), to: Sexy.Bot.Api
  defdelegate send_message(body), to: Sexy.Bot.Api
  defdelegate send_photo(body), to: Sexy.Bot.Api
  defdelegate send_video(body), to: Sexy.Bot.Api
  defdelegate send_animation(body), to: Sexy.Bot.Api
  defdelegate send_poll(body), to: Sexy.Bot.Api
  defdelegate send_document(chat_id, file, name, text, kb), to: Sexy.Bot.Api
  defdelegate send_dice(chat_id, type), to: Sexy.Bot.Api
  defdelegate send_chat_action(chat_id, type), to: Sexy.Bot.Api
  defdelegate edit_text(body), to: Sexy.Bot.Api
  defdelegate edit_reply_markup(body), to: Sexy.Bot.Api
  defdelegate edit_media(body), to: Sexy.Bot.Api
  defdelegate delete_message(chat_id, message_id), to: Sexy.Bot.Api
  defdelegate answer_callback(callback_id, text, alert), to: Sexy.Bot.Api
  defdelegate answer_callback(obj), to: Sexy.Bot.Api
  defdelegate get_me(), to: Sexy.Bot.Api
  defdelegate get_chat(chat_id), to: Sexy.Bot.Api
  defdelegate get_chat_member(chat_id, user_id), to: Sexy.Bot.Api
  defdelegate get_user_photo(user_id), to: Sexy.Bot.Api
  defdelegate set_commands(string), to: Sexy.Bot.Api
  defdelegate delete_commands(), to: Sexy.Bot.Api
  defdelegate forward_message(body), to: Sexy.Bot.Api
  defdelegate copy_message(chat_id, from_chat_id, message_id), to: Sexy.Bot.Api
  defdelegate request(body, method), to: Sexy.Bot.Api
  defdelegate send_invoice(chat_id, title, description, payload, currency, prices), to: Sexy.Bot.Api
  defdelegate answer_pre_checkout(pre_checkout_query_id), to: Sexy.Bot.Api
  defdelegate refund_star_payment(user_id, charge_id), to: Sexy.Bot.Api
  defdelegate wallet_init(cur, sum, id, info, user), to: Sexy.Bot.Api
end
