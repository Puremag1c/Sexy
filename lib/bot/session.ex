defmodule Sexy.Bot.Session do
  @moduledoc """
  Behaviour that bridges Sexy with your application.

  Implement this module to provide two things:

  1. **Persistence** — tell Sexy which message is currently active and save new ones
  2. **Dispatch** — handle incoming Telegram updates (commands, queries, messages)

  ## Example implementation

      defmodule MyApp.Session do
        @behaviour Sexy.Bot.Session

        # ── Persistence ──
        @impl true
        def get_message_id(chat_id) do
          case MyApp.Repo.get_by(MyApp.User, chat_id: chat_id) do
            nil -> nil
            user -> user.message_id
          end
        end

        @impl true
        def on_message_sent(chat_id, message_id, _type, update_data) do
          user = MyApp.Repo.get_by!(MyApp.User, chat_id: chat_id)
          MyApp.Repo.update!(Ecto.Changeset.change(user, %{
            message_id: message_id,
            screen: Map.get(update_data, :screen)
          }))
        end

        # ── Dispatch ──
        @impl true
        def handle_command(update) do
          {cmd, query} = Sexy.Utils.Bot.parse_comand_and_query(update.message.text)
          case cmd do
            "start" -> MyApp.Screens.home(update)
            "help"  -> MyApp.Screens.help(update)
            _       -> :ok
          end
        end

        @impl true
        def handle_query(update) do
          {cmd, query} = Sexy.Utils.Bot.parse_comand_and_query(update.callback_query.data)
          case cmd do
            "buy"  -> MyApp.Screens.buy(update, query)
            "back" -> MyApp.Screens.home(update)
            _      -> :ok
          end
        end

        @impl true
        def handle_message(update), do: :ok

        @impl true
        def handle_chat_member(update), do: :ok
      end

  ## Persistence callbacks

  Sexy calls `get_message_id/1` before sending to find the old message to delete,
  and `on_message_sent/4` after sending to save the new one. Your implementation
  decides **where** state lives (database, ETS, Agent, etc.).

  ## Dispatch callbacks

  The `Sexy.Bot.Poller` routes every Telegram update to one of these callbacks.
  Each callback receives the full Telegram update map with atom keys.

  ## Optional callbacks

    * `handle_poll/1` — for poll answer updates
    * `handle_transit/3` — for built-in `/_transit` navigation buttons
      (see `Sexy.Bot.Notification`)
  """

  # ── Persistence ──────────────────────────────────────────────

  @doc """
  Return the current active `message_id` for this chat, or `nil` if none.

  Called by `Sexy.Bot.Sender` before sending a new message. If a message id
  is returned, the old message will be deleted before the new one is sent.
  """
  @callback get_message_id(chat_id :: integer()) :: integer() | nil

  @doc """
  Called after a message is successfully sent and becomes the active screen.

  ## Parameters

    * `chat_id` — Telegram chat id
    * `message_id` — new message id from the Telegram response
    * `type` — `"txt"` for text messages, `"media"` for everything else
    * `update_data` — the `update_data` map from the Object (app-specific data like
      screen name, selected city, current page, etc.)
  """
  @callback on_message_sent(
              chat_id :: integer(),
              message_id :: integer(),
              type :: String.t(),
              update_data :: map()
            ) :: any()

  # ── Dispatch ─────────────────────────────────────────────────

  @doc "Handle messages starting with `/` (bot commands)."
  @callback handle_command(update :: map()) :: any()

  @doc "Handle inline keyboard button presses (callback queries)."
  @callback handle_query(update :: map()) :: any()

  @doc "Handle regular text messages (not starting with `/`)."
  @callback handle_message(update :: map()) :: any()

  @doc "Handle chat member status changes (user joined/left, bot added/removed)."
  @callback handle_chat_member(update :: map()) :: any()

  @doc "Handle poll answer updates. Optional."
  @callback handle_poll(update :: map()) :: any()

  @doc """
  Handle transit button clicks (built-in `/_transit` route).

  Called when a user clicks a navigation button created by `Sexy.Bot.Notification`.
  Sexy automatically deletes the notification message and answers the callback —
  your implementation only needs to render the target screen.

  ## Parameters

    * `chat_id` — Telegram chat id
    * `command` — target command name (e.g. `"order"`, `"wallet"`)
    * `query` — parsed query params as an atom-keyed map

  Optional — only implement if you use `Sexy.Bot.notify/3` with the `:navigate` option.
  """
  @callback handle_transit(chat_id :: integer(), command :: String.t(), query :: map()) :: any()

  @optional_callbacks [handle_poll: 1, handle_transit: 3]
end
