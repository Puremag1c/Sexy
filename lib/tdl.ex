defmodule Sexy.TDL do
  @moduledoc """
  TDLib integration for Elixir — manage userbot sessions via a `tdlib_json_cli` binary.

  ## Setup

  1. Configure the session data directory:

         # config/config.exs
         config :sexy,
           tdlib_data_root: "/tmp/tdlib_data"

     The `tdlib_json_cli` binary is downloaded automatically for your platform
     on first start (pinned + checksum-verified via `priv/tdlib/manifest.json`;
     see `Sexy.TDL.Binary`). To use your own build instead, set
     `tdlib_binary: "/path/to/tdlib_json_cli"` — that path is then used as-is.
     Prefetch in CI/Dockerfile with `mix sexy.tdl.install`.
     Or run the interactive wizard: `mix sexy.tdl.setup`

  2. Add to your supervision tree:

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
        Logger.error("TDLib port exited: \#{status}")
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

  Sexy targets **TDLib 1.8.66** and ships **3380 structs** generated from its
  schema (`priv/tdlib/manifest.json` pins the exact version and commit):

    * `Sexy.TDL.Method.*` — 1010 API methods
    * `Sexy.TDL.Object.*` — 2370 response/event types

  Regenerate for a different TDLib version:

      mix sexy.tdl.generate_types /path/to/td_api.tl
  """

  use Supervisor

  alias Sexy.TDL.{Registry, Riser}
  alias Sexy.Utils

  @doc "Default TDLib configuration. Set :api_id and :api_hash before use."
  @spec default_config() :: struct()
  def default_config do
    %Sexy.TDL.Method.SetTdlibParameters{
      database_encryption_key: nil,
      use_test_dc: false,
      database_directory: "/tmp/tdlib",
      files_directory: "",
      use_file_database: true,
      use_chat_info_database: true,
      use_message_database: true,
      use_secret_chats: false,
      api_id: "0",
      api_hash: "0",
      system_language_code: "en",
      device_model: "Unknown",
      system_version: "Unknown",
      application_version: "Unknown"
    }
  end

  @doc """
  Open a new TDLib session.

  Options:
    - `:app_pid` — process receiving events (required)
    - `:proxy` — path to a proxychains4 config file; the binary is then
      wrapped in `proxychains4 -f <path>` (default: `false` — no proxy)
    - `:encryption_key` — database encryption key (default: "")
    - `:children` — extra child specs for the Riser supervisor

  Returns `{:error, {:already_started, pid}}` if a session with this name is
  already running, and `{:error, reason}` if the tdlib port can't be opened
  (wrong `:tdlib_binary` path, etc.).
  """
  @spec open(String.t(), struct(), keyword()) ::
          {:ok, pid()} | {:error, {:already_started, pid()} | term()}
  def open(session_name, config, opts \\ []) do
    case Registry.get(session_name) do
      %{supervisor_pid: pid} when is_pid(pid) ->
        # ponytail: check-then-act — two concurrent opens of the same name can
        # still race; true uniqueness needs registration-at-start.
        if Process.alive?(pid),
          do: {:error, {:already_started, pid}},
          else: do_open(session_name, config, opts)

      _ ->
        do_open(session_name, config, opts)
    end
  end

  defp do_open(session_name, config, opts) do
    app_pid = Keyword.fetch!(opts, :app_pid)
    proxy = Keyword.get(opts, :proxy, false)
    encryption_key = Keyword.get(opts, :encryption_key, "")
    extra_children = Keyword.get(opts, :children, [])

    state = %Registry{
      config: config,
      app_pid: app_pid,
      encryption_key: encryption_key
    }

    Registry.set(session_name, state)

    case DynamicSupervisor.start_child(
           Sexy.TDL.AccountVisor,
           {Riser, {session_name, proxy, extra_children}}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Registry.drop(session_name)
        {:error, reason}
    end
  end

  @doc "Close the session and stop all its processes."
  @spec close(String.t()) :: :ok | {:error, :not_found}
  def close(session_name) do
    case Registry.get(session_name) do
      %{supervisor_pid: pid} when is_pid(pid) ->
        # terminate_child, not Supervisor.stop: a stopped child would be
        # resurrected by the DynamicSupervisor; terminate_child removes it.
        result = DynamicSupervisor.terminate_child(Sexy.TDL.AccountVisor, pid)
        Registry.drop(session_name)
        result

      _ ->
        Registry.drop(session_name)
        {:error, :not_found}
    end
  end

  @doc """
  Send a TDLib command over the session. Accepts maps or pre-encoded JSON strings.

  Returns `:ok` when the command was written to the tdlib port,
  `{:error, :no_backend}` when the session has no live backend, or
  `{:error, :no_port}` when the port just died (the session is restarting).
  """
  @spec transmit(String.t(), map() | String.t()) :: :ok | {:error, :no_backend | :no_port}
  def transmit(session_name, msg) when is_map(msg) do
    json =
      msg
      |> Utils.strip()
      |> Jason.encode!()

    transmit(session_name, json)
  end

  def transmit(session_name, json) when is_binary(json) do
    case Registry.get(session_name, :backend_pid) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(pid, {:transmit, json})
        catch
          # The registry entry can briefly hold a dead pid during a restart —
          # same condition as a missing pid, same answer.
          :exit, {:noproc, _} -> {:error, :no_backend}
        end

      _ ->
        {:error, :no_backend}
    end
  end

  # Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Fail at application start, not at the first open() hours later: a
    # missing binary must surface at deploy time. No-op (and offline) when
    # the binary is configured or already cached.
    case Sexy.TDL.Binary.ensure_installed() do
      :ok -> :ok
      {:error, message} -> raise "Sexy.TDL: #{message}"
    end

    children = [
      Registry,
      {Elixir.Registry, keys: :unique, name: Sexy.TDL.Workers},
      {DynamicSupervisor, name: Sexy.TDL.AccountVisor, strategy: :one_for_one}
    ]

    # rest_for_one: everything below depends on the Registry's ETS table.
    # If the Registry crashes, sessions restart into a consistent empty state
    # instead of running as zombies against an empty table.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
