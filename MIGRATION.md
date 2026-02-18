# Migrating to Sexy 0.8

Guide for moving old bots (with inline/embedded Sexy) to the new Sexy library.

---

## Before You Start

**Old pattern** (inline Sexy):
- `Sexy` module lives inside the project (`lib/mybot/sexy.ex`)
- Short function names: `pm`, `dm`, `ui`, `um`, `uni`, `shout`, etc.
- `sexycon` built from config: `link <> token <> "/"`
- Manual message lifecycle: `Sexy.dm(user.tid, user.mid)` + `Users.update_user(user, %{mid: ...})`
- Routing in a separate module (`Penetration`, etc.) with `case parseCommand(...)` switch
- `Poison` for JSON encoding

**New pattern** (library):
- `{:sexy, git: "git@github.com:Puremag1c/Sexy.git"}` dependency
- Start as `{Sexy, token: "...", session: MyApp}` in supervision tree
- `MyApp` implements `@behaviour Sexy.Session` (persistence + dispatch)
- `Sexy.build()` + `Sexy.send()` handle full lifecycle automatically
- `Sexy.notify()` for notifications with auto-transit
- Built-in polling, /_delete, /_transit routes
- `Jason` for JSON encoding

---

## Step-by-Step Migration

### Phase 1: Add dependency, remove inline Sexy

**1.1. mix.exs — add Sexy, remove Poison (switch to Jason)**
```elixir
# Remove:
{:poison, "~> ..."}

# Add:
{:sexy, git: "git@github.com:Puremag1c/Sexy.git"},
{:jason, "~> 1.2"},
{:httpoison, "~> 1.8", override: true}  # Sexy uses HTTPoison internally
```

> **Note**: Sexy uses `Jason`, not `Poison`. Replace all `Poison.encode!/decode!` with `Jason.encode!/decode!` across the project. This is a mechanical find-and-replace.

**1.2. Delete inline Sexy files**
```
lib/mybot/sexy.ex          → DELETE (replaced by library)
lib/mybot/sexy/poller.ex   → DELETE (built into library)
lib/mybot/sexy/penetration.ex → KEEP but rewrite as Session (see Phase 3)
lib/mybot/sexy/nurse.ex    → KEEP (app-specific, not Sexy-related)
lib/mybot/sexy/chic.ex     → KEEP (app-specific)
lib/mybot/sexy/tatoo.ex    → KEEP (app-specific)
lib/mybot/sexy/x-ui.ex     → KEEP (app-specific)
```

**Rule**: Delete only files that Sexy library replaces (HTTP wrappers, polling, strip). Keep app-specific integrations (payments, external APIs).

**1.3. Move app-specific Sexy submodules to app namespace**

Rename `Sexy.Nurse` → `MyApp.Nurse`, `Sexy.Chic` → `MyApp.Chic`, etc. These are NOT part of the Sexy library — they just lived in the Sexy folder by convention.

**1.4. config — remove old sexy config**
```elixir
# Remove from config.exs:
config :myapp,
  sexycon: "...",
  link: "..."

# Keep token in dev.local.exs / runtime.exs:
config :sexy, token: "BOT_TOKEN"
```

### Phase 2: Implement Session behaviour

**2.1. Add `@behaviour Sexy.Session` to your main module**

The Session behaviour is the single integration point. It handles both persistence (message state) and dispatch (update routing).

```elixir
defmodule MyApp do
  @behaviour Sexy.Session

  # ── Persistence ──

  @impl true
  def get_message_id(chat_id) do
    case Users.getuser("#{chat_id}") do
      nil -> nil
      user -> user.mid  # NOTE: mid may be stored as string, see gotcha below
    end
  end

  @impl true
  def on_message_sent(chat_id, message_id, type, extra) do
    case Users.getuser("#{chat_id}") do
      nil -> :ok
      user -> Users.update_user(user, Map.merge(extra, %{mid: message_id, mtype: type}))
    end
  end

  # ── Dispatch ──

  @impl true
  def handle_command(update), do: ...  # was reactCommand(u)

  @impl true
  def handle_query(update), do: ...    # was reactQuery(u)

  @impl true
  def handle_message(update), do: ...  # was message(u)

  @impl true
  def handle_chat_member(update), do: ... # was chatMember(u)

  # handle_transit/3 — optional, only if you use Sexy.notify with navigate
  # handle_poll/1 — optional
end
```

**2.2. Start Sexy in supervision tree**
```elixir
# lib/mybot/application.ex
children = [
  # ... your other children ...
  {Sexy, token: Application.get_env(:sexy, :token), session: MyApp},
  # Remove: Sexy.Poller (now started by Sexy internally)
]
```

### Phase 3: Rewrite message sending

This is the biggest change. Replace manual send + delete + update_user with `Sexy.build()` + `Sexy.send()`.

**Old pattern** (manual lifecycle):
```elixir
def sendmessage(user, obj) do
  # 1. Detect type
  # 2. Encode JSON with Poison
  # 3. Call Sexy.pm / Sexy.uni
  # 4. Sexy.dm(user.tid, user.mid)  — delete old message
  # 5. Users.update_user(user, %{mid: "#{r["result"]["message_id"]}", ...})
end
```

**New pattern** (automatic lifecycle):
```elixir
def sendmessage(user, obj) do
  obj
  |> Map.put(:chat_id, user.tid)
  |> Map.put(:update_data, %{state: obj.state})
  |> Sexy.build()
  |> Sexy.send()
end
```

`Sexy.send()` automatically:
1. Detects content type (text/photo/video/animation/file)
2. Sends via appropriate Telegram API method
3. Calls `Session.get_message_id(chat_id)` → deletes old message
4. Calls `Session.on_message_sent(chat_id, new_mid, type, update_data)` → saves state

**Object map fields**:
| Field | Required | Description |
|-------|----------|-------------|
| `chat_id` | yes | Telegram chat ID |
| `text` | yes | Message text (or caption for media) |
| `kb` | no | `%{inline_keyboard: [[...]]}` |
| `media` | no | nil=text, "A..."=photo, "B..."=video, "C..."=animation |
| `entity` | no | Telegram entities (default: `[]`) |
| `update_data` | no | Map passed to `on_message_sent` (state, mode, etc.) |
| `file` / `filename` | no | For document uploads |

### Phase 4: Replace API calls

**Function name mapping (old → new)**:

| Old (inline) | New (library) | Notes |
|-------------|--------------|-------|
| `Sexy.pm(chat_id, text)` | `Sexy.send_message(chat_id, text)` | |
| `Sexy.pm(json_body)` | `Sexy.send_message(json_body)` | |
| `Sexy.dm(chat_id, mid)` | `Sexy.delete_message(chat_id, mid)` | |
| `Sexy.um(json_body)` | `Sexy.edit_text(decoded_map)` | Takes map, not JSON string |
| `Sexy.ui(json_body)` | `Sexy.edit_reply_markup(json_body)` | |
| `Sexy.umm(json_body)` | `Sexy.edit_media(json_body)` | |
| `Sexy.p(json_body)` | `Sexy.send_photo(json_body)` | |
| `Sexy.v(json_body)` | `Sexy.send_video(json_body)` | |
| `Sexy.a(json_body)` | `Sexy.send_animation(json_body)` | |
| `Sexy.uni(body, method)` | `Sexy.request(body, method)` | |
| `Sexy.shout(id, text, alert)` | `Sexy.answer_callback(id, text, alert)` | |
| `Sexy.dice(id, type)` | `Sexy.send_dice(id, type)` | |
| `Sexy.act(id, type)` | `Sexy.send_chat_action(id, type)` | |
| `Sexy.quiz(body)` | `Sexy.send_poll(body)` | |
| `Sexy.share(body)` | `Sexy.forward_message(body)` | |
| `Sexy.copy(where, from, msg)` | `Sexy.copy_message(where, from, msg)` | |
| `Sexy.uf(id, file, name, text, kb)` | `Sexy.send_document(id, file, name, text, kb)` | |
| `Sexy.getu(id)` | `Sexy.get_chat(id)` | |
| `Sexy.uph(id)` | `Sexy.get_user_photo(id)` | |
| `Sexy.gogo(offset)` | N/A | Built into Poller, never call directly |
| `Sexy.strip(map)` | `Sexy.Utils.strip(map)` | |
| `Sexy.setmenu()` | `Sexy.set_commands("cmd1 - Desc, cmd2 - Desc")` | Different format |
| `Sexy.delmenu()` | `Sexy.delete_commands()` | |
| `Sexy.pay(tid, inv, period, sum, title, desc)` | `Sexy.send_invoice(tid, title, desc, inv, "XTR", [%{label: period, amount: sum}])` | Stars payments |
| `Sexy.payOk(id)` | `Sexy.answer_pre_checkout(id)` | |
| `Sexy.refundStarPayment(tid, charge_id)` | `Sexy.refund_star_payment(tid, charge_id)` | |

### Phase 5: Replace notifications

**Old infopush pattern**:
```elixir
def infopush(id, message) do
  user = Users.getuser("#{id}")
  r = Sexy.pm(Poison.encode!(%{chat_id: id, text: frame_text(message)}))
  Sexy.dm(user.tid, user.mid)
  Sexy.ui(Poison.encode!(%{
    chat_id: id,
    message_id: r["result"]["message_id"],
    reply_markup: %{inline_keyboard: [[%{text: "Я прочитал", callback_data: "/archive #{r["result"]["message_id"]}"}]]}
  }))
  Users.update_user(user, %{mid: nil})
end
```

**New pattern**:
```elixir
def infopush(id, message) do
  Sexy.notify(id, %{text: message})
end
```

`Sexy.notify` automatically:
- Sends the message (without touching current screen)
- Adds a dismiss button (default text: "OK", customizable via `dismiss_text:`)
- Dismiss button triggers built-in `/_delete` route

**With navigation (transit)**:
```elixir
# Old: manual callback construction
callback_data: "/archive #{mid}" # → calls archive(), which calls start()

# New: auto-transit
Sexy.notify(id, %{text: message},
  navigate: {"Go to menu", "/start"}
)
```

Click deletes notification and calls `Session.handle_transit(chat_id, "start", %{})`.

### Phase 6: Remove manual delete/archive handlers

Old bots typically have `archive(u)` and `delete(u)` handlers that manually delete messages. These are replaced by Sexy's built-in routes:

- `/_delete mid=X` — auto-handled by Poller (deletes message X)
- `/_transit mid=X-cmd=Y-...` — auto-handled by Poller (deletes X, calls `Session.handle_transit`)

**Remove** these from your routing:
```elixir
# Remove from command/query routing:
"archive" -> archive(u)
"delete" -> delete(u)
```

**Delete** the functions themselves if they only do `Sexy.dm` + redirect.

### Phase 7: Routing cleanup

**Old** (Penetration module with import):
```elixir
defmodule Sexy.Penetration do
  import Vpnbot

  def reactCommand(u) do
    case parseCommand(u.message.text) do
      "start" -> start(u)
      "info" -> info(u)
      ...
    end
  end
end
```

**New** (inline in main module as Session callbacks):
```elixir
defmodule MyApp do
  @behaviour Sexy.Session

  @impl true
  def handle_command(u) do
    {cmd, _query} = Sexy.Utils.Bot.parse_comand_and_query(u.message.text)
    case cmd do
      "start" -> start(u)
      "info" -> info(u)
      ...
    end
    # Optionally: Sexy.delete_message(user.tid, u.message.message_id)
  end

  @impl true
  def handle_query(u) do
    {cmd, query} = Sexy.Utils.Bot.parse_comand_and_query(u.callback_query.data)
    case cmd do
      "start" -> start(u)
      "buy" -> SubscriptionProcessor.buy_service(u)
      ...
    end
  end
end
```

---

## Gotchas

### 1. mid stored as string vs integer
Old bots often store `mid` as string (`"#{r["result"]["message_id"]}`). New Sexy passes integers from Telegram API. Either:
- Change your schema to store integer
- Or convert in `get_message_id`: `String.to_integer(user.mid)`

### 2. Poison → Jason
Mechanical replacement but watch for:
- `Poison.encode/decode` (returns `{:ok, _}`) vs `Poison.encode!/decode!` (returns value)
- Jason has the same API: `Jason.encode!/decode!`

### 3. frame_text / wrap_text removed from Sender
Old Sexy wrapped text in decorative borders automatically. New Sexy does NOT. If you want borders, call your own `frame_text()` in your menu modules before building the object.

### 4. sexycon → persistent_term
Old: `Application.get_env(:vpnbot, :sexycon)` built the URL at config time.
New: Sexy builds URL internally from token and stores in `:persistent_term`. No config needed.

### 5. Application.get_env(:vpnbot, Sexy, Sexy)
Some old bots use this pattern for testing. Remove it — just call `Sexy.send_message(...)` directly.

### 6. state vs update_data
Old bots pass `state: "mode"` in the object to save in `sendmessage`. New Sexy uses `update_data: %{...}` which gets forwarded to `on_message_sent/4` as the `extra` parameter.

```elixir
# Old:
%{text: "...", kb: [...], state: "mymode"}
sendmessage(user, obj)  # manually saves obj.state

# New:
%{text: "...", kb: [...], chat_id: user.tid, update_data: %{state: "mymode"}}
|> Sexy.build()
|> Sexy.send()
# on_message_sent receives %{state: "mymode"} as extra, you save it there
```

### 7. pre_checkout_query / successful_payment
These Telegram payment events are NOT routed through Session callbacks. You'll need to keep handling them in `handle_message` or `handle_query`, or add custom routing in your dispatch.

Check if your Penetration module handles:
- `pre_checkout_query` → call `Sexy.answer_pre_checkout(id)`
- `successful_payment` → detect in `handle_message` via `Map.has_key?(u.message, :successful_payment)`

### 8. Concurrent message processing
Old Poller may use `Task.async_stream` with `maxconcurrency: 10`. New Sexy Poller uses `Task.start` per update (fire-and-forget). If you need concurrency control, handle it in your Session callbacks.

---

## Migration Checklist

```
[ ] 1. Add {:sexy, git: ...} to mix.exs
[ ] 2. Replace {:poison, ...} with {:jason, ...}
[ ] 3. Delete inline sexy.ex and sexy/poller.ex
[ ] 4. Rename app-specific Sexy.* modules to MyApp.*
[ ] 5. Remove :sexycon / :link from config
[ ] 6. Add config :sexy, token: "..." to dev.local.exs + runtime.exs
[ ] 7. Implement @behaviour Sexy.Session in main module
[ ] 8. Add {Sexy, token: ..., session: MyApp} to supervision tree
[ ] 9. Remove Sexy.Poller from supervision tree
[ ] 10. Replace sendmessage() with Sexy.build() |> Sexy.send()
[ ] 11. Replace infopush/techpush/push with Sexy.notify()
[ ] 12. Replace Sexy.pm/dm/ui/um/etc with Sexy.send_message/delete_message/etc
[ ] 13. Replace all Poison.encode!/decode! with Jason.encode!/decode!
[ ] 14. Remove archive/delete handlers (now built-in)
[ ] 15. Move routing from Penetration to Session callbacks
[ ] 16. Handle frame_text in app code (not in Sender)
[ ] 17. Fix mid type (string → integer) if needed
[ ] 18. Handle pre_checkout_query / successful_payment in dispatch
[ ] 19. mix compile --force (zero warnings)
[ ] 20. Test: send command, receive screen, click button, notifications
```

---

# Migrating to Sexy 0.9

Guide for updating from Sexy 0.8 to 0.9. Main change: `Sexy` split into `Sexy.Bot` + `Sexy.TDL`.

---

## What Changed

- `Sexy` is no longer a supervisor — it's just a namespace module
- Bot API moved to `Sexy.Bot` (same API, new module name)
- New `Sexy.TDL` module for TDLib userbot sessions

## Step 1: Update Supervision Tree

```elixir
# Before (0.8):
children = [
  {Sexy, token: "BOT_TOKEN", session: MyApp.Session},
]

# After (0.9):
children = [
  {Sexy.Bot, token: "BOT_TOKEN", session: MyApp.Session},
]
```

## Step 2: Update API Calls

All public API moved from `Sexy` to `Sexy.Bot`:

```elixir
# Before (0.8):
Sexy.build(map) |> Sexy.send()
Sexy.notify(chat_id, msg)
Sexy.send_message(chat_id, text)
Sexy.delete_message(chat_id, mid)

# After (0.9):
Sexy.Bot.build(map) |> Sexy.Bot.send()
Sexy.Bot.notify(chat_id, msg)
Sexy.Bot.send_message(chat_id, text)
Sexy.Bot.delete_message(chat_id, mid)
```

This applies to all delegates: `send_photo`, `send_video`, `edit_text`, `answer_callback`, etc.

## Step 2.5: Update Session Behaviour

```elixir
# Before (0.8):
@behaviour Sexy.Session

# After (0.9):
@behaviour Sexy.Bot.Session
```

## Step 3 (Optional): Add TDLib Support

If you want to run userbot sessions via TDLib:

**3.1. Configure TDLib paths**
```elixir
# config/config.exs
config :sexy,
  tdlib_binary: "/path/to/tdlib_json_cli",
  tdlib_data_root: "/path/to/tdlib_data"
```

**3.2. Add Sexy.TDL to supervision tree**
```elixir
children = [
  {Sexy.Bot, token: "BOT_TOKEN", session: MyApp.Session},
  Sexy.TDL,
]
```

**3.3. Open a userbot session**
```elixir
config = %{Sexy.TDL.default_config() | api_id: "12345", api_hash: "abc123"}
Sexy.TDL.open("my_session", config, app_pid: self())
```

**3.4. Handle incoming events**
```elixir
def handle_info({:recv, struct}, state) do
  # TDLib object received
end

def handle_info({:proxy_event, text}, state) do
  # proxychains output
end

def handle_info({:system_event, type, details}, state) do
  # port_failed, port_exited, proxy_conf_missing
end
```

**3.5. Send commands**
```elixir
Sexy.TDL.transmit("my_session", %Sexy.TDL.Method.GetMe{})
```

## Migration Checklist

```
[ ] 1. {Sexy, ...} → {Sexy.Bot, ...} in Application children
[ ] 2. @behaviour Sexy.Session → @behaviour Sexy.Bot.Session
[ ] 3. Sexy.build/send/notify → Sexy.Bot.build/send/notify
[ ] 4. All Sexy.* API calls → Sexy.Bot.* (send_message, delete_message, etc.)
[ ] 5. mix compile --force (zero warnings)
[ ] 6. Test: send command, receive screen, click button, notifications
```
