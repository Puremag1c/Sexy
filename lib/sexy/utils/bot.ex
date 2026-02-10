defmodule Sexy.Utils.Bot do

  alias Sexy.Utils

  require Logger

  def parse_comand_and_query(string) do
    {get_command_name(string), Utils.get_query(string)}
  end

  def get_command_name(string) do
    string
    |> String.trim("/")
    |> String.split(" ", parts: 2)
    |> List.first()
  end

  def extract_msg(obj) do
    cond do
      Map.has_key?(obj, :message) -> obj.message
      Map.has_key?(obj, :callback_query) -> obj.callback_query.message
      true -> obj
    end
  end

  def extract_user_obj(obj) do
    cond do
      Map.has_key?(obj, :callback_query) -> obj.callback_query.from
      Map.has_key?(obj, :message) -> obj.message.from
      true -> obj.from
    end
  end

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

  def wrap_text(text),
  do: "#{line()}\n\n#{text}\n\n#{line()}"

  def wrap_text(text, tag, lines \\ false) do
    if lines,
      do: "#{line()}\n\n<#{tag}>#{text}</#{tag}>\n\n#{line()}",
      else: "<#{tag}>#{text}</#{tag}>"
  end

  defp line, do: "<code>⚙ ━━━━━━━ ⚙ ━━━━━━━━ ⚙</code>"

  def get_message_media(msg, type) do
    case type do
      "video" -> msg.video.file_id
      "photo" -> get_photo_id(msg.photo)
      any -> Logger.debug("get_message_media: Неизвестный тип media #{any}")
    end

  end

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

  def paginate(list, page_index, size) when page_index >= 1 do
    offset = (page_index - 1) * size
    Enum.slice(list, offset, size)
  end

  def paginate(list, _page_index, size) do
    offset = 0 * size
    Enum.slice(list, offset, size)
  end
end
