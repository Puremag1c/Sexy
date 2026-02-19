defmodule Sexy.Bot.Api do
  @moduledoc """
  Low-level HTTP client for the Telegram Bot API.

  Every method builds a JSON (or multipart) body and POSTs it to
  `https://api.telegram.org/bot<TOKEN>/<method>`.

  Most users don't need to call this module directly — use `Sexy.Bot` which
  delegates here. For any Telegram method not explicitly wrapped, call `request/2`:

      body = Jason.encode!(%{chat_id: 123, text: "hi"})
      Sexy.Bot.Api.request(body, "sendMessage")

  ## Timeouts

    * JSON requests: 5 seconds (configurable via opts)
    * Multipart uploads: 20 seconds
    * Polling (`get_updates`): 10 seconds

  ## Return values

  All methods return decoded JSON as a map:

      %{"ok" => true, "result" => %{...}}
      %{"ok" => false, "description" => "..."}
  """

  alias Sexy.Utils
  require Logger

  @type tg_response :: map()

  # ── Internal HTTP ──────────────────────────────────────────────

  defp api_url do
    :persistent_term.get({Sexy.Bot, :api_url})
  end

  defp do_request(method, body, opts \\ []) do
    url = api_url() <> "/" <> method
    timeout = Keyword.get(opts, :timeout, 5_000)
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, recv_timeout: timeout) do
      {:ok, response} ->
        {:ok, decoded} = Jason.decode(response.body)
        decoded

      {:error, %{reason: reason}} ->
        %{"ok" => false, "description" => "HTTP error: #{reason}"}
    end
  end

  defp do_multipart(method, body, opts \\ []) do
    url = api_url() <> "/" <> method
    timeout = Keyword.get(opts, :timeout, 20_000)
    headers = [{"Content-Type", "multipart/form-data"}]

    case HTTPoison.post(url, {:multipart, body}, headers, recv_timeout: timeout) do
      {:ok, response} ->
        {:ok, decoded} = Jason.decode(response.body)
        decoded

      {:error, %{reason: reason}} ->
        %{"ok" => false, "description" => "HTTP error: #{reason}"}
    end
  end

  # ── Polling ────────────────────────────────────────────────────

  @spec get_updates(integer()) :: {:ok, [map()]} | {:error, atom()}
  def get_updates(offset) do
    url = api_url() <> "/getUpdates"
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{offset: offset, timeout: 1})

    case HTTPoison.post(url, body, headers, recv_timeout: 10_000) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> Utils.strip()
        |> Map.fetch(:result)

      {:error, response} ->
        {:error, response.reason}
    end
  end

  # ── Send Messages ──────────────────────────────────────────────

  @spec send_message(integer(), String.t()) :: tg_response()
  def send_message(chat_id, text) when is_integer(chat_id) do
    Jason.encode!(%{chat_id: chat_id, text: text, parse_mode: "HTML"})
    |> then(&do_request("sendMessage", &1))
  end

  @spec send_message(String.t()) :: tg_response()
  def send_message(body) when is_binary(body) do
    do_request("sendMessage", body)
  end

  @spec send_photo(String.t()) :: tg_response()
  def send_photo(body), do: do_request("sendPhoto", body)

  @spec send_video(String.t()) :: tg_response()
  def send_video(body), do: do_request("sendVideo", body)

  @spec send_animation(String.t()) :: tg_response()
  def send_animation(body), do: do_request("sendAnimation", body)

  @spec send_poll(String.t()) :: tg_response()
  def send_poll(body), do: do_request("sendPoll", body)

  @spec forward_message(String.t()) :: tg_response()
  def forward_message(body), do: do_request("forwardMessage", body)

  @spec copy_message(integer(), integer(), integer()) :: tg_response()
  def copy_message(chat_id, from_chat_id, message_id) do
    Jason.encode!(%{chat_id: chat_id, from_chat_id: from_chat_id, message_id: message_id})
    |> then(&do_request("copyMessage", &1))
  end

  @spec send_document(integer(), binary(), String.t(), String.t(), String.t()) :: tg_response()
  def send_document(chat_id, file, filename, text, reply_markup) do
    body = [
      {:file, file, {"form-data", [{"name", "document"}, {"filename", filename}]}, []},
      {"chat_id", to_string(chat_id)},
      {"caption", text},
      {"reply_markup", reply_markup},
      {"parse_mode", "HTML"}
    ]

    do_multipart("sendDocument", body)
  end

  @spec send_dice(integer(), String.t()) :: tg_response()
  def send_dice(chat_id, type) do
    emoji =
      case type do
        "dice" -> "🎲"
        "bowl" -> "🎳"
        "foot" -> "⚽"
        "bask" -> "🏀"
        "dart" -> "🎯"
        "777" -> "🎰"
      end

    Jason.encode!(%{chat_id: chat_id, emoji: emoji})
    |> then(&do_request("sendDice", &1))
  end

  @spec send_chat_action(integer(), String.t()) :: tg_response()
  def send_chat_action(chat_id, type) do
    action =
      case type do
        "txt" -> "typing"
        "pic" -> "upload_photo"
        "vid" -> "upload_video"
      end

    Jason.encode!(%{chat_id: chat_id, action: action})
    |> then(&do_request("sendChatAction", &1))
  end

  # ── Edit Messages ──────────────────────────────────────────────

  @spec edit_text(map()) :: tg_response()
  def edit_text(body) when is_map(body) do
    do_request("editMessageText", Jason.encode!(body))
  end

  @spec edit_reply_markup(String.t()) :: tg_response()
  def edit_reply_markup(body) when is_binary(body) do
    do_request("editMessageReplyMarkup", body)
  end

  @spec edit_media(String.t()) :: tg_response()
  def edit_media(body) do
    do_request("editMessageMedia", body)
  end

  # ── Delete Messages ────────────────────────────────────────────

  @spec delete_message(integer(), integer()) :: tg_response()
  def delete_message(chat_id, message_id) do
    Jason.encode!(%{chat_id: chat_id, message_id: message_id})
    |> then(&do_request("deleteMessage", &1))
  end

  # ── Callback Queries ───────────────────────────────────────────

  @spec answer_callback(String.t(), String.t(), boolean()) :: tg_response()
  def answer_callback(callback_id, text, alert) do
    Jason.encode!(%{callback_query_id: callback_id, text: text, show_alert: alert})
    |> then(&do_request("answerCallbackQuery", &1))
  end

  @spec answer_callback(map()) :: tg_response()
  def answer_callback(obj) when is_map(obj) do
    Jason.encode!(obj)
    |> then(&do_request("answerCallbackQuery", &1))
  end

  # ── User / Chat Info ───────────────────────────────────────────

  @spec get_me() :: tg_response()
  def get_me do
    url = api_url() <> "/getMe"
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.get(url, headers) do
      {:ok, response} ->
        {:ok, decoded} = Jason.decode(response.body)
        decoded

      {:error, %{reason: reason}} ->
        %{"ok" => false, "description" => "HTTP error: #{reason}"}
    end
  end

  @spec get_chat(integer()) :: tg_response()
  def get_chat(chat_id) do
    Jason.encode!(%{chat_id: chat_id})
    |> then(&do_request("getChat", &1))
  end

  @spec get_chat_member(integer(), integer()) :: tg_response()
  def get_chat_member(chat_id, user_id) do
    Jason.encode!(%{chat_id: chat_id, user_id: user_id})
    |> then(&do_request("getChatMember", &1))
  end

  @spec get_user_photo(integer()) :: String.t()
  def get_user_photo(user_id) do
    response =
      Jason.encode!(%{user_id: user_id, limit: "1"})
      |> then(&do_request("getUserProfilePhotos", &1))

    case response do
      %{"result" => %{"photos" => []}} ->
        "AgACAgIAAxkBAAIigmQVmbx7m-HI4Run-98wS9Si1Ul8AAJMxTEbUcywSDKEM2a7rqTUAQADAgADeAADLwQ"

      %{"result" => %{"photos" => [[_, _, %{"file_id" => pic}]]}} ->
        pic

      _ ->
        "AgACAgIAAxkBAAIigmQVmbx7m-HI4Run-98wS9Si1Ul8AAJMxTEbUcywSDKEM2a7rqTUAQADAgADeAADLwQ"
    end
  end

  # ── Bot Menu ───────────────────────────────────────────────────

  @spec set_commands(String.t()) :: tg_response()
  def set_commands(string) do
    commands =
      string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(fn el ->
        [cmd, desc] = String.split(el, "-")
        %{command: String.trim(cmd), description: String.trim(desc)}
      end)

    Jason.encode!(%{commands: commands})
    |> then(&do_request("setMyCommands", &1))
  end

  @spec delete_commands() :: tg_response()
  def delete_commands do
    Jason.encode!(%{scope: %{type: "default"}})
    |> then(&do_request("deleteMyCommands", &1))
  end

  # ── Payments ───────────────────────────────────────────────────

  @spec send_invoice(integer(), String.t(), String.t(), String.t(), String.t(), list()) ::
          tg_response()
  def send_invoice(chat_id, title, description, payload, currency, prices) do
    Jason.encode!(%{
      chat_id: chat_id,
      title: title,
      description: description,
      payload: payload,
      provider_token: "",
      currency: currency,
      prices: prices
    })
    |> then(&do_request("sendInvoice", &1))
  end

  @spec answer_pre_checkout(String.t()) :: tg_response()
  def answer_pre_checkout(pre_checkout_query_id) do
    Jason.encode!(%{pre_checkout_query_id: pre_checkout_query_id, ok: true})
    |> then(&do_request("answerPreCheckoutQuery", &1))
  end

  @spec refund_star_payment(integer(), String.t()) :: tg_response()
  def refund_star_payment(user_id, telegram_payment_charge_id) do
    Jason.encode!(%{user_id: user_id, telegram_payment_charge_id: telegram_payment_charge_id})
    |> then(&do_request("refundStarPayment", &1))
  end

  @spec wallet_init(String.t(), number(), String.t(), String.t(), integer()) :: tg_response()
  def wallet_init(currency, amount, external_id, description, telegram_user_id) do
    wallet_key = System.get_env("WALLET")

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Wpay-Store-Api-Key", wallet_key}
    ]

    body =
      Jason.encode!(%{
        amount: %{currencyCode: currency, amount: amount},
        description: description,
        externalId: external_id,
        timeoutSeconds: 2400,
        customerTelegramUserId: telegram_user_id
      })

    url = "https://pay.wallet.tg/wpay/store-api/v1/order"

    case HTTPoison.post(url, body, headers) do
      {:ok, response} ->
        {:ok, decoded} = Jason.decode(response.body)
        decoded

      {:error, %{reason: reason}} ->
        %{"ok" => false, "description" => "HTTP error: #{reason}"}
    end
  end

  # ── Universal ──────────────────────────────────────────────────

  @spec request(String.t(), String.t()) :: tg_response()
  def request(body, method), do: do_request(method, body)
end
