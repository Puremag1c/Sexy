# Bot Quick Start

Build a Telegram bot with `Sexy.Bot` in 5 minutes.

## What is Sexy?

Sexy is a **single-message UI** framework for Telegram bots. Instead of flooding
the chat with messages, your bot keeps **one active message per chat**. Every
action deletes the old message and sends a new one — the result looks and feels
like an interactive app inside Telegram.

The `Session` behaviour is the bridge between the framework and your code.
It has two responsibilities:

- **Persistence** — remember which message is currently on screen
- **Dispatch** — route incoming Telegram updates to your handlers

## 1. Get a bot token

Open [@BotFather](https://t.me/BotFather) in Telegram, send `/newbot`,
follow the prompts, and copy the token (looks like `123456:ABC-DEF...`).

## 2. Create a new project

```bash
mix new my_bot --sup
cd my_bot
```

`--sup` generates a supervision tree so the bot starts automatically with your app.

## 3. Add Sexy to dependencies

```elixir
# mix.exs
defp deps do
  [
    {:sexy, "~> 0.9"}
  ]
end
```

```bash
mix deps.get
```

## 4. Implement the Session

Create `lib/my_bot/session.ex`. We'll build it in three blocks: storage,
dispatch, and screens.

### Block A — Storage (persistence)

The framework calls two callbacks to manage the active message:

- `get_message_id/1` — before sending, to find and delete the old message
- `on_message_sent/4` — after sending, to save the new message id

For this quickstart we use an `Agent` (a simple key-value process). In a real
project you would use a database (Ecto).

```elixir
# lib/my_bot/session.ex
defmodule MyBot.Session do
  @behaviour Sexy.Bot.Session

  use Agent

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  # ── Persistence ──

  @impl true
  def get_message_id(chat_id) do
    Agent.get(__MODULE__, &Map.get(&1, chat_id))
  end

  @impl true
  def on_message_sent(chat_id, message_id, _type, _update_data) do
    Agent.update(__MODULE__, &Map.put(&1, chat_id, message_id))
  end
```

The two unused parameters:

- `type` — `"txt"` for text messages, `"media"` for photos/videos/documents
- `update_data` — a map you attach to the Object (e.g. `%{screen: "products",
  page: 2}`). Useful for saving app state alongside the message id.

### Block B — Dispatch (routing updates)

Telegram sends your bot **updates**. Each update is a map with one key that
tells you what happened:

| Update key | Meaning | Session callback |
|---|---|---|
| `message` (text starts with `/`) | User sent a command | `handle_command/1` |
| `message` (otherwise) | User sent a regular message | `handle_message/1` |
| `callback_query` | User pressed an inline button | `handle_query/1` |
| `my_chat_member` | User blocked/unblocked the bot | `handle_chat_member/1` |

Here is what a command update looks like (simplified):

```elixir
%{
  message: %{
    chat: %{id: 123456},
    text: "/start"
  }
}
```

And a callback query update (when a user presses an inline button):

```elixir
%{
  callback_query: %{
    id: "abc123",                   # you must answer this (see below)
    message: %{chat: %{id: 123456}},
    data: "/about"                  # the callback_data string you set on the button
  }
}
```

Add the dispatch callbacks to the same module:

```elixir
  # ── Dispatch ──

  @impl true
  def handle_command(update) do
    chat_id = update.message.chat.id
    {cmd, _query} = Sexy.Utils.Bot.parse_comand_and_query(update.message.text)

    case cmd do
      "start" -> show_home(chat_id)
      "help"  -> show_help(chat_id)
      _       -> :ok
    end
  end

  @impl true
  def handle_query(update) do
    chat_id = update.callback_query.message.chat.id
    {cmd, _query} = Sexy.Utils.Bot.parse_comand_and_query(update.callback_query.data)

    case cmd do
      "home"  -> show_home(chat_id)
      "about" -> show_about(chat_id)
      "help"  -> show_help(chat_id)
      _       -> :ok
    end

    # Telegram waits for a response to every button press.
    # answer_callback removes the "loading" spinner on the button.
    # Arguments: callback_id, tooltip text (empty = none), show_alert flag.
    Sexy.Bot.answer_callback(update.callback_query.id, "", false)
  end

  # Required callbacks — return :ok if you don't need them yet.
  @impl true
  def handle_message(_update), do: :ok

  @impl true
  def handle_chat_member(_update), do: :ok
```

### Block C — Screens

Each screen follows the same pattern: **build a map → convert to Object → send**.

```elixir
  # ── Screens ──

  defp show_home(chat_id) do
    %{
      chat_id: chat_id,
      text: "<b>Welcome to MyBot!</b>\n\nPick an option below:",
      kb: %{inline_keyboard: [
        [%{text: "About", callback_data: "/about"}],
        [%{text: "Help", callback_data: "/help"}]
      ]}
    }
    |> Sexy.Bot.build()
    |> Sexy.Bot.send()
  end

  defp show_about(chat_id) do
    %{
      chat_id: chat_id,
      text: "This bot was built with <b>Sexy</b> framework.",
      kb: %{inline_keyboard: [
        [%{text: "Back", callback_data: "/home"}]
      ]}
    }
    |> Sexy.Bot.build()
    |> Sexy.Bot.send()
  end

  defp show_help(chat_id) do
    %{
      chat_id: chat_id,
      text: "Available commands:\n/start — Home screen\n/help — This message",
      kb: %{inline_keyboard: [
        [%{text: "Back", callback_data: "/home"}]
      ]}
    }
    |> Sexy.Bot.build()
    |> Sexy.Bot.send()
  end
end
```

**Inline keyboard layout:** `kb` expects a `%{inline_keyboard: rows}` map where
`rows` is a list of lists. Each inner list is one row of buttons. For example,
two buttons on the same row:

```elixir
kb: %{inline_keyboard: [
  [%{text: "Yes", callback_data: "/yes"}, %{text: "No", callback_data: "/no"}],
  [%{text: "Cancel", callback_data: "/home"}]
]}
# Row 1: [Yes] [No]
# Row 2: [Cancel]
```

**`callback_data`** is the string that arrives in `update.callback_query.data`
when the user presses that button. Convention: start with `/` and a command
name so you can route it in `handle_query/1`.

## 5. Start the bot in your supervision tree

```elixir
# lib/my_bot/application.ex
defmodule MyBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyBot.Session,                  # start the Agent first
      {Sexy.Bot, token: System.get_env("BOT_TOKEN"), session: MyBot.Session}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyBot.Supervisor)
  end
end
```

Order matters: `MyBot.Session` must start before `Sexy.Bot` because the bot
will call session callbacks as soon as updates arrive.

## 6. Run

```bash
BOT_TOKEN="123456:ABC-DEF..." mix run --no-halt
```

Open your bot in Telegram and send `/start`.

## How it works

```
User sends /start
  → Poller receives update
    → handle_command/1
      → show_home/1: build map → build() → send()
        → Sexy calls Telegram API (sendMessage)
        → Sexy saves message_id via on_message_sent/4
          → User sees "Welcome to MyBot!"

User presses [About]
  → Poller receives callback_query (data: "/about")
    → handle_query/1
      → show_about/1: build map → build() → send()
        → Sexy calls get_message_id/1 → deletes old message
        → Sexy sends new message, saves new message_id
        → answer_callback removes button spinner
          → User sees "This bot was built with Sexy"
```

---

## Reference

### Object fields

Every message sent through `Sexy.Bot.send/1` is a `Sexy.Utils.Object` struct.
You build one from a plain map via `Sexy.Bot.build/1`:

```elixir
Sexy.Bot.build(%{chat_id: 123, text: "Hello!"})
```

| Field | Type | Default | Description |
|---|---|---|---|
| `chat_id` | integer | `nil` | Telegram chat id (required) |
| `text` | string | `""` | Message text or caption. HTML is supported by default |
| `media` | string \| nil | `nil` | Media file_id or `"file"` for uploads. `nil` = text only |
| `kb` | map | `%{inline_keyboard: []}` | Reply markup (inline keyboard) |
| `update_data` | map | `%{}` | App data passed to `Session.on_message_sent/4` |
| `file` | binary \| nil | `nil` | File content for document uploads |
| `filename` | string \| nil | `nil` | Filename for document uploads |

### Sending different content types

The `media` field controls which Telegram API method is called:

```elixir
# Text message (media: nil — default)
%{chat_id: id, text: "<b>Bold</b> text with HTML"}

# Photo by file_id (starts with "A")
%{chat_id: id, text: "Caption", media: "AgACAgIAAxk..."}

# Video by file_id (starts with "B")
%{chat_id: id, text: "Watch this", media: "BAACAgIAAxk..."}

# Animation / GIF (starts with "C")
%{chat_id: id, media: "CgACAgIAAxk..."}

# Document — upload binary with filename
%{chat_id: id, text: "Your export", media: "file", file: File.read!("data.csv"), filename: "data.csv"}
```

### Inline keyboard

```elixir
%{
  chat_id: id,
  text: "Choose:",
  kb: %{inline_keyboard: [
    [%{text: "Option A", callback_data: "/pick val=a"}],
    [%{text: "Option B", callback_data: "/pick val=b"}],
    [%{text: "Cancel", callback_data: "/home"}]
  ]}
}
```

Each inner list is a row. Buttons in the same list appear side by side.
Buttons in separate lists stack vertically.

### Passing state between screens

Use `update_data` to save app-specific context. It is passed as the fourth
argument to `Session.on_message_sent/4`:

```elixir
%{
  chat_id: id,
  text: "Page 2 of products",
  update_data: %{screen: "products", page: 2, category: "electronics"}
}
|> Sexy.Bot.build()
|> Sexy.Bot.send()
```

Then in your Session:

```elixir
def on_message_sent(chat_id, message_id, type, update_data) do
  # update_data == %{screen: "products", page: 2, category: "electronics"}
  MyApp.Users.update(chat_id, %{mid: message_id, state: update_data})
end
```

### `send/2` options

| Option | Default | Effect |
|--------|---------|--------|
| `update_mid: true` | yes | Deletes old message, saves new mid via Session |
| `update_mid: false` | — | Sends without touching the current screen state |

```elixir
# Normal — replaces current screen
Sexy.Bot.build(map) |> Sexy.Bot.send()

# Fire-and-forget — doesn't replace the screen
Sexy.Bot.build(map) |> Sexy.Bot.send(update_mid: false)
```

### Notifications

`Sexy.Bot.notify/3` sends messages outside the main screen flow.

#### Overlay (default)

Sends a message with a dismiss button. The current screen stays intact:

```elixir
Sexy.Bot.notify(chat_id, %{text: "Action completed!"})
Sexy.Bot.notify(chat_id, %{text: "Saved!"}, dismiss_text: "Got it")
```

#### Replace

Replaces the current screen (mid is updated via Session):

```elixir
Sexy.Bot.notify(chat_id, %{text: "Payment received!"}, replace: true)
```

#### Navigate

Adds a button that deletes the notification and calls `Session.handle_transit/3`:

```elixir
Sexy.Bot.notify(chat_id, %{text: "New order #42!"},
  navigate: {"View Order", "/order id=42"}
)
```

In your Session, implement the optional callback:

```elixir
@impl true
def handle_transit(chat_id, "order", %{id: order_id}) do
  show_order_screen(chat_id, order_id)
end
```

#### Extra buttons

Append additional button rows after navigate/dismiss:

```elixir
Sexy.Bot.notify(chat_id, %{text: "New message from Alice"},
  navigate: {"Open Chat", "/chat user=alice"},
  extra_buttons: [[%{text: "Mute", callback_data: "/mute user=alice"}]]
)
```

## Next steps

- Accept **payments**: `Sexy.Bot.send_invoice/6` for Telegram Stars
- Use `Sexy.Utils.Bot.paginate/3` for paginated lists
- Use `Sexy.Utils.Bot.get_message_type/1` to detect incoming media type
