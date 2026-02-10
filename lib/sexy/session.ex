defmodule Sexy.Session do
  @moduledoc """
  Behaviour for bridging Sexy library with the consuming app.

  Implements persistence (message state) and dispatch (update handlers).
  """

  # ── Persistence ──────────────────────────────────────────────

  @doc "Return the current active message_id for this chat, or nil."
  @callback get_message_id(chat_id :: integer()) :: integer() | nil

  @doc """
  Called after a message is successfully sent and should become the active screen.

  - `chat_id` — Telegram chat id
  - `message_id` — new message id from Telegram response
  - `type` — "txt" or "media"
  - `extra` — pass-through data from Object.update_data (app-specific: mode, city_id, etc.)
  """
  @callback on_message_sent(
              chat_id :: integer(),
              message_id :: integer(),
              type :: String.t(),
              extra :: map()
            ) :: any()

  # ── Dispatch ─────────────────────────────────────────────────

  @callback handle_command(update :: map()) :: any()
  @callback handle_query(update :: map()) :: any()
  @callback handle_message(update :: map()) :: any()
  @callback handle_chat_member(update :: map()) :: any()
  @callback handle_poll(update :: map()) :: any()

  @optional_callbacks [handle_poll: 1]
end
