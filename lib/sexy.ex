defmodule Sexy do
  @moduledoc """
  Sexy - main module for methods to communicate with TGBot API.
  Folder Sexy - bunch of tooling for all pretty functional of my bots
  """

  alias Sexy.Utils
  @wallet System.get_env("WALLET")
  require Logger

  # universal method, for future using in constructors

  def gen_link() do
    app_name = Application.get_application(__MODULE__)
    Application.get_env(app_name, :link) <> Application.get_env(app_name, :token)
  end

  def gen_link(token) do
    app_name = Application.get_application(__MODULE__)
    Application.get_env(app_name, :link) <> token
  end

  def uni(body, method) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/" <> method

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # polling get updates
  def gogo(offset) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/getUpdates"
    options = [recv_timeout: 10_000]

    body =
      Jason.encode!(%{
        offset: offset,
        timeout: 1
      })

    case HTTPoison.post(url, body, headers, options) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> Utils.strip()
        |> Map.fetch(:result)

      {:error, response} ->
        {:error, response.reason}
    end
  end

  # personal message
  def pm(id, text) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendMessage"
    IO.puts(url)
    options = []

    {:ok, body} =
      Jason.encode(%{
        chat_id: id,
        text: text,
        parse_mode: "HTML"
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # personal message body
  def pm(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendMessage"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # current user photo
  # TODO: TEST ON USER WITHOUT PHOTO
  def uph(id) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/getUserProfilePhotos"
    IO.puts(url)
    options = []

    {:ok, body} =
      Jason.encode(%{
        user_id: id,
        limit: "1"
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, %{"result" => %{"photos" => photo}}} = Jason.decode(response.body)

    case photo do
      [] ->
        "AgACAgIAAxkBAAIigmQVmbx7m-HI4Run-98wS9Si1Ul8AAJMxTEbUcywSDKEM2a7rqTUAQADAgADeAADLwQ"

      _ ->
        [[_, _, %{"file_id" => pic}]] = photo
        pic
    end
  end

  # chat info with bio
  def getu(id) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/getChat"
    options = []

    {:ok, body} = Jason.encode(%{chat_id: id})

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  def get_chat_member(chat, member_id) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/getChatMember"
    options = []

    {:ok, body} = Jason.encode(%{chat_id: chat, user_id: member_id})

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  def getme() do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/getMe"
    options = []

    {:ok, response} = HTTPoison.get(url, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # update text message
  def um(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/editMessageText"

    options = []

    {:ok, response} = HTTPoison.post(url, Jason.encode!(body), headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # update keyboard
  def ui(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/editMessageReplyMarkup"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # delete message (rename to away)
  def dm(id, mid) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/deleteMessage"

    options = []

    body =
      Jason.encode!(%{
        chat_id: id,
        message_id: mid
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # update media message
  def umm(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/editMessageMedia"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    Logger.info(rbody)
    rbody
  end

  # send video
  def v(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendVideo"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # send photo
  def p(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendPhoto"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # send gif/animation
  def a(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendAnimation"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # send dice
  def dice(id, type) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendDice"
    IO.puts(url)
    options = []

    em =
      case type do
        "dice" ->
          "🎲"

        "bowl" ->
          "🎳"

        "foot" ->
          "⚽"

        "bask" ->
          "🏀"

        "dart" ->
          "🎯"

        "777" ->
          "🎰"
      end

    {:ok, body} =
      Jason.encode(%{
        chat_id: id,
        parse_mode: "markdown",
        emoji: em
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # send bot animated status
  def act(id, type) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendChatAction"
    IO.puts(url)
    options = []

    act =
      case type do
        "txt" ->
          "typing"

        "pic" ->
          "upload_photo"

        "vid" ->
          "upload_video"
      end

    {:ok, body} =
      Jason.encode(%{
        chat_id: id,
        action: act
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # set bot menu "command - Description, command2 - Description"
  def setmenu(string) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/setMyCommands"
    IO.puts(url)
    options = []

    bu =
      for el <- String.split(string, ","),
          do: el |> String.trim_leading(" ") |> String.trim_trailing(" ")

    cmd =
      for el <- bu do
        [cmnd, desc] = String.split(el, "-")

        %{
          command: cmnd |> String.trim_leading(" ") |> String.trim_trailing(" "),
          description: desc |> String.trim_leading(" ") |> String.trim_trailing(" ")
        }
      end

    {:ok, response} = HTTPoison.post(url, Jason.encode!(%{commands: cmd}), headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # delete bot menu
  def delmenu() do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/deleteMyCommands"
    IO.puts(url)
    options = []

    body =
      Jason.encode!(%{
        scope: %{type: "default"}
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # Pop-up answer to callback_query alert=true for user confirmation button
  def shout(id, text, alert) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/answerCallbackQuery"
    options = []

    {:ok, body} =
      Jason.encode(%{
        callback_query_id: id,
        text: text,
        show_alert: alert
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  def shout(obj) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/answerCallbackQuery"
    options = []

    {:ok, body} = Jason.encode(obj)

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end


  # TEST for built in telegram payments
  def money(id \\ 355_117) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendInvoice"
    IO.puts(url)
    options = []

    {:ok, body} =
      Jason.encode(%{
        chat_id: id,
        title: "ПРОДЛЕНИЕ GRAVITY VPN",
        description: "НА ЦЕЛЫЙ ГОД!",
        payload: "What",
        provider_token: "5334985814:TEST:543267",
        currency: "RUB",
        prices: [
          %{
            label: "год",
            amount: 10000
          }
        ]
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # fucking quiz
  def quiz(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/sendPoll"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # forward message
  def share(body) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/forwardMessage"

    options = []

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # copy message
  def copy(where, from, msg) do
    headers = [{"Content-Type", "application/json"}]
    url = gen_link() <> "/copyMessage"

    options = []

    body = Jason.encode!(%{chat_id: where, from_chat_id: from, message_id: msg})

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # upload and send file / multipart
  def uf(id, file, name, text, kb) do
    headers = [{"Content-Type", "multipart/form-data"}]
    url = gen_link() <> "/sendDocument"

    body = [
      {:file, file, {"form-data", [{"name", "document"}, {"filename", name}]}, []},
      {"chat_id", to_string(id)},
      {"caption", text},
      {"reply_markup", kb},
      {"parse_mode", "HTML"}
    ]

    options = [recv_timeout: 20_000]

    {:ok, response} = HTTPoison.post(url, {:multipart, body}, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end

  # telegram wallet pay initial funtcion
  def walletInit(cur, sum, id, info, user) do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Wpay-Store-Api-Key", @wallet}
    ]

    url = "https://pay.wallet.tg/wpay/store-api/v1/order"

    options = []

    body =
      Jason.encode!(%{
        amount: %{currencyCode: cur, amount: sum},
        description: info,
        externalId: id,
        timeoutSeconds: 2400,
        customerTelegramUserId: user
      })

    {:ok, response} = HTTPoison.post(url, body, headers, options)
    {:ok, rbody} = Jason.decode(response.body)
    rbody
  end



end
