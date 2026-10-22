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
  | `file` | binary/`{:path, path}`/nil | File content, or `{:path, path}` to upload a file from disk |
  | `filename` | string/nil | Filename for multipart uploads |
  | `upload_type` | atom/nil | `:photo`, `:video`, `:animation`, `:document` — forces multipart upload |
  | `params` | map | Extra Bot API parameters merged into the request (see below) |

  `build/1` raises `KeyError` on a key that is not a field — a misspelled or
  unsupported key fails loudly instead of being dropped.

  ## Extra Bot API parameters

  `params` is passed through to the `send*` request as-is, for every content
  type including multipart uploads — any Bot API parameter works without a
  Sexy release:

      Sexy.Bot.build(%{
        chat_id: 123,
        text: "https://example.com",
        params: %{link_preview_options: %{is_disabled: true}, disable_notification: true}
      })

  Keys may be atoms or strings; `nil` values are not sent. Parameters Sexy
  sets itself (`chat_id`, `text`/`caption`, `entities`/`caption_entities`,
  `parse_mode`, `reply_markup`, the media field) cannot be overridden —
  use the Object fields; a clash raises `ArgumentError`.

  ## Media type detection

  Detection looks at `upload_type` first, then falls back to `media`:

  | Condition | Detected type | API method |
  |---|---|---|
  | `upload_type: :photo` | photo_upload | `sendPhoto` (multipart) |
  | `upload_type: :video` | video_upload | `sendVideo` (multipart) |
  | `upload_type: :animation` | animation_upload | `sendAnimation` (multipart) |
  | `upload_type: :document` | file | `sendDocument` (multipart) |
  | `media: nil` | txt | `sendMessage` |
  | `media: "file"` (legacy) | file | `sendDocument` (multipart) |
  | `media` starts with `"A"` | photo | `sendPhoto` (by file_id) |
  | `media` starts with `"B"` | video | `sendVideo` (by file_id) |
  | `media` starts with `"C"` | animation | `sendAnimation` (by file_id) |

  Telegram file_ids have a predictable prefix based on file type, which Sexy uses
  for automatic detection. For uploading a local file or binary, set `upload_type`.
  """

  @type upload_type :: :photo | :video | :animation | :document | nil

  @type t :: %__MODULE__{
          chat_id: integer() | nil,
          text: String.t(),
          media: String.t() | nil,
          kb: map(),
          entity: list(),
          update_data: map(),
          file: binary() | {:path, String.t()} | nil,
          filename: String.t() | nil,
          upload_type: upload_type(),
          params: map()
        }

  defstruct chat_id: nil,
            text: "",
            media: nil,
            kb: %{inline_keyboard: []},
            entity: [],
            update_data: %{},
            file: nil,
            filename: nil,
            upload_type: nil,
            params: %{}

  @type object_type :: String.t()

  @doc """
  Build an Object struct from a map, or a list of Objects from a list of maps.

  Raises `KeyError` if the map has a key that is not an Object field.

  ## Examples

      iex> Sexy.Utils.Object.build(%{chat_id: 123, text: "Hi"})
      %Sexy.Utils.Object{chat_id: 123, text: "Hi"}
  """
  @spec build(map()) :: t()
  @spec build([map()]) :: [t()]
  def build(items) when is_list(items), do: Enum.map(items, &build/1)
  # idempotent: an already-built Object passes through unchanged
  def build(%__MODULE__{} = object), do: object
  def build(map) when is_map(map) and not is_struct(map), do: struct!(__MODULE__, map)

  @doc """
  Detect the content type of an Object.

  `upload_type` (if set) wins over `media`. Returns one of:
  `"txt"`, `"file"`, `"photo"`, `"video"`, `"animation"`,
  `"photo_upload"`, `"video_upload"`, `"animation_upload"`, `"unknown"`.
  """
  @spec detect_object_type(t()) :: object_type()
  def detect_object_type(obj) do
    detect_upload(obj.upload_type) || detect_media(obj.media)
  end

  defp detect_upload(:photo), do: "photo_upload"
  defp detect_upload(:video), do: "video_upload"
  defp detect_upload(:animation), do: "animation_upload"
  defp detect_upload(:document), do: "file"
  defp detect_upload(nil), do: nil

  defp detect_media(nil), do: "txt"
  defp detect_media("file"), do: "file"

  defp detect_media(media) when is_binary(media) do
    case String.first(media) do
      "A" -> "photo"
      "B" -> "video"
      "C" -> "animation"
      _ -> "unknown"
    end
  end

  defp detect_media(_), do: "unknown"
end
