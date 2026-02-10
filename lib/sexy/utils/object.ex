defmodule Sexy.Utils.Object do
  defstruct text: "", media: nil, kb: %{inline_keyboard: []}, entity: [], user: nil, update_user: %{}, file: nil, filename: nil

  def detect_object_type(obj) do
    cond do
      obj.media == nil -> "txt"
      obj.media == "file" -> "file"
      String.first(obj.media) == "A" -> "photo"
      String.first(obj.media) == "B" -> "video"
      String.first(obj.media) == "C" -> "animation"
      true -> "unknown"
    end
  end
end
