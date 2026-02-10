<p align="center">
  <img src="https://img.shields.io/badge/elixir-%3E%3D%201.14-blueviolet?style=flat-square" />
  <img src="https://img.shields.io/badge/telegram-bot%20api-26A5E4?style=flat-square&logo=telegram&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

<h1 align="center">Sexy</h1>

<p align="center">
  <b>Single-message Telegram Bot framework for Elixir</b><br/>
  <sub>Two params to start. One behaviour to implement. Zero config keys.</sub>
</p>

---

## Philosophy

Most Telegram bots flood the chat with messages. Sexy takes a different approach: **one active message per user**. Every new screen replaces the previous one, creating a clean, app-like experience inside Telegram.

```
User clicks button  ->  old message deleted  ->  new message sent  ->  state saved
```

---

## Quick Start

### 1. Add dependency

```elixir
# mix.exs
defp deps do
  [{:sexy, git: "git@github.com:Puremag1c/Sexy.git"}]
end
```

### 2. Start in your supervision tree

```elixir
# lib/my_app/application.ex
children = [
  # ...
  {Sexy, token: Application.get_env(:sexy, :token), session: MyApp.TelegramSession},
]
```

```elixir
# config/dev.local.exs (not in git!)
config :sexy, token: "123456:ABC-DEF..."
```

That's it. Two params: `token` and `session`.

### 3. Implement Session

The Session behaviour is the **only** integration point. It handles both persistence (message state) and dispatch (update routing).

```elixir
defmodule MyApp.TelegramSession do
  @behaviour Sexy.Session

  # ── Persistence ──

  @impl true
  def get_message_id(chat_id) do
    case MyApp.Users.get_by_tid(chat_id) do
      nil -> nil
      user -> user.last_message_id
    end
  end

  @impl true
  def on_message_sent(chat_id, message_id, type, extra) do
    user = MyApp.Users.get_by_tid(chat_id)
    MyApp.Users.update(user, Map.merge(extra, %{last_message_id: message_id, message_type: type}))
  end

  # ── Dispatch ──

  @impl true
  def handle_command(update), do: MyApp.Bot.handle_command(update)

  @impl true
  def handle_query(update), do: MyApp.Bot.handle_query(update)

  @impl true
  def handle_message(update), do: MyApp.Bot.handle_message(update)

  @impl true
  def handle_chat_member(update), do: MyApp.Bot.handle_chat_member(update)

  # ── Transit (optional) ──

  @impl true
  def handle_transit(chat_id, command, query) do
    user = MyApp.Users.get_by_tid(chat_id)
    MyApp.Bot.handle_query({command, query}, user)
  end

  # handle_poll/1 is also optional
end
```

---

## Core API

```elixir
# Build Object struct from map
Sexy.build(%{chat_id: 123, text: "Hello", kb: %{inline_keyboard: []}})

# Send Object to Telegram (manages single-message lifecycle)
object |> Sexy.send()
object |> Sexy.send(update_mid: false)  # don't touch current screen

# Send notification with dismiss/navigate buttons
Sexy.notify(chat_id, %{text: "Order accepted!"})
Sexy.notify(chat_id, %{text: "New order!"},
  navigate: {"View", "/order"},
  replace: true
)
```

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
        │      Sexy.build()        │  <- map -> Object struct
        └───────────┬──────────────┘
                    │
        ┌───────────▼──────────────┐
        │      Sexy.send()         │  <- detect type, send, manage mid
        │                          │
        │  ┌─────────────────────┐ │
        │  │   Sexy.Session      │ │  <- get_message_id / on_message_sent
        │  │   (your impl)       │ │     + handle_command/query/message/...
        │  └─────────────────────┘ │
        └───────────┬──────────────┘
                    │
        ┌───────────▼──────────────┐
        │      Sexy.Api            │  <- HTTP to Telegram
        └──────────────────────────┘
```

---

## Object

The universal message struct:

```elixir
%Sexy.Utils.Object{
  chat_id: 123456789,
  text: "Hello!",
  media: nil,           # nil = text, "A..." = photo, "B..." = video, "C..." = animation
  kb: %{inline_keyboard: [[%{text: "Click", callback_data: "/action"}]]},
  entity: [],           # Telegram entities
  update_data: %{},     # pass-through to on_message_sent
  file: nil,            # for document uploads
  filename: nil
}
```

## Notification

```elixir
# Overlay — dismiss button, current screen untouched
Sexy.notify(chat_id, %{text: "Done!"})

# Replace — becomes new current screen
Sexy.notify(chat_id, %{text: "Payment received!"}, replace: true)

# With transit — clicks deletes notification, calls Session.handle_transit
Sexy.notify(chat_id, %{text: "New order!"},
  navigate: {"View Order", "/order id=123"}
)

# Extra buttons
Sexy.notify(chat_id, %{text: "Error!"},
  extra_buttons: [[%{text: "Support", url: "tg://user?id=123"}]]
)
```

| Option | Default | Description |
|--------|---------|-------------|
| `replace` | `false` | `false` = overlay with dismiss, `true` = replace screen |
| `navigate` | `nil` | `{"Text", "/command query"}` — auto-transit via `/_transit` |
| `extra_buttons` | `[]` | Additional button rows |
| `dismiss_text` | `"OK"` | Custom dismiss button text |

---

## Telegram API

All methods available via `Sexy.method()` or `Sexy.Api.method()`:

```elixir
Sexy.send_message(chat_id, "Hello!")
Sexy.send_message(json_body)
Sexy.send_photo(json_body)
Sexy.send_video(json_body)
Sexy.send_animation(json_body)
Sexy.send_document(chat_id, file, filename, caption, reply_markup_json)
Sexy.send_poll(json_body)
Sexy.send_dice(chat_id, type)
Sexy.send_chat_action(chat_id, type)
Sexy.forward_message(json_body)
Sexy.copy_message(chat_id, from_chat_id, message_id)
Sexy.edit_text(%{chat_id: id, message_id: mid, text: "Updated"})
Sexy.edit_reply_markup(json_body)
Sexy.edit_media(json_body)
Sexy.delete_message(chat_id, message_id)
Sexy.answer_callback(callback_id, "Text!", true)
Sexy.get_me()
Sexy.get_chat(chat_id)
Sexy.get_chat_member(chat_id, user_id)
Sexy.get_user_photo(user_id)
Sexy.set_commands("start - Start bot, help - Get help")
Sexy.delete_commands()
Sexy.send_invoice(chat_id, "Title", "Desc", "payload_123", "XTR", [%{label: "30 days", amount: 100}])
Sexy.answer_pre_checkout(pre_checkout_query_id)
Sexy.refund_star_payment(user_id, telegram_payment_charge_id)
Sexy.request(json_body, "anyMethod")
```

---

## Utilities

```elixir
Sexy.Utils.fiat_chunk(1_234_567, 2)           # => "1 234 567"
Sexy.Utils.stringify_uuid(uuid)                # => "6ByM..."
Sexy.Utils.normalize_uuid("6ByM...")           # => "550e8400-..."
Sexy.Utils.strip(%{"key" => %{"nested" => 1}}) # => %{key: %{nested: 1}}
Sexy.Utils.Bot.parse_comand_and_query("/order action=view-id=42")
Sexy.Utils.Bot.paginate(list, page, size)
```

---

## Module Map

```
Sexy                    Supervisor + public API facade
Sexy.Api                Telegram HTTP methods
Sexy.Sender             Object -> Telegram + mid lifecycle
Sexy.Screen             Map -> Object struct
Sexy.Session            Behaviour: persistence + dispatch + transit
Sexy.Notification       Overlay/replace notifications
Sexy.Poller             GenServer polling + dispatch
Sexy.Utils              Query parsing, formatting, UUID
Sexy.Utils.Bot          Command parsing, type detection
Sexy.Utils.Object       Message struct + type detection
```

---

## License

MIT
