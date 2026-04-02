# `Sexy.TDL`
[🔗](https://github.com/Puremag1c/Sexy/blob/v0.9.8/lib/tdl.ex#L1)

TDLib integration for Elixir — manage userbot sessions via a `tdlib_json_cli` binary.

## Setup

1. Install `tdlib_json_cli` (or build from source)
2. Configure the binary path:

       # config/config.exs
       config :sexy,
         tdlib_binary: "/usr/local/bin/tdlib_json_cli",
         tdlib_data_root: "/tmp/tdlib_data"

   Or run the interactive wizard: `mix sexy.tdl.setup`

3. Add to your supervision tree:

       children = [Sexy.TDL]

## Opening sessions

    config = %{Sexy.TDL.default_config() |
      api_id: "12345",
      api_hash: "abc123",
      database_directory: "/tmp/tdlib_data/my_account"
    }

    {:ok, _pid} = Sexy.TDL.open("my_account", config, app_pid: self())

## Receiving events

All TDLib events are sent as messages to the `app_pid` process:

    def handle_info({:recv, %Sexy.TDL.Object.UpdateNewMessage{} = msg}, state) do
      # Handle new message
      {:noreply, state}
    end

    def handle_info({:recv, _other}, state), do: {:noreply, state}

    def handle_info({:system_event, :port_exited, status}, state) do
      Logger.error("TDLib port exited: #{status}")
      {:noreply, state}
    end

## Sending commands

    # Using auto-generated Method structs
    Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.GetMe{})

    Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.SendMessage{
      chat_id: 123456,
      input_message_content: %Sexy.TDL.Object.InputMessageText{
        text: %Sexy.TDL.Object.FormattedText{text: "Hello!"}
      }
    })

    # Or using plain maps
    Sexy.TDL.transmit("my_account", %{"@type" => "getMe"})

## Supervision tree

    Sexy.TDL (Supervisor)
      ├── Registry (ETS session storage)
      ├── Workers (Elixir Registry for client worker discovery)
      └── AccountVisor (DynamicSupervisor)
            └── Riser per session (one_for_all)
                  ├── Backend (Port to tdlib_json_cli)
                  ├── Handler (JSON → Elixir structs)
                  └── ...your extra children

## Worker discovery

Client workers register themselves via `Sexy.TDL.Registry.register_worker/2`
(backed by Elixir `Registry`). Workers auto-unregister when they die.

    # In worker init:
    Sexy.TDL.Registry.register_worker(session_name, :sorter)

    # Lookup:
    Sexy.TDL.Registry.get_worker(session_name, :sorter)

    # List all workers for a session:
    Sexy.TDL.Registry.list_workers(session_name)

## Auto-generated types

Sexy ships **2558 structs** generated from TDLib API documentation:

  * `Sexy.TDL.Method.*` — 786 API methods
  * `Sexy.TDL.Object.*` — 1772 response/event types

Regenerate for a different TDLib version:

    mix sexy.tdl.generate_types /path/to/types.json

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `close`

```elixir
@spec close(String.t()) :: :ok | {:error, :not_found}
```

Close the session and stop all its processes.

# `default_config`

```elixir
@spec default_config() :: struct()
```

Default TDLib configuration. Set :api_id and :api_hash before use.

# `open`

```elixir
@spec open(String.t(), struct(), keyword()) :: {:ok, pid()} | {:error, term()}
```

Open a new TDLib session.

Options:
  - `:app_pid` — process receiving events (required)
  - `:proxy` — enable proxychains (default: false)
  - `:encryption_key` — database encryption key (default: "")
  - `:children` — extra child specs for the Riser supervisor

# `start_link`

# `transmit`

```elixir
@spec transmit(String.t(), map() | String.t()) :: term()
```

Send a TDLib command over the session. Accepts maps or pre-encoded JSON strings.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
