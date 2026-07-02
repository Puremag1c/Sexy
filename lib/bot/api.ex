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

    HTTPoison.post(url, body, headers, recv_timeout: timeout) |> decode_response()
  end

  defp do_multipart(method, body, opts \\ []) do
    url = api_url() <> "/" <> method
    timeout = Keyword.get(opts, :timeout, 20_000)
    headers = [{"Content-Type", "multipart/form-data"}]

    HTTPoison.post(url, {:multipart, body}, headers, recv_timeout: timeout) |> decode_response()
  end

  defp decode_response({:ok, response}), do: Jason.decode!(response.body)

  defp decode_response({:error, %{reason: reason}}),
    do: %{"ok" => false, "description" => "HTTP error: #{reason}"}

  # ── Polling ────────────────────────────────────────────────────

  @spec get_updates(integer()) :: {:ok, [map()]} | :error | {:error, term()}
  def get_updates(offset) do
    url = api_url() <> "/getUpdates"
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{offset: offset, timeout: 1})

    case HTTPoison.post(url, body, headers, recv_timeout: 10_000) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, json} -> json |> Utils.strip() |> Map.fetch(:result)
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_status, status}}

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

  @spec send_photo(integer(), binary(), String.t(), String.t(), String.t()) :: tg_response()
  def send_photo(chat_id, file, filename, text, reply_markup) do
    body = [
      {"photo", file, {"form-data", [{"name", "photo"}, {"filename", filename}]}, []},
      {"chat_id", to_string(chat_id)},
      {"caption", text},
      {"reply_markup", reply_markup},
      {"parse_mode", "HTML"}
    ]

    do_multipart("sendPhoto", body)
  end

  @spec send_video(String.t()) :: tg_response()
  def send_video(body), do: do_request("sendVideo", body)

  @spec send_video(integer(), binary(), String.t(), String.t(), String.t()) :: tg_response()
  def send_video(chat_id, file, filename, text, reply_markup) do
    body = [
      {"video", file, {"form-data", [{"name", "video"}, {"filename", filename}]}, []},
      {"chat_id", to_string(chat_id)},
      {"caption", text},
      {"reply_markup", reply_markup},
      {"parse_mode", "HTML"}
    ]

    do_multipart("sendVideo", body)
  end

  @spec send_animation(String.t()) :: tg_response()
  def send_animation(body), do: do_request("sendAnimation", body)

  @spec send_animation(integer(), binary(), String.t(), String.t(), String.t()) :: tg_response()
  def send_animation(chat_id, file, filename, text, reply_markup) do
    body = [
      {"animation", file, {"form-data", [{"name", "animation"}, {"filename", filename}]}, []},
      {"chat_id", to_string(chat_id)},
      {"caption", text},
      {"reply_markup", reply_markup},
      {"parse_mode", "HTML"}
    ]

    do_multipart("sendAnimation", body)
  end

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
      {"document", file, {"form-data", [{"name", "document"}, {"filename", filename}]}, []},
      {"chat_id", to_string(chat_id)},
      {"caption", text},
      {"reply_markup", reply_markup},
      {"parse_mode", "HTML"}
    ]

    do_multipart("sendDocument", body)
  end

  @doc ~S"""
  Send a dice animation. `emoji` is one of Telegram's dice emoji:
  `"🎲"`, `"🎯"`, `"🏀"`, `"⚽"`, `"🎳"`, `"🎰"`.
  """
  @spec send_dice(integer(), String.t()) :: tg_response()
  def send_dice(chat_id, emoji) do
    Jason.encode!(%{chat_id: chat_id, emoji: emoji})
    |> then(&do_request("sendDice", &1))
  end

  @doc ~S"""
  Show a chat action indicator. `action` is a Telegram action string, e.g.
  `"typing"`, `"upload_photo"`, `"upload_video"`, `"record_voice"`.
  """
  @spec send_chat_action(integer(), String.t()) :: tg_response()
  def send_chat_action(chat_id, action) do
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

  @doc """
  Delete a message from a chat.

  ## Options

    * `:after` — delay in seconds before deleting. Accepts integers and floats.
      When provided, deletion runs asynchronously in a background task.

  ## Examples

      # Immediate deletion
      delete_message(chat_id, message_id)

      # Delete after 5 seconds
      delete_message(chat_id, message_id, after: 5)

      # Delete after half a second
      delete_message(chat_id, message_id, after: 0.5)

  """
  @spec delete_message(integer(), integer(), keyword()) :: tg_response() | {:ok, pid()}
  def delete_message(chat_id, message_id, opts \\ []) do
    case Keyword.get(opts, :after) do
      nil ->
        Jason.encode!(%{chat_id: chat_id, message_id: message_id})
        |> then(&do_request("deleteMessage", &1))

      seconds when is_number(seconds) ->
        Task.start(fn ->
          Process.sleep(trunc(seconds * 1000))
          delete_message(chat_id, message_id)
        end)
    end
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

    HTTPoison.get(url, headers) |> decode_response()
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

  @spec get_user_photo(integer()) :: String.t() | nil
  def get_user_photo(user_id) do
    response =
      Jason.encode!(%{user_id: user_id, limit: "1"})
      |> then(&do_request("getUserProfilePhotos", &1))

    case response do
      %{"result" => %{"photos" => [sizes | _]}} when sizes != [] ->
        List.last(sizes)["file_id"]

      _ ->
        nil
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

  # ── Universal ──────────────────────────────────────────────────

  @spec request(String.t(), String.t()) :: tg_response()
  def request(body, method), do: do_request(method, body)
end
