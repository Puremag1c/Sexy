defmodule Sexy.Utils.Bot do
  @moduledoc """
  Helpers for working with Telegram bot updates: command parsing, user/message
  extraction, media handling, text formatting, and pagination.

  ## Command parsing

      iex> Sexy.Utils.Bot.parse_comand_and_query("/buy id=42-page=1")
      {"buy", %{id: 42, page: 1}}

      iex> Sexy.Utils.Bot.get_command_name("/start deep_link")
      "start"

  ## Update extraction

      # Works with both message and callback_query updates
      msg = Sexy.Utils.Bot.extract_msg(update)
      user = Sexy.Utils.Bot.extract_user_obj(update)

  ## Media detection

      type = Sexy.Utils.Bot.get_message_type(update)
      # => "text", "photo", "video", "animation", "document", etc.

  ## Pagination

      page_items = Sexy.Utils.Bot.paginate(all_items, 2, 10)
      # => items 11-20
  """

  alias Sexy.Utils

  require Logger

  @doc """
  Parse a command string into `{command_name, query_map}`.

  ## Example

      iex> Sexy.Utils.Bot.parse_comand_and_query("/buy id=42-amount=100")
      {"buy", %{id: 42, amount: 100}}
  """
  def parse_comand_and_query(string) do
    {get_command_name(string), Utils.get_query(string)}
  end

  @doc """
  Extract just the command name from a string (without `/` prefix and query).

  ## Example

      iex> Sexy.Utils.Bot.get_command_name("/start some_param")
      "start"
  """
  def get_command_name(string) do
    string
    |> String.trim("/")
    |> String.split(" ", parts: 2)
    |> List.first()
  end

  @doc """
  Extract the message map from a Telegram update.

  Works with both direct messages and callback queries:

    * `%{message: msg}` → returns `msg`
    * `%{callback_query: %{message: msg}}` → returns `msg`
    * anything else → returns the input as-is
  """
  def extract_msg(obj) do
    cond do
      Map.has_key?(obj, :message) -> obj.message
      Map.has_key?(obj, :callback_query) -> obj.callback_query.message
      true -> obj
    end
  end

  @doc """
  Extract the user (`from`) map from a Telegram update.

  Checks `callback_query.from`, then `message.from`, then `obj.from`.
  """
  def extract_user_obj(obj) do
    cond do
      Map.has_key?(obj, :callback_query) -> obj.callback_query.from
      Map.has_key?(obj, :message) -> obj.message.from
      true -> obj.from
    end
  end

  @doc """
  Detect the content type of a message.

  Returns one of: `"video_note"`, `"animation"`, `"document"`, `"sticker"`,
  `"contact"`, `"photo"`, `"audio"`, `"video"`, `"voice"`, `"text"`, `"unknown"`.
  """
  def get_message_type(u) do
    msg = extract_msg(u)

    cond do
      Map.has_key?(msg, :video_note) -> "video_note"
      Map.has_key?(msg, :animation) -> "animation"
      Map.has_key?(msg, :document) -> "document"
      Map.has_key?(msg, :sticker) -> "sticker"
      Map.has_key?(msg, :contact) -> "contact"
      Map.has_key?(msg, :photo) -> "photo"
      Map.has_key?(msg, :audio) -> "audio"
      Map.has_key?(msg, :video) -> "video"
      Map.has_key?(msg, :voice) -> "voice"
      Map.has_key?(msg, :text) -> "text"
      true -> "unknown"
    end
  end

  @doc """
  Wrap text in decorative `<code>` borders for Telegram HTML messages.

  With one argument, wraps in lines. With a tag, wraps in the specified HTML tag.
  """
  def wrap_text(text),
  do: "#{line()}\n\n#{text}\n\n#{line()}"

  def wrap_text(text, tag, lines \\ false) do
    if lines,
      do: "#{line()}\n\n<#{tag}>#{text}</#{tag}>\n\n#{line()}",
      else: "<#{tag}>#{text}</#{tag}>"
  end

  defp line, do: "<code>⚙ ━━━━━━━ ⚙ ━━━━━━━━ ⚙</code>"

  @doc """
  Extract the `file_id` from a message by media type.

  Supports `"video"` and `"photo"`. For photos, returns the highest-resolution version.
  """
  def get_message_media(msg, type) do
    case type do
      "video" -> msg.video.file_id
      "photo" -> get_photo_id(msg.photo)
      any -> Logger.debug("get_message_media: Неизвестный тип media #{any}")
    end

  end

  @doc "Get the `file_id` of the highest-resolution photo from a Telegram photo array."
  def get_photo_id(photo) do
    case length(photo) do
      1 ->
        [%{file_id: photo}] = photo
        photo
      2 ->
        [_,%{file_id: photo}] = photo
        photo
      3 ->
        [_,_,%{file_id: photo}] = photo
        photo
      4 ->
        [_,_,_,%{file_id: photo}] = photo
        photo
    end
  end

  @doc """
  Paginate a list by page index (1-based) and page size.

  ## Example

      iex> Sexy.Utils.Bot.paginate(Enum.to_list(1..50), 2, 10)
      [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  """
  def paginate(list, page_index, size) when page_index >= 1 do
    offset = (page_index - 1) * size
    Enum.slice(list, offset, size)
  end

  def paginate(list, _page_index, size) do
    offset = 0 * size
    Enum.slice(list, offset, size)
  end
end
