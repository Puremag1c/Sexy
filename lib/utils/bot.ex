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

  @message_types ~w(video_note animation document sticker contact photo audio video voice text)a

  @doc """
  Parse a command string into `{command_name, query_map}`.

  ## Example

      iex> Sexy.Utils.Bot.parse_comand_and_query("/buy id=42-amount=100")
      {"buy", %{id: 42, amount: 100}}
  """
  @spec parse_comand_and_query(String.t()) :: {String.t(), map()}
  def parse_comand_and_query(string) do
    {get_command_name(string), Utils.get_query(string)}
  end

  @doc """
  Extract just the command name from a string (without `/` prefix and query).

  ## Example

      iex> Sexy.Utils.Bot.get_command_name("/start some_param")
      "start"
  """
  @spec get_command_name(String.t()) :: String.t()
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
  @spec extract_msg(map()) :: map()
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
  @spec extract_user_obj(map()) :: map()
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
  @spec get_message_type(map()) :: String.t()
  def get_message_type(u) do
    msg = extract_msg(u)

    Enum.find_value(@message_types, "unknown", fn type ->
      if Map.has_key?(msg, type), do: Atom.to_string(type)
    end)
  end

  @doc """
  Wrap text in decorative `<code>` borders for Telegram HTML messages.

  With one argument, wraps in lines. With a tag, wraps in the specified HTML tag.
  """
  @spec wrap_text(String.t()) :: String.t()
  def wrap_text(text),
    do: "#{line()}\n\n#{text}\n\n#{line()}"

  @spec wrap_text(String.t(), String.t(), boolean()) :: String.t()
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
  @spec get_message_media(map(), String.t()) :: String.t() | nil
  def get_message_media(msg, type) do
    case type do
      "video" -> msg.video.file_id
      "photo" -> get_photo_id(msg.photo)
      any -> Logger.debug("get_message_media: Неизвестный тип media #{any}")
    end
  end

  @doc "Get the `file_id` of the highest-resolution photo from a Telegram photo array."
  @spec get_photo_id([map()]) :: String.t()
  def get_photo_id(photo) do
    case length(photo) do
      1 ->
        [%{file_id: photo}] = photo
        photo

      2 ->
        [_, %{file_id: photo}] = photo
        photo

      3 ->
        [_, _, %{file_id: photo}] = photo
        photo

      4 ->
        [_, _, _, %{file_id: photo}] = photo
        photo
    end
  end

  @doc """
  Paginate a list by page index (1-based) and page size.

  ## Example

      iex> Sexy.Utils.Bot.paginate(Enum.to_list(1..50), 2, 10)
      [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  """
  @spec paginate(list(), pos_integer(), pos_integer()) :: list()
  def paginate(list, page_index, size) when page_index >= 1 do
    offset = (page_index - 1) * size
    Enum.slice(list, offset, size)
  end

  def paginate(list, _page_index, size) do
    offset = 0 * size
    Enum.slice(list, offset, size)
  end
end
