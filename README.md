<p align="center">
  <img src="https://img.shields.io/badge/elixir-%3E%3D%201.14-blueviolet?style=flat-square" />
  <img src="https://img.shields.io/badge/telegram-bot%20api%20%2B%20tdlib-26A5E4?style=flat-square&logo=telegram&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

<h1 align="center">Sexy</h1>

<p align="center">
  <b>Telegram framework for Elixir — bots and userbots from one dependency</b><br/>
  <sub>Sexy.Bot for Bot API. Sexy.TDL for TDLib. Use one or both.</sub>
</p>

---

## What is Sexy?

Sexy is a Telegram framework with two engines:

- **Sexy.Bot** — Bot API with a single-message UI pattern. Every screen replaces the previous one, creating an app-like experience inside Telegram.
- **Sexy.TDL** — TDLib integration for userbot sessions. Manages port to `tdlib_json_cli`, deserializes JSON into Elixir structs, routes events to your app.

Both can run in the same application simultaneously.

---

## Quick Start: Bot API

### 1. Add dependency

```elixir
# mix.exs
defp deps do
  [{:sexy, git: "git@github.com:Puremag1c/Sexy.git"}]
end
```

### 2. Start in your supervision tree

```elixir
children = [
  {Sexy.Bot, token: "123456:ABC-DEF...", session: MyApp.Session},
]
```

### 3. Implement Session

```elixir
defmodule MyApp.Session do
  @behaviour Sexy.Bot.Session

  # Persistence — Sexy manages one active message per chat
  @impl true
  def get_message_id(chat_id), do: MyApp.Users.get_mid(chat_id)

  @impl true
  def on_message_sent(chat_id, message_id, type, extra) do
    MyApp.Users.save_mid(chat_id, message_id, type, extra)
  end

  # Dispatch — Sexy routes updates to these callbacks
  @impl true
  def handle_command(update), do: MyApp.Bot.command(update)

  @impl true
  def handle_query(update), do: MyApp.Bot.query(update)

  @impl true
  def handle_message(update), do: MyApp.Bot.message(update)

  @impl true
  def handle_chat_member(update), do: :ok
end
```

### 4. Build and send screens

```elixir
%{
  chat_id: chat_id,
  text: "Welcome!",
  kb: %{inline_keyboard: [[%{text: "Start", callback_data: "/start"}]]}
}
|> Sexy.Bot.build()
|> Sexy.Bot.send()
```

That's it. Sexy deletes the old message, sends the new one, and saves state via your Session.

---

## Quick Start: TDLib (Userbots)

### 1. Configure

```elixir
# config/config.exs
config :sexy,
  tdlib_binary: "/path/to/tdlib_json_cli",
  tdlib_data_root: "/path/to/tdlib_data"
```

Or run the interactive setup: `mix sexy.tdl.setup`

### 2. Add to supervision tree

```elixir
children = [
  Sexy.TDL,
  # optionally alongside Sexy.Bot:
  {Sexy.Bot, token: "...", session: MyApp.Session},
]
```

### 3. Open a session

```elixir
config = %{Sexy.TDL.default_config() |
  api_id: "12345",
  api_hash: "abc123",
  database_directory: "/tmp/tdlib_data/my_account"
}

Sexy.TDL.open("my_account", config, app_pid: self())
```

### 4. Handle events

```elixir
def handle_info({:recv, struct}, state) do
  # TDLib object as Elixir struct (e.g. %Sexy.TDL.Object.UpdateNewMessage{})
end

def handle_info({:proxy_event, text}, state) do
  # proxychains output
end

def handle_info({:system_event, type, details}, state) do
  # :port_failed, :port_exited, :proxy_conf_missing
end
```

### 5. Send commands

```elixir
Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.GetMe{})
Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.SendMessage{
  chat_id: 123456,
  input_message_content: %Sexy.TDL.Object.InputMessageText{
    text: %Sexy.TDL.Object.FormattedText{text: "Hello from userbot!"}
  }
})
```

---

## Concepts

### Single-message pattern (Bot)

```
User clicks button  ->  old message deleted  ->  new message sent  ->  state saved
```

Every chat has one active screen. `Sexy.Bot.send/1` handles the full cycle: detect content type, call Telegram API, delete previous message via `Session.get_message_id/1`, save new mid via `Session.on_message_sent/4`.

### Object struct

Every message goes through `Sexy.Utils.Object` — the universal message container. Build one with `Sexy.Bot.build/1`:

```elixir
Sexy.Bot.build(%{chat_id: 123, text: "Hello!"})
#=> %Sexy.Utils.Object{chat_id: 123, text: "Hello!", ...}
```

**Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `chat_id` | integer | `nil` | Telegram chat id (**required**) |
| `text` | string | `""` | Message text or caption (HTML supported) |
| `media` | string/nil | `nil` | Content type selector (see table below) |
| `kb` | map | `%{inline_keyboard: []}` | Telegram reply markup |
| `entity` | list | `[]` | Telegram entities (bold, links, etc.). When non-empty, `parse_mode` is omitted |
| `update_data` | map | `%{}` | App-specific data passed to `Session.on_message_sent/4` as `extra` |
| `file` | binary/nil | `nil` | File content for document uploads |
| `filename` | string/nil | `nil` | Filename for document uploads |

**Media type detection** — the `media` field determines how the message is sent:

| `media` value | Sent as | API method |
|---------------|---------|------------|
| `nil` | text message | `sendMessage` |
| `"file"` | document (multipart upload) | `sendDocument` |
| starts with `"A"` | photo | `sendPhoto` |
| starts with `"B"` | video | `sendVideo` |
| starts with `"C"` | animation (GIF) | `sendAnimation` |

Telegram file_ids have predictable prefixes by type — Sexy uses this for auto-detection.

**Examples:**

```elixir
# Text message with buttons
%{chat_id: id, text: "Pick:", kb: %{inline_keyboard: [[%{text: "Go", callback_data: "/go"}]]}}

# Photo by file_id
%{chat_id: id, text: "Nice photo", media: "AgACAgIAAxk..."}

# Document upload from binary
%{chat_id: id, text: "Your report", media: "file", file: csv_binary, filename: "report.csv"}

# Pass state to on_message_sent
%{chat_id: id, text: "Cart", update_data: %{screen: "cart", page: 1}}
```

### `send/2` options

`Sexy.Bot.send(object, opts)` sends an Object and manages the message lifecycle.

| Option | Default | Description |
|--------|---------|-------------|
| `update_mid: true` | `true` | Delete previous message, save new mid via Session |
| `update_mid: false` | — | Send without touching the current screen state |

```elixir
# Normal send — replaces current screen (default)
Sexy.Bot.build(%{chat_id: id, text: "Home"}) |> Sexy.Bot.send()

# Send without replacing — useful for secondary messages
Sexy.Bot.build(%{chat_id: id, text: "Tip of the day"}) |> Sexy.Bot.send(update_mid: false)
```

### Notifications

`Sexy.Bot.notify(chat_id, message, opts)` sends notification messages separate from the main screen flow.

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `replace: false` | `false` | **Overlay** — sends without replacing current screen, adds dismiss button |
| `replace: true` | — | **Replace** — becomes new active screen (mid updated via Session) |
| `navigate: {text, path}` | `nil` | Adds a button that deletes the notification and calls `Session.handle_transit/3` |
| `navigate: {text, fn}` | `nil` | Same, but with a function `fn mid -> callback_data end` for custom routing |
| `dismiss_text: "text"` | `"OK"` | Custom dismiss button text |
| `extra_buttons: [[...]]` | `[]` | Additional button rows appended after navigate/dismiss |

```elixir
# Overlay — dismiss button, current screen untouched
Sexy.Bot.notify(chat_id, %{text: "Done!"})

# Custom dismiss text
Sexy.Bot.notify(chat_id, %{text: "Saved!"}, dismiss_text: "Got it")

# Replace — becomes new active screen
Sexy.Bot.notify(chat_id, %{text: "Payment received!"}, replace: true)

# Navigate — click deletes notification, calls Session.handle_transit/3
Sexy.Bot.notify(chat_id, %{text: "New order!"},
  navigate: {"View Order", "/order id=123"}
)

# Navigate with custom callback + extra buttons
Sexy.Bot.notify(chat_id, %{text: "Alert!"},
  navigate: {"Details", fn mid -> "/show mid=#{mid}" end},
  extra_buttons: [[%{text: "Mute", callback_data: "/mute"}]]
)
```

### TDL supervision tree

```
Sexy.TDL (Supervisor)
  |-- Sexy.TDL.Registry (ETS session storage)
  |-- AccountVisor (DynamicSupervisor)
        |-- Riser per session (one_for_all)
              |-- Backend (port to tdlib_json_cli)
              |-- Handler (JSON -> structs -> events)
              |-- ...extra children from your app
```

Open a session with `Sexy.TDL.open/3`, close with `Sexy.TDL.close/1`. Each session gets its own supervision subtree. Pass `children: [MyWorker]` in opts to inject app-specific processes.

### Auto-generated types

Sexy ships 2558 structs generated from TDLib API documentation:

- `Sexy.TDL.Method.*` — 786 API methods (GetMe, SendMessage, etc.)
- `Sexy.TDL.Object.*` — 1772 response types (UpdateNewMessage, User, Chat, etc.)

Regenerate from a different TDLib version: `mix sexy.tdl.generate_types /path/to/types.json`

---

## API Reference

### Sexy.Bot

| Function | Description |
|----------|-------------|
| `build(map)` | Map -> Object struct |
| `send(object, opts)` | Send to Telegram, manage mid lifecycle |
| `notify(chat_id, msg, opts)` | Notification with dismiss/navigate |
| `send_message(chat_id, text)` | Send text message |
| `send_photo(body)` | Send photo |
| `send_video(body)` | Send video |
| `send_animation(body)` | Send animation |
| `send_document(chat_id, file, name, text, kb)` | Send file |
| `edit_text(body)` | Edit message text |
| `edit_reply_markup(body)` | Edit buttons |
| `delete_message(chat_id, mid)` | Delete message |
| `answer_callback(id, text, alert)` | Answer callback query |
| `send_invoice(chat_id, title, desc, payload, cur, prices)` | Telegram Stars payment |
| `request(body, method)` | Any Telegram Bot API method |

### Sexy.TDL

| Function | Description |
|----------|-------------|
| `open(session, config, opts)` | Start TDLib session |
| `close(session)` | Stop session and cleanup |
| `transmit(session, msg)` | Send command to TDLib |
| `default_config()` | Base TDLib config template |

### Sexy.Bot.Session callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `get_message_id(chat_id)` | yes | Return current active mid |
| `on_message_sent(chat_id, mid, type, extra)` | yes | Save new active mid |
| `handle_command(update)` | yes | `/command` messages |
| `handle_query(update)` | yes | Button callbacks |
| `handle_message(update)` | yes | Text messages |
| `handle_chat_member(update)` | yes | Join/leave events |
| `handle_poll(update)` | no | Poll responses |
| `handle_transit(chat_id, cmd, query)` | no | Transit button clicks |

---

## Module Map

```
Sexy                        Namespace module
Sexy.Bot                    Bot API supervisor + public API
Sexy.Bot.Api                Telegram HTTP client
Sexy.Bot.Sender             Object -> Telegram + mid lifecycle
Sexy.Bot.Screen             Map -> Object struct
Sexy.Bot.Session            Behaviour: persistence + dispatch
Sexy.Bot.Notification       Overlay/replace notifications
Sexy.Bot.Poller             GenServer polling + routing
Sexy.TDL                    TDLib supervisor + open/close/transmit API
Sexy.TDL.Backend            Port to tdlib_json_cli binary
Sexy.TDL.Handler            JSON deserialization + event routing
Sexy.TDL.Registry           ETS session storage
Sexy.TDL.Riser              Per-account supervisor
Sexy.TDL.Object             1772 auto-generated TDLib object structs
Sexy.TDL.Method             786 auto-generated TDLib method structs
Sexy.Utils                  Query parsing, formatting, type conversion
Sexy.Utils.Bot              Command parsing, pagination
Sexy.Utils.Object           Message struct + type detection
```

---

## Mix Tasks

| Task | Description |
|------|-------------|
| `mix sexy.tdl.setup` | Interactive TDLib configuration wizard |
| `mix sexy.tdl.generate_types [path]` | Regenerate Method/Object structs from types.json |

---

## Migration

Upgrading from an older version? See [MIGRATION.md](MIGRATION.md).

## License

MIT
