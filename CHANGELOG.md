# Changelog

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

- Initial library release
- Supervisor + Session-only integration
- Poller, Api, Sender, Screen, Notification modules
- Built-in /_delete route
