defmodule Sexy.Utils.Object do
  @moduledoc """
  The universal message container for `Sexy.Bot`.

  Every message sent through `Sexy.Bot.send/1` is represented as an Object struct.
  Build one from a plain map via `Sexy.Bot.build/1`:

      Sexy.Bot.build(%{
        chat_id: 123,
        text: "Hello!",
        kb: %{inline_keyboard: [[%{text: "Go", callback_data: "/go"}]]}
      })

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `chat_id` | integer | Telegram chat id (required) |
  | `text` | string | Message text or caption (HTML supported) |
  | `media` | string/nil | Media file_id or `"file"` for documents. `nil` = text-only |
  | `kb` | map | Reply markup (`%{inline_keyboard: [[...]]}`) |
  | `entity` | list | Telegram message entities (bold, links, etc.) |
  | `update_data` | map | App-specific data passed to `Session.on_message_sent/4` |
  | `file` | binary/nil | File content for document uploads |
  | `filename` | string/nil | Filename for document uploads |

  ## Media type detection

  The `media` field determines how the message is sent:

  | `media` value | Detected type | API method |
  |---|---|---|
  | `nil` | text | `sendMessage` |
  | `"file"` | document | `sendDocument` (multipart upload) |
  | starts with `"A"` | photo | `sendPhoto` |
  | starts with `"B"` | video | `sendVideo` |
  | starts with `"C"` | animation | `sendAnimation` |

  Telegram file_ids have a predictable prefix based on file type, which Sexy uses
  for automatic detection.
  """

  @type t :: %__MODULE__{
          chat_id: integer() | nil,
          text: String.t(),
          media: String.t() | nil,
          kb: map(),
          entity: list(),
          update_data: map(),
          file: binary() | nil,
          filename: String.t() | nil
        }

  defstruct chat_id: nil,
            text: "",
            media: nil,
            kb: %{inline_keyboard: []},
            entity: [],
            update_data: %{},
            file: nil,
            filename: nil

  @type object_type :: String.t()

  @doc """
  Detect the content type of an Object based on its `media` field.

  Returns one of: `"txt"`, `"file"`, `"photo"`, `"video"`, `"animation"`, `"unknown"`.
  """
  @spec detect_object_type(t()) :: object_type()
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
