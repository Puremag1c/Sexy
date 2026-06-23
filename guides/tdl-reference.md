# TDLib Reference

Deeper reference for `Sexy.TDL` — the data layout, supervision model, how to inject
your own workers, the complete event model, and proxy setup. For a first run, start
with the [TDLib Quick Start](tdl-quickstart.md).

## Configuration

Two application-level keys (set in `config/config.exs` or via `mix sexy.tdl.setup`):

```elixir
config :sexy,
  tdlib_binary: "/usr/local/bin/tdlib_json_cli",  # required — raises at session start if missing
  tdlib_data_root: "/tmp/tdlib_data"              # root for per-session files (proxy.conf)
```

Per-session paths come from the `SetTdlibParameters` config you pass to `open/3`
(`Sexy.TDL.default_config/0`):

| Field | Purpose |
|---|---|
| `database_directory` | TDLib database for this account |
| `files_directory` | downloaded media for this account |
| `api_id` / `api_hash` | credentials from [my.telegram.org](https://my.telegram.org) |

### Per-account folder layout

Keep each account self-contained under `tdlib_data_root/<session>/`:

```
<tdlib_data_root>/
  my_account/
    db/            # database_directory
    files/         # files_directory
    proxy.conf     # required only when proxy: true (see Proxy)
```

The `database_directory`/`files_directory` values are whatever you put in the config,
but `proxy.conf` **must** live at exactly `<tdlib_data_root>/<session>/proxy.conf` —
that path is hardcoded by the backend.

## Supervision model

`Sexy.TDL.open/3` starts a per-session supervisor (`Sexy.TDL.Riser`) under the
`Sexy.TDL.AccountVisor` DynamicSupervisor:

```
Sexy.TDL.Riser (one_for_all, max_restarts: 5, max_seconds: 30)
  ├── Sexy.TDL.Backend   (Port to tdlib_json_cli)
  ├── Sexy.TDL.Handler   (JSON → structs, forwards to app_pid)
  └── ...your extra children (see below)
```

**`:one_for_all` is deliberate and has a consequence:** if any child crashes, the whole
session restarts together — Backend, Handler, and every worker you injected. A flaky
app worker will therefore restart the TDLib port too. Keep crash-prone logic out of the
Riser's children, or isolate it under its own supervisor passed as one child.

`close/1` stops the Riser (all children) and drops the session from the registry.

## Injecting your own workers (`children:` option)

Pass extra child specs to run inside the session's supervisor:

```elixir
Sexy.TDL.open("my_account", config,
  app_pid: self(),
  children: [
    MyApp.Sorter,
    {MyApp.Updater, account: "my_account"}
  ]
)
```

- **Start order is sequential, in list position.** Backend starts first (opens the port),
  Handler second (registers as the event sink), then your children — so by the time your
  workers' `init/1` runs, the session is already up.
- All of them share the `:one_for_all` strategy above.

## Worker discovery

Children injected into one session find each other by role via the `Sexy.TDL.Workers`
registry (Elixir `Registry`, unique keys). No PIDs to thread around; entries auto-clear
when a worker dies.

```elixir
# in a worker's init/1:
Sexy.TDL.Registry.register_worker("my_account", :sorter)

# elsewhere:
Sexy.TDL.Registry.get_worker("my_account", :sorter)   # pid | nil
Sexy.TDL.Registry.list_workers("my_account")          # [{role, pid}]
```

## Event model

Everything reaches your `app_pid` as a plain message. Handle these three shapes:

```elixir
def handle_info({:recv, struct}, state), do: ...          # a TDLib object
def handle_info({:proxy_event, text}, state), do: ...      # a proxychains line
def handle_info({:system_event, type, details}, state), do: ...
```

### `{:recv, struct}`

A deserialized TDLib object — a `Sexy.TDL.Object.*` struct, with nested `@type` objects
recursively converted (e.g. `%Sexy.TDL.Object.UpdateNewMessage{message: %...Message{}}`).
Unknown `@type`s that have no matching struct are logged and dropped.

### `{:proxy_event, text}`

Output from `proxychains4` when the session was opened with `proxy: true` — connection
chain lines, and `"error: no valid proxy found in config"` when the chain is unusable.

### `{:system_event, type, details}`

Lifecycle signals from the backend:

| `type` | `details` | Meaning |
|---|---|---|
| `:port_failed` | error term | The port could not be opened at startup. |
| `:port_exited` | exit status | The `tdlib_json_cli` process exited. |
| `:proxy_conf_missing` | path | `proxy: true` but no `proxy.conf` at the expected path. |

## Sending commands

`Sexy.TDL.transmit/2` accepts a `Sexy.TDL.Method.*` struct or a plain map; both are
JSON-encoded and written to the port. Returns `{:error, :no_backend}` if the session
isn't running.

```elixir
Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.GetMe{})
Sexy.TDL.transmit("my_account", %{"@type" => "getMe"})
```

## Proxy

```elixir
Sexy.TDL.open("my_account", config, app_pid: self(), proxy: true)
```

When `proxy: true`, the binary is wrapped in `proxychains4 -f <conf> <binary>`. You must
create the config **before** opening the session, at:

```
<tdlib_data_root>/<session>/proxy.conf
```

`proxy.conf` is standard proxychains4 format, e.g.:

```
[ProxyList]
http  proxy.example.com 8080 user pass
```

Only HTTP proxies are exercised here; SOCKS is up to your proxychains setup. If the file
is missing you get `{:system_event, :proxy_conf_missing, path}` and proxy errors arrive
as `{:proxy_event, "error: ..."}`.

## Type generation

`Sexy` ships structs for every TDLib method and object. Regenerate from a newer
`types.json`:

```bash
mix sexy.tdl.generate_types /path/to/types.json   # writes lib/tdl/{object,method}.ex
```

`mix sexy.tdl.setup` runs an interactive wizard that writes the config and offers to
generate types in one step.
