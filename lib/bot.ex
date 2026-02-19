defmodule Sexy.Bot do
  @moduledoc """
  Telegram Bot API framework with the single-message UI pattern.

  ## Starting

  Add to your supervision tree with a bot token and a module implementing `Sexy.Bot.Session`:

      children = [
        {Sexy.Bot, token: System.get_env("BOT_TOKEN"), session: MyApp.Session}
      ]

  ## Core workflow

  The typical flow inside a session callback:

      # 1. Build an Object from a plain map
      object = Sexy.Bot.build(%{
        chat_id: chat_id,
        text: "Pick an option:",
        kb: %{inline_keyboard: [[%{text: "Go", callback_data: "/go"}]]}
      })

      # 2. Send it — old message is deleted, new one saved automatically
      Sexy.Bot.send(object)

  ## Single-message pattern

  Each chat has **one active message** (screen). When you call `send/1`, Sexy:

  1. Detects content type (text, photo, video, animation, document)
  2. Calls the appropriate Telegram API method
  3. Deletes the previous message via `Session.get_message_id/1`
  4. Saves the new message id via `Session.on_message_sent/4`

  This creates an app-like experience where the UI updates in place.

  ## Sending files

  To send a document, set `media: "file"` with `file` and `filename` fields:

      Sexy.Bot.build(%{
        chat_id: chat_id,
        media: "file",
        file: File.read!("report.csv"),
        filename: "report.csv",
        text: "Here is your report"
      })
      |> Sexy.Bot.send()

  ## Notifications

  Use `notify/3` for messages that don't replace the current screen:

      # Overlay with dismiss button
      Sexy.Bot.notify(chat_id, %{text: "Saved!"})

      # Replace current screen
      Sexy.Bot.notify(chat_id, %{text: "Payment received!"}, replace: true)

      # With navigation button
      Sexy.Bot.notify(chat_id, %{text: "New order!"}, navigate: {"View", "/order id=42"})

  ## Telegram API

  All standard Telegram Bot API methods are available as delegates:
  `send_message/2`, `send_photo/1`, `edit_text/1`, `delete_message/2`,
  `answer_callback/3`, `send_invoice/6`, and more. For any method not wrapped,
  use `request/2`.
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

  @doc """
  Convert a map (or list of maps) into `Sexy.Utils.Object` struct(s).

  Accepts any map with Object fields: `:chat_id`, `:text`, `:media`, `:kb`,
  `:entity`, `:update_data`, `:file`, `:filename`.

  ## Example

      Sexy.Bot.build(%{chat_id: 123, text: "Hello!"})
      #=> %Sexy.Utils.Object{chat_id: 123, text: "Hello!", ...}
  """
  def build(map), do: Sexy.Bot.Screen.build(map)

  @doc """
  Send an Object (or list of Objects) to Telegram.

  Handles the full single-message lifecycle: detect type, call API, delete old
  message, save new message id via Session.

  ## Options

    * `:update_mid` — `true` (default) to manage the active message,
      `false` to send without touching screen state

  ## Examples

      # Send a text screen
      %{chat_id: id, text: "Hello"}
      |> Sexy.Bot.build()
      |> Sexy.Bot.send()

      # Send without replacing the current screen
      Sexy.Bot.send(object, update_mid: false)
  """
  def send(object, opts \\ []), do: Sexy.Bot.Sender.deliver(object, opts)

  @doc """
  Send a notification message with optional dismiss/navigate buttons.

  See `Sexy.Bot.Notification` for full option details.
  """
  def notify(chat_id, msg, opts \\ []), do: Sexy.Bot.Notification.notify(chat_id, msg, opts)

  # ── Telegram API ──────────────────────────────────────────────

  @doc "Poll for updates starting from the given offset. See `Sexy.Bot.Api.get_updates/1`."
  defdelegate get_updates(offset), to: Sexy.Bot.Api

  @doc "Send a text message with HTML parse mode."
  defdelegate send_message(chat_id, text), to: Sexy.Bot.Api

  @doc "Send a pre-encoded JSON body as a message."
  defdelegate send_message(body), to: Sexy.Bot.Api

  @doc "Send a photo by file_id. Body is a JSON-encoded string."
  defdelegate send_photo(body), to: Sexy.Bot.Api

  @doc "Send a video by file_id. Body is a JSON-encoded string."
  defdelegate send_video(body), to: Sexy.Bot.Api

  @doc "Send an animation (GIF) by file_id. Body is a JSON-encoded string."
  defdelegate send_animation(body), to: Sexy.Bot.Api

  @doc "Send a poll. Body is a JSON-encoded string."
  defdelegate send_poll(body), to: Sexy.Bot.Api

  @doc """
  Send a document as multipart upload.

  ## Parameters

    * `chat_id` — Telegram chat id
    * `file` — binary file content
    * `name` — filename shown to the user
    * `text` — caption (HTML)
    * `kb` — JSON-encoded reply markup
  """
  defdelegate send_document(chat_id, file, name, text, kb), to: Sexy.Bot.Api

  @doc """
  Send a dice animation. Type is one of: `"dice"`, `"bowl"`, `"foot"`,
  `"bask"`, `"dart"`, `"777"`.
  """
  defdelegate send_dice(chat_id, type), to: Sexy.Bot.Api

  @doc """
  Show a chat action indicator. Type is one of: `"txt"` (typing),
  `"pic"` (uploading photo), `"vid"` (uploading video).
  """
  defdelegate send_chat_action(chat_id, type), to: Sexy.Bot.Api

  @doc "Edit message text. Body is a map with `:chat_id`, `:message_id`, `:text`, etc."
  defdelegate edit_text(body), to: Sexy.Bot.Api

  @doc "Edit message reply markup (buttons). Body is a JSON-encoded string."
  defdelegate edit_reply_markup(body), to: Sexy.Bot.Api

  @doc "Edit message media. Body is a JSON-encoded string."
  defdelegate edit_media(body), to: Sexy.Bot.Api

  @doc "Delete a message by chat_id and message_id."
  defdelegate delete_message(chat_id, message_id), to: Sexy.Bot.Api

  @doc "Answer a callback query with text and optional alert popup."
  defdelegate answer_callback(callback_id, text, alert), to: Sexy.Bot.Api

  @doc "Answer a callback query with a pre-built map."
  defdelegate answer_callback(obj), to: Sexy.Bot.Api

  @doc "Get bot info (`getMe` API method)."
  defdelegate get_me(), to: Sexy.Bot.Api

  @doc "Get chat info by chat_id."
  defdelegate get_chat(chat_id), to: Sexy.Bot.Api

  @doc "Get chat member info."
  defdelegate get_chat_member(chat_id, user_id), to: Sexy.Bot.Api

  @doc "Get the highest-resolution profile photo file_id for a user."
  defdelegate get_user_photo(user_id), to: Sexy.Bot.Api

  @doc ~S"""
  Set bot menu commands from a comma-separated string.

  ## Example

      Sexy.Bot.set_commands("start - Launch bot, help - Show help")
  """
  defdelegate set_commands(string), to: Sexy.Bot.Api

  @doc "Delete all bot menu commands."
  defdelegate delete_commands(), to: Sexy.Bot.Api

  @doc "Forward a message. Body is a JSON-encoded string."
  defdelegate forward_message(body), to: Sexy.Bot.Api

  @doc "Copy a message to another chat."
  defdelegate copy_message(chat_id, from_chat_id, message_id), to: Sexy.Bot.Api

  @doc """
  Call any Telegram Bot API method by name.

  ## Example

      body = Jason.encode!(%{chat_id: 123, text: "hi"})
      Sexy.Bot.request(body, "sendMessage")
  """
  defdelegate request(body, method), to: Sexy.Bot.Api

  @doc "Send a Telegram Stars invoice."
  defdelegate send_invoice(chat_id, title, description, payload, currency, prices), to: Sexy.Bot.Api

  @doc "Confirm a pre-checkout query (for Telegram Payments)."
  defdelegate answer_pre_checkout(pre_checkout_query_id), to: Sexy.Bot.Api

  @doc "Refund a Telegram Stars payment."
  defdelegate refund_star_payment(user_id, charge_id), to: Sexy.Bot.Api

  @doc "Create a Wallet.tg payment order. Reads `WALLET` env var for the API key."
  defdelegate wallet_init(cur, sum, id, info, user), to: Sexy.Bot.Api
end
