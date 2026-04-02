# `Sexy.TDL.Registry`
[🔗](https://github.com/Puremag1c/Sexy/blob/v0.9.8/lib/tdl/registry.ex#L1)

ETS-based session registry for TDLib sessions.

Stores per-session metadata (pids, config, encryption keys) in a public ETS table
with read concurrency enabled. Write operations go through the GenServer to
ensure serialization.

Started automatically by `Sexy.TDL` — not called directly.

## Stored fields

  * `:name` — session identifier
  * `:config` — TDLib configuration (`SetTdlibParameters` struct)
  * `:supervisor_pid` — Riser supervisor pid
  * `:backend_pid` — Backend GenServer pid
  * `:handler_pid` — Handler GenServer pid
  * `:app_pid` — target process for events
  * `:encryption_key` — database encryption key

## Worker discovery

Client workers (Sorter, Updater, Sender, etc.) register via `Sexy.TDL.Workers`
(Elixir `Registry`). Use `register_worker/2`, `get_worker/2`, `list_workers/1`
for discovery. Workers auto-unregister when they die — no stale PIDs.

# `t`

```elixir
@type t() :: %Sexy.TDL.Registry{
  app_pid: term(),
  backend_pid: term(),
  config: term(),
  encryption_key: term(),
  handler_pid: term(),
  name: term(),
  supervisor_pid: term()
}
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `drop`

```elixir
@spec drop(String.t()) :: true
```

# `get`

```elixir
@spec get(String.t()) :: t() | nil
```

# `get`

```elixir
@spec get(String.t(), atom()) :: term() | nil
```

# `get_worker`

```elixir
@spec get_worker(String.t(), atom()) :: pid() | nil
```

Look up a worker PID by session and role. Returns `nil` if not found or dead.

# `init`

# `list`

```elixir
@spec list() :: [{String.t(), t()}]
```

# `list_workers`

```elixir
@spec list_workers(String.t()) :: [{atom(), pid()}]
```

List all registered workers for a session as `[{role, pid}]`.

# `register_worker`

```elixir
@spec register_worker(String.t(), atom()) ::
  {:ok, pid()} | {:error, {:already_registered, pid()}}
```

Register the calling process as a worker for the given session.

    # In your worker's init/1:
    Sexy.TDL.Registry.register_worker(session_name, :sorter)

# `set`

```elixir
@spec set(String.t(), t()) :: true
```

# `start_link`

# `update`

```elixir
@spec update(String.t(), keyword() | map()) :: true | false
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
