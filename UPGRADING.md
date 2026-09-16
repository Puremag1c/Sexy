# Upgrading to 0.11.1

0.11.1 changes how proxy mode is selected. No Bot API changes.

## Proxy mode: pass the config path

* **Before:** `Sexy.TDL.open/3` with `proxy: true` expected a `proxy.conf`
  at `<tdlib_data_root>/<session>/proxy.conf`; a missing file was reported
  as a `{:system_event, :proxy_conf_missing, path}` message and the port
  still tried to launch.
* **Now:** pass the path itself — `proxy: "/etc/proxychains/my-account.conf"`
  (`proxy: false`, the default, means no proxy). A missing file fails
  `open/3` synchronously with the standard port error
  (`{:port_failed, :proxy_conf_missing}` inside the usual supervisor
  wrapper) — the same shape as any other port failure, no special casing.
* **Do:** replace `proxy: true` with your config path; drop the per-session
  `proxy.conf` convention if you had one. Sessions started without a proxy
  are unaffected.

---

# Upgrading to 0.11.0

0.11.0 ships prebuilt `tdlib_json_cli` binaries with platform auto-detection
and regenerates the TDLib types for **TDLib 1.8.66**. No Bot API changes.

## Binary resolution

* **Before:** `config :sexy, :tdlib_binary` was required; you built
  `tdlib_json_cli` yourself.
* **Now:** optional. Without it, `Sexy.TDL` downloads the prebuilt binary for
  your platform (`linux-x64`, `linux-arm64`, `macos-arm64`) at startup into
  the user cache (`~/.cache/sexy` on Linux, `~/Library/Caches/sexy` on
  macOS), verifying its sha256 against `priv/tdlib/manifest.json`. A
  configured path stays authoritative — it is used as-is and never falls
  back to auto-download.
* **Do (recommended):** delete `:tdlib_binary` from config, keep
  `:tdlib_data_root`. First start needs outbound HTTPS to github.com;
  prefetch with `mix sexy.tdl.install` where that's a problem.
  `SEXY_TDLIB_PATH` overrides without a config change.
* **Do (own build):** keep `:tdlib_binary` pointing at your binary — but
  rebuild it from TDLib 1.8.66 (see below).

## TDLib 1.8.66 types

* Object/Method structs jump from TDLib ~1.8.0-era to 1.8.66: 2370 objects +
  1010 methods (was 1772 + 786). Telegram renamed/removed some types in
  between — code matching on structs that no longer exist breaks; run your
  suite after upgrading.
* The shipped binary and the structs are generated from the **same TDLib
  commit**. An old self-built binary speaks the old schema and will produce
  events the new structs don't model — upgrade the binary together with the
  library (simplest: drop `:tdlib_binary` and let it auto-download).
* Freeze/ban detection (non-JSON `ACCOUNT_FROZEN`/`FROZEN_METHOD_INVALID`
  error forwarding) is unchanged and verified against 1.8.66's log format.
  Still, canary one session before rolling a fleet.

## Proxy mode

proxychains keeps working: prebuilt linux binaries link libc dynamically
(`LD_PRELOAD` requires that), with OpenSSL/zlib/libstdc++ static. The
proxychains command now quotes the binary and `proxy.conf` paths.

---

# Upgrading to 0.10.0

0.10.0 is a reliability release: 37 audited defects fixed across the Bot core,
the TDL runtime, and the mix tasks. Most fixes are invisible. This guide lists
every public call whose **observable behavior changed** and what to do about it.

## Sexy.Bot

### `Sexy.Bot.start_link/1` — fails fast on bad config

* **Before:** `token: nil` (unset env var) or a typo'd `session:` module started
  a green supervision tree that silently never worked.
* **Now:** raises `ArgumentError` at boot for a nil/empty token; raises if the
  session module can't be loaded.
* **Do:** nothing if your config is correct. If your deploy relied on the bot
  booting without a token, set `BOT_TOKEN` before start.

### `Sexy.Bot.send/2` with a list — returns per-item results

* **Before:** `send([a, b, c])` returned `:ok`, discarding every response.
* **Now:** returns the list of Telegram responses in order, so partial failures
  (blocked users, rate limits) are visible.
* **Do:** if you pattern-matched `:ok = Sexy.Bot.send(list)`, match the list
  instead: `results = Sexy.Bot.send(list)`. Single-object `send/2` is unchanged.

### Rate limiting — automatic single retry

* **Before:** a 429 from Telegram was logged and lost.
* **Now:** the send is retried once after the `retry_after` interval Telegram
  asks for. The call **blocks** for that time (seconds).
* **Do:** nothing. For large broadcasts, still check per-item results.

### `Sexy.Bot.notify/3` — button failure is no longer silent

* **Before:** if the message was sent but the dismiss/navigate buttons could not
  be attached (rate limit, `callback_data` over 64 bytes), `notify` returned
  `"ok" => true` and the user got an undismissable notification.
* **Now:** returns that error map (`"ok" => false`) with `"result"` still
  holding the sent message, so `message_id` stays available.
* **Do:** if you check `notify(...)["ok"]`, decide how to handle the partial
  case; `["result"]["message_id"]` is present either way when the send worked.

### API error returns — error maps instead of exceptions

* **Before:** a non-JSON response (e.g. an HTML 502 from a proxy during a
  Telegram outage) raised `Jason.DecodeError` in *your* calling process; some
  transport errors raised `Protocol.UndefinedError` inside the error handler.
* **Now:** every `Sexy.Bot.Api` method returns the documented
  `%{"ok" => false, "description" => ...}` map for any transport/JSON failure.
* **Do:** remove any `rescue Jason.DecodeError` you added around send calls.
  Note: transport error descriptions now use `inspect/1`
  (`"HTTP error: :timeout"` instead of `"HTTP error: timeout"`).

### Callback query format — dashes in values now parse

* **Before:** `Sexy.Utils.split_query/1` split pairs on every `-`, silently
  corrupting values containing dashes: `"id=-1001234-page=2"` parsed as
  `%{id: "", page: 2}`. The library's own `notify(..., navigate: ...)` flow was
  affected.
* **Now:** `-` splits pairs only when followed by `key=`. Negative IDs, UUIDs,
  and dates in values round-trip correctly. Old callback buttons already in
  chats keep parsing the same (or better).
* **Do:** nothing, unless a value must contain the literal sequence `-key=` —
  that sequence is reserved as the pair separator; `=` in values remains
  unsupported.

### Session callbacks — optional means optional

* **Before:** `handle_poll/1` was documented optional but dispatched
  unconditionally (crash per poll update if missing); `handle_transit/3` was
  invoked unguarded, *after* the message was already deleted.
* **Now:** all optional callbacks are guarded. `/_transit` verifies the handler
  exists before deleting anything. `handle_poll/1` now also receives
  `%{poll_answer: ...}` updates (individual votes), which were previously
  dropped as unknown.
* **Do:** if you implement `handle_poll/1`, be ready for both `%{poll: ...}`
  and `%{poll_answer: ...}` shapes.

### Delivery semantics (informational)

The poller now survives malformed updates, network noise, and handler crashes,
and the update offset survives poller restarts. Delivery remains
**at-least-once**: a batch can be re-dispatched after a crash in the
confirmation window. Keep payment handlers idempotent (deduplicate by
`update_id` or `telegram_payment_charge_id`).

Updates of the **same chat are now processed in order** (partitioned dispatch
keyed by chat id) — previously all updates ran as unordered concurrent tasks
and two quick messages from one user could be handled in reverse. Different
chats still run concurrently. Note the ceiling: a slow handler delays other
chats that hash into the same partition.

## Sexy.TDL

### `Sexy.TDL.open/3` — honest returns

* **Before:** opening a session name that was already running silently clobbered
  the running session's registry entry and started a second tdlib on the same
  database. Opening with a broken `:tdlib_binary` returned `{:ok, pid}` and the
  failure event went nowhere.
* **Now:** returns `{:error, {:already_started, pid}}` for a duplicate name and
  `{:error, reason}` (synchronously) when the port can't be opened.
* **Do:** handle the two error tuples if you retry opens.

### `Sexy.TDL.close/1` — actually closes

* **Before:** `close/1` stopped the session supervisor, which the
  `DynamicSupervisor` then immediately resurrected: the session survived as a
  zombie or crash-looped the whole account supervisor. Closing a stale session
  could exit the caller with `:noproc`.
* **Now:** the session is terminated for real (`terminate_child`), never
  resurrected, and `close/1` never exits the caller.
* **Do:** nothing — `close/1` now does what its docs always claimed.

### Port death — automatic restart, then permanent stop

* **Before (no proxy):** tdlib dying was *undetectable* — transmits silently
  vanished, no event, no restart. **Before (proxy):** detected but the session
  stayed a zombie forever.
* **Now:** the Backend/Handler pair restarts with a fresh port automatically
  (up to 5 times in 30s). You still get `{:system_event, :port_exited, status}`
  before each restart. A session that keeps failing dies alone — it does not
  cascade into other sessions. Its registry entry is cleaned up automatically.
* **Do:** monitor the pid from `open/3` (or watch for repeated `:port_exited`)
  if you want to re-open persistently failing sessions yourself.

### System/proxy events — delivered directly

* **Before:** `{:system_event, ...}`/`{:proxy_event, ...}` were relayed through
  the Handler and were lost on cold start and during restarts.
* **Now:** the Backend sends them straight to your `app_pid`. Same tuples, same
  `handle_info` clauses — they just actually arrive now.
* **Do:** nothing.

### Supervision shape

`Sexy.TDL`'s children now use `:rest_for_one`: if the session Registry crashes,
dependent processes restart into a consistent empty state instead of running as
zombies against an empty table. After such a reset (or any session supervisor
death) re-open your sessions — entries no longer linger with dead pids.

### `Sexy.TDL.transmit/2` — meaningful return value

* **Before:** returned the raw message tuple from `Kernel.send/2` (useless), and
  "successfully" wrote into dead ports (the data silently vanished). During a
  Backend restart it exited the caller with `:noproc`.
* **Now:** returns `:ok` when the command was actually written to the port,
  `{:error, :no_backend}` / `{:error, :no_port}` otherwise. Writing to a dead
  port fails loudly and triggers the pair restart.
* **Do:** if you matched on transmit's return, match `:ok` now.

### Inline keyboards in received messages

`vector<vector<T>>` fields (e.g. `ReplyMarkupInlineKeyboard.rows`) are now
recursively deserialized: inner elements arrive as `%Sexy.TDL.Object.*` structs
instead of raw string-keyed maps. If you worked around this by matching raw
maps, switch to matching the structs.

## Mix tasks

### `mix sexy.tdl.setup`

No longer offers to generate types — `Sexy.TDL.Object`/`Method` are bundled
with the library. Prompts fail with a clear message instead of a crash when run
without an interactive terminal.

### `mix sexy.tdl.generate_types`

Still available for regenerating types when a new TDLib version ships — run it
**inside the sexy repository (or a fork)**. It now refuses to run in a consumer
project (the generated modules would duplicate the ones compiled in the `:sexy`
dependency and break `mix release`); `--force` overrides. Generation is atomic:
a malformed `types.json` no longer destroys the previous files. Doc text from
`types.json` is escaped, closing a compile-time code-execution hole.

## Compatibility

Declared Elixir support (`~> 1.14`) is now real: the accidental use of an
Elixir 1.17+ guard was removed, so the library compiles on 1.14–1.16 again.
