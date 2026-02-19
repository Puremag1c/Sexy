# Bot Quick Start

Build a Telegram bot with `Sexy.Bot` in 5 minutes.

## 1. Create a new project

```bash
mix new my_bot --sup
cd my_bot
```

## 2. Add Sexy to dependencies

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

## 3. Implement the Session behaviour

The Session is the bridge between Sexy and your app. It handles two things:

- **Persistence** — which message is currently active in each chat
- **Dispatch** — what to do with incoming updates

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
  def on_message_sent(chat_id, message_id, _type, _extra) do
    Agent.update(__MODULE__, &Map.put(&1, chat_id, message_id))
  end

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
    {cmd, query} = Sexy.Utils.Bot.parse_comand_and_query(update.callback_query.data)

    case cmd do
      "home"  -> show_home(chat_id)
      "about" -> show_about(chat_id)
      _       -> :ok
    end

    Sexy.Bot.answer_callback(update.callback_query.id, "", false)
  end

  @impl true
  def handle_message(_update), do: :ok

  @impl true
  def handle_chat_member(_update), do: :ok

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

## 4. Start the bot in your supervision tree

```elixir
# lib/my_bot/application.ex
defmodule MyBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyBot.Session,
      {Sexy.Bot, token: System.get_env("BOT_TOKEN"), session: MyBot.Session}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyBot.Supervisor)
  end
end
```

## 5. Run

```bash
BOT_TOKEN="123456:ABC-DEF..." mix run --no-halt
```

Open your bot in Telegram and send `/start`.

## What happens under the hood

1. `Sexy.Bot.Poller` polls Telegram for updates every 100ms
2. Your message text starts with `/` → `handle_command/1` is called
3. You build an Object and call `Sexy.Bot.send/1`
4. Sexy detects the content type, calls the Telegram API, deletes the old message, saves the new one

## Object: the message container

Every message sent through `Sexy.Bot.send/1` is a `Sexy.Utils.Object` struct.
You build one from a plain map:

```elixir
Sexy.Bot.build(%{chat_id: 123, text: "Hello!"})
```

### Sending different content types

The `media` field controls what API method is used:

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

### Passing state between screens

Use `update_data` to save app-specific context in `Session.on_message_sent/4`:

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
def on_message_sent(chat_id, message_id, type, extra) do
  # extra == %{screen: "products", page: 2, category: "electronics"}
  MyApp.Users.update(chat_id, %{mid: message_id, state: extra})
end
```

## `send/2` options

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

## Notifications

`Sexy.Bot.notify/3` sends messages outside the main screen flow.

### Overlay (default)

Sends a message with a dismiss button. The current screen stays intact:

```elixir
Sexy.Bot.notify(chat_id, %{text: "Action completed!"})
Sexy.Bot.notify(chat_id, %{text: "Saved!"}, dismiss_text: "Got it")
```

### Replace

Replaces the current screen (mid is updated via Session):

```elixir
Sexy.Bot.notify(chat_id, %{text: "Payment received!"}, replace: true)
```

### Navigate

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

### Extra buttons

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
