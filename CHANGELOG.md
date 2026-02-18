# Changelog

## 0.9.1

- Move all Bot modules under `Sexy.Bot` namespace:
  - `Sexy.Api` → `Sexy.Bot.Api`
  - `Sexy.Sender` → `Sexy.Bot.Sender`
  - `Sexy.Notification` → `Sexy.Bot.Notification`
  - `Sexy.Poller` → `Sexy.Bot.Poller`
  - `Sexy.Screen` → `Sexy.Bot.Screen`
  - `Sexy.Session` → `Sexy.Bot.Session`

## 0.9.0

**Breaking**: `Sexy` split into `Sexy.Bot` + `Sexy.TDL`.

- `Sexy` module is now a namespace only — use `Sexy.Bot` as supervisor entry point
- All Bot API functions moved: `Sexy.*` → `Sexy.Bot.*`
- New `Sexy.TDL` — TDLib integration for userbot sessions
  - `Sexy.TDL.open/3`, `close/1`, `transmit/2` — session management
  - `Sexy.TDL.Backend` — port to tdlib_json_cli binary
  - `Sexy.TDL.Handler` — JSON deserialization + event routing
  - `Sexy.TDL.Registry` — ETS-based session storage
  - `Sexy.TDL.Riser` — per-account supervisor
  - 2558 auto-generated Method/Object structs from TDLib API
- New mix tasks: `mix sexy.tdl.setup`, `mix sexy.tdl.generate_types`
- Migration guide: see MIGRATION.md

## 0.8.2

- Add Telegram Stars payment methods (send_invoice, answer_pre_checkout, refund_star_payment)
- Add wallet_init for Wallet.tg integration

## 0.8.1

- Built-in /_transit route for navigation between screens

## 0.8.0

**Breaking**: Sexy is now a Supervisor, not an Application.

- Start with `{Sexy, token: "...", session: MySession}` in supervision tree
- `Sexy.Session` behaviour — single integration point (persistence + dispatch)
- Removed `Sexy.Application`, `Sexy.Visor`, config-based dispatch
- Config replaced with `persistent_term` (no more `:sexycon`)
- Added `build/1`, `send/1-2`, `notify/2-3` facade functions
- Hardcoded dismiss_text default to "OK"
- Removed `wrap_text` from Sender

## 0.7.4

- Add `Sexy.Notification` — overlay/replace notification pattern
- Dismiss button with built-in `/_delete` route in Poller
- Configurable `dismiss_text` via `Application.get_env(:sexy, :dismiss_text)`

## 0.7.3

- Remove 26 legacy short-name delegates (pm, dm, um, ui, etc.)
- Remove unused `api_url/1`

## 0.7.2

- Add `Sexy.Session` behaviour (`get_message_id/1`, `on_message_sent/4`)
- Add `Sexy.Sender` — delivers Object, manages mid lifecycle via Session callbacks
- Add `Sexy.Screen` — converts app maps to Object structs
- `Sexy.Utils.Object`: add `chat_id`, rename `update_user` → `update_data`

## 0.7.1

- Create `Sexy.Api` with readable method names (send_message, delete_message, etc.)
- Consolidate HTTP into `do_request/3` and `do_multipart/3`
- Rewrite `Sexy` as facade with `defdelegate` to `Sexy.Api`
- Legacy short names kept as backward-compat delegates

## 0.7.0

- Initial extraction from OrderMachine into standalone library
- Modules: Sexy (API client), Sexy.Poller, Sexy.Visor, Sexy.Utils, Sexy.Utils.Bot, Sexy.Utils.Object
- Dependencies: HTTPoison, Jason, Base62
