<p align="center">
  <img src="https://img.shields.io/badge/elixir-%3E%3D%201.14-blueviolet?style=flat-square" />
  <img src="https://img.shields.io/badge/telegram-bot%20api-26A5E4?style=flat-square&logo=telegram&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

<h1 align="center">Sexy</h1>

<p align="center">
  <b>Single-message Telegram Bot framework for Elixir</b><br/>
  <sub>Polling, inline navigation, screen lifecycle, notifications — out of the box.</sub>
</p>

---

## Philosophy

Most Telegram bots flood the chat with messages. Sexy takes a different approach: **one active message per user**. Every new screen replaces the previous one, creating a clean, app-like experience inside Telegram.

```
User clicks button  ->  old message deleted  ->  new message sent  ->  state saved
```

The library handles this lifecycle automatically through the **Session** behaviour.

---

## Architecture

```
                        YOUR APP
            ┌──────────────────────────┐
            │  Menu / Screen modules   │  <- return plain maps
            │  (%{text, kb, user...})  │
            └───────────┬──────────────┘
                        │
                   to_object()           <- app extracts chat_id, renames fields
                        │
            ┌───────────▼──────────────┐
            │      Sexy.Screen         │  <- map -> Object struct
            └───────────┬──────────────┘
                        │
            ┌───────────▼──────────────┐
            │      Sexy.Sender         │  <- detect type, send, manage mid
            │                          │
            │  ┌─────────────────────┐ │
            │  │   Sexy.Session      │ │  <- get_message_id / on_message_sent
            │  │   (your impl)       │ │     (bridges library <-> your DB)
            │  └─────────────────────┘ │
            └───────────┬──────────────┘
                        │
            ┌───────────▼──────────────┐
            │      Sexy.Api            │  <- HTTP to Telegram
            └──────────────────────────┘
```

---

## Quick Start

### 1. Add dependency

```elixir
# mix.exs
defp deps do
  [
    {:sexy, git: "git@github.com:Puremag1c/Sexy.git"}
  ]
end
```

### 2. Configure

```elixir
# config/config.exs
config :sexy,
  link: "https://api.telegram.org/bot",
  session_module: MyApp.TelegramSession,
  handler_module: MyApp.Telegram,
  command_handler: :handle_command,
  query_handler: :handle_query,
  message_handler: :handle_message,
  chat_member_handler: :handle_chat_member

# config/dev.local.exs (not in git!)
config :sexy, token: "123456:ABC-DEF..."
```

### 3. Implement Session

The Session behaviour bridges the library with your database. Sexy never dictates your schema — you decide how to store `message_id`.

```elixir
defmodule MyApp.TelegramSession do
  @behaviour Sexy.Session

  @impl true
  def get_message_id(chat_id) do
    case MyApp.Users.get_by_telegram_id(chat_id) do
      nil -> nil
      user -> user.last_message_id
    end
  end

  @impl true
  def on_message_sent(chat_id, message_id, type, extra) do
    user = MyApp.Users.get_by_telegram_id(chat_id)
    params = Map.merge(extra, %{last_message_id: message_id, message_type: type})
    MyApp.Users.update(user, params)
  end
end
```

### 4. Implement handlers

```elixir
defmodule MyApp.Telegram do
  def handle_command(update) do
    # update.message.text -> "/start", "/help", etc.
  end

  def handle_query(update) do
    # update.callback_query.data -> "/menu action=buy"
  end

  def handle_message(update) do
    # Free text messages
  end

  def handle_chat_member(update) do
    # Bot added/removed from chat
  end
end
```

That's it. The Poller starts automatically via the OTP supervision tree.

---

## Core Concepts

### Object

The universal message struct. Every screen your app builds ultimately becomes an Object before sending.

```elixir
%Sexy.Utils.Object{
  chat_id: 123456789,
  text: "Hello!",
  media: nil,                          # nil = text, "A..." = photo, "B..." = video
  kb: %{inline_keyboard: [[
    %{text: "Click me", callback_data: "/action"}
  ]]},
  entity: [],                          # Telegram entities (bold, links, etc.)
  update_data: %{mode: "main_menu"},   # pass-through to on_message_sent
  file: nil,                           # for document uploads
  filename: nil
}
```

**Type detection** is based on the `media` field:

| `media` value | Type | Sent via |
|---------------|------|----------|
| `nil` | text | `sendMessage` |
| `"file"` | document | `sendDocument` (multipart) |
| `"A..."` | photo | `sendPhoto` |
| `"B..."` | video | `sendVideo` |
| `"C..."` | animation | `sendAnimation` |

### Screen

Converts a plain map into an Object struct:

```elixir
%{chat_id: 123, text: "Hello", kb: %{inline_keyboard: []}}
|> Sexy.Screen.build()
# => %Sexy.Utils.Object{chat_id: 123, text: "Hello", ...}

# Works with lists too
[screen1, screen2] |> Sexy.Screen.build()
```

### Sender

Delivers Objects to Telegram and manages the single-message lifecycle:

```elixir
# Normal send — deletes previous message, saves new mid via Session
object |> Sexy.Sender.deliver()

# Notification send — doesn't touch current screen
object |> Sexy.Sender.deliver(update_mid: false)
```

**What `deliver/2` does internally:**

1. Detect content type via `Object.detect_object_type/1`
2. Wrap text with decorative lines, set `parse_mode: "HTML"`
3. Send via appropriate `Sexy.Api` method
4. If `update_mid: true` and response is `%{"ok" => true}`:
   - `Session.get_message_id(chat_id)` — find old message
   - `Api.delete_message(chat_id, old_mid)` — delete it
   - `Session.on_message_sent(chat_id, new_mid, type, update_data)` — persist

### Notification

Send overlay or replacement notifications with built-in dismiss/navigate buttons:

```elixir
# Simple overlay — user sees dismiss button
Sexy.Notification.notify(chat_id, %{text: "Order accepted!"})

# With navigation button (mid is injected after send)
Sexy.Notification.notify(chat_id, %{text: "New order!"},
  navigate: {"View Order", fn mid -> "/transit mid=#{mid}-cmd=order-id=123" end}
)

# Replace current screen (no dismiss button)
Sexy.Notification.notify(chat_id, %{text: "Payment received!"},
  navigate: {"Go to Wallet", fn mid -> "/transit mid=#{mid}-cmd=wallet" end},
  replace: true
)

# Extra button rows
Sexy.Notification.notify(chat_id, %{text: "Error!"},
  extra_buttons: [[%{text: "Contact Support", url: "tg://user?id=123"}]]
)
```

| Option | Default | Description |
|--------|---------|-------------|
| `replace` | `false` | `false` = overlay with dismiss, `true` = replace screen |
| `navigate` | `nil` | `{"Text", "/callback"}` or `{"Text", fn mid -> "..." end}` |
| `extra_buttons` | `[]` | Additional `[[%{text, callback_data or url}]]` rows |
| `dismiss_text` | config / `"OK"` | Custom dismiss button text |

**Overlay vs Replace:**

```
OVERLAY (replace: false)              REPLACE (replace: true)
┌─────────────────────┐              ┌─────────────────────┐
│  Notification text   │              │  Notification text   │
│                      │              │                      │
│  [Navigate Button]   │              │  [Navigate Button]   │
│  [Dismiss Button]    │              │                      │
└─────────────────────┘              └─────────────────────┘
 Current screen untouched              Old screen deleted
 Dismiss deletes notification          New mid saved to session
```

### Built-in Routes

The Poller intercepts these callbacks **before** dispatching to your app:

| Callback Data | Action |
|---------------|--------|
| `/_delete mid=X` | Delete message `X`, answer callback |

Used automatically by Notification dismiss buttons. Your app never sees these.

---

## Query Format

Sexy uses a compact query format for inline keyboard callbacks:

```
/command key=value-key2=value2-key3=value3
```

Values are auto-parsed: integers, floats, booleans, strings.

```elixir
Sexy.Utils.Bot.parse_comand_and_query("/order action=view-id=42")
# => {"order", %{action: "view", id: 42}}

Sexy.Utils.get_query("/order action=view-id=42")
# => %{action: "view", id: 42}

Sexy.Utils.split_query("action=view-id=42")
# => %{action: "view", id: 42}

Sexy.Utils.stringify_query(%{action: "view", id: 42})
# => "action=view-id=42"
```

---

## API Reference

### Telegram Methods

All available via `Sexy.method()` or `Sexy.Api.method()`:

<details>
<summary><b>Messages</b></summary>

```elixir
Sexy.send_message(chat_id, "Hello!")
Sexy.send_message(json_body)
Sexy.send_photo(json_body)
Sexy.send_video(json_body)
Sexy.send_animation(json_body)
Sexy.send_document(chat_id, file, filename, caption, reply_markup_json)
Sexy.send_poll(json_body)
Sexy.send_dice(chat_id, type)           # "dice"|"bowl"|"foot"|"bask"|"dart"|"777"
Sexy.send_chat_action(chat_id, type)    # "txt"|"pic"|"vid"
Sexy.forward_message(json_body)
Sexy.copy_message(chat_id, from_chat_id, message_id)
```

</details>

<details>
<summary><b>Editing</b></summary>

```elixir
Sexy.edit_text(%{chat_id: id, message_id: mid, text: "Updated"})
Sexy.edit_reply_markup(json_body)
Sexy.edit_media(json_body)
Sexy.delete_message(chat_id, message_id)
```

</details>

<details>
<summary><b>Callbacks</b></summary>

```elixir
Sexy.answer_callback(callback_id, "Text!", true)    # show_alert
Sexy.answer_callback(%{callback_query_id: id, text: "..."})
```

</details>

<details>
<summary><b>Info & Settings</b></summary>

```elixir
Sexy.get_me()
Sexy.get_chat(chat_id)
Sexy.get_chat_member(chat_id, user_id)
Sexy.get_user_photo(user_id)
Sexy.set_commands("start - Start bot, help - Get help")
Sexy.delete_commands()
```

</details>

<details>
<summary><b>Universal</b></summary>

```elixir
Sexy.request(json_body, "sendMessage")    # any Telegram Bot API method
```

</details>

### Utilities

```elixir
# Number formatting (thousand separators)
Sexy.Utils.fiat_chunk(1_234_567, 2)      # => "1 234 567"
Sexy.Utils.fiat_chunk(99.5, 2)           # => "99.50"

# UUID <-> Base62 compact format
Sexy.Utils.stringify_uuid(uuid)           # => "6ByM..."
Sexy.Utils.normalize_uuid("6ByM...")      # => "550e8400-..."

# Deep string-to-atom key conversion
Sexy.Utils.strip(%{"key" => %{"nested" => 1}})
# => %{key: %{nested: 1}}

# Bot helpers
Sexy.Utils.Bot.get_message_type(update)   # => "text"|"photo"|"video"|...
Sexy.Utils.Bot.extract_user_obj(update)   # => %{id: ..., username: ...}
Sexy.Utils.Bot.wrap_text("Hello")         # => text with decorative borders
Sexy.Utils.Bot.paginate(list, page, size) # => sliced list (1-indexed)
```

---

## Full Config Reference

```elixir
config :sexy,
  # Required
  link: "https://api.telegram.org/bot",
  token: "BOT_TOKEN",
  session_module: MyApp.TelegramSession,
  handler_module: MyApp.Telegram,

  # Handler function names
  command_handler: :handle_command,
  query_handler: :handle_query,
  message_handler: :handle_message,
  chat_member_handler: :handle_chat_member,

  # Optional
  dismiss_text: "OK"
```

> **Tip:** Keep `token` in `config/runtime.exs` or `config/dev.local.exs` (gitignored) for security.

---

## Typical App Pattern

```elixir
# 1. Menu modules return plain maps
defmodule MyApp.Menu do
  def main(user) do
    %{
      text: "Welcome, #{user.name}!",
      kb: %{inline_keyboard: [
        [%{text: "Profile", callback_data: "/profile"}],
        [%{text: "Settings", callback_data: "/settings"}]
      ]},
      user: user,
      update_data: %{mode: "main"}
    }
  end
end

# 2. Orchestrator converts and sends
defmodule MyApp.Telegram do
  def handle_command(update) do
    user = get_or_create_user(update)
    parsed = Sexy.Utils.Bot.parse_comand_and_query(update.message.text)

    case parsed do
      {"start", _query} ->
        user
        |> MyApp.Menu.main()
        |> to_object()
        |> Sexy.Sender.deliver()
    end

    # Delete the user's command message to keep chat clean
    Sexy.delete_message(user.tid, update.message.message_id)
  end

  def handle_query(update) do
    user = get_or_create_user(update)
    parsed = Sexy.Utils.Bot.parse_comand_and_query(update.callback_query.data)

    case parsed do
      {"profile", query} ->
        user
        |> MyApp.Menu.profile(query)
        |> to_object()
        |> Sexy.Sender.deliver()
    end
  end

  # Bridge: extract chat_id from app's user struct
  defp to_object(%{user: user} = map) do
    map
    |> Map.delete(:user)
    |> Map.put(:chat_id, user.tid)
    |> Sexy.Screen.build()
  end
end

# 3. Notifications for async events
Sexy.Notification.notify(user.tid, %{text: "Your order is ready!"},
  navigate: {"View Order", fn mid -> "/transit mid=#{mid}-cmd=order-id=#{order.id}" end}
)
```

---

## Module Map

```
Sexy                    Public API facade (defdelegate to Api)
Sexy.Api                Telegram HTTP methods
Sexy.Sender             Object -> Telegram + mid lifecycle
Sexy.Screen             Map -> Object struct
Sexy.Session            Behaviour: get_message_id/1, on_message_sent/4
Sexy.Notification       Overlay/replace notifications
Sexy.Poller             GenServer polling + dispatch
Sexy.Visor              Supervisor
Sexy.Utils              Query parsing, formatting, UUID
Sexy.Utils.Bot          Command parsing, type detection
Sexy.Utils.Object       Message struct + type detection
```

---

## License

MIT
