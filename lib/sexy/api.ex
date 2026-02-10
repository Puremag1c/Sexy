defmodule Sexy.Api do
  @moduledoc """
  Telegram Bot API client with readable method names.
  All methods use a single `do_request/3` internally.
  """

  alias Sexy.Utils
  require Logger

  # ── Internal HTTP ──────────────────────────────────────────────

  defp api_url do
    Application.get_env(:sexy, :link) <> Application.get_env(:sexy, :token)
  end

  defp api_url(token) do
    Application.get_env(:sexy, :link) <> token
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

  def send_message(chat_id, text) when is_integer(chat_id) do
    Jason.encode!(%{chat_id: chat_id, text: text, parse_mode: "HTML"})
    |> then(&do_request("sendMessage", &1))
  end

  def send_message(body) when is_binary(body) do
    do_request("sendMessage", body)
  end

  def send_photo(body), do: do_request("sendPhoto", body)
  def send_video(body), do: do_request("sendVideo", body)
  def send_animation(body), do: do_request("sendAnimation", body)
  def send_poll(body), do: do_request("sendPoll", body)
  def forward_message(body), do: do_request("forwardMessage", body)

  def copy_message(chat_id, from_chat_id, message_id) do
    Jason.encode!(%{chat_id: chat_id, from_chat_id: from_chat_id, message_id: message_id})
    |> then(&do_request("copyMessage", &1))
  end

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

  def edit_text(body) when is_map(body) do
    do_request("editMessageText", Jason.encode!(body))
  end

  def edit_reply_markup(body) when is_binary(body) do
    do_request("editMessageReplyMarkup", body)
  end

  def edit_media(body) do
    do_request("editMessageMedia", body)
  end

  # ── Delete Messages ────────────────────────────────────────────

  def delete_message(chat_id, message_id) do
    Jason.encode!(%{chat_id: chat_id, message_id: message_id})
    |> then(&do_request("deleteMessage", &1))
  end

  # ── Callback Queries ───────────────────────────────────────────

  def answer_callback(callback_id, text, alert) do
    Jason.encode!(%{callback_query_id: callback_id, text: text, show_alert: alert})
    |> then(&do_request("answerCallbackQuery", &1))
  end

  def answer_callback(obj) when is_map(obj) do
    Jason.encode!(obj)
    |> then(&do_request("answerCallbackQuery", &1))
  end

  # ── User / Chat Info ───────────────────────────────────────────

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

  def get_chat(chat_id) do
    Jason.encode!(%{chat_id: chat_id})
    |> then(&do_request("getChat", &1))
  end

  def get_chat_member(chat_id, user_id) do
    Jason.encode!(%{chat_id: chat_id, user_id: user_id})
    |> then(&do_request("getChatMember", &1))
  end

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

  def delete_commands do
    Jason.encode!(%{scope: %{type: "default"}})
    |> then(&do_request("deleteMyCommands", &1))
  end

  # ── Payments ───────────────────────────────────────────────────

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

  def request(body, method), do: do_request(method, body)
end
