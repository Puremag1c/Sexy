defmodule Sexy.TDL do
  @moduledoc """
  TDLib integration for Sexy. Manages userbot sessions via TDLib binary.

  Add to your application supervisor:

      children = [
        Sexy.TDL,
        # ...
      ]

  Then open sessions:

      config = Sexy.TDL.default_config()
      config = %{config | api_id: "12345", api_hash: "abc123"}
      Sexy.TDL.open("my_session", config, app_pid: self())

  Incoming events are sent to `app_pid`:

      {:recv, struct}              # TDLib object
      {:proxy_event, text}         # proxychains output
      {:system_event, type, details} # system events (port_failed, port_exited, etc.)
  """

  use Supervisor

  alias Sexy.TDL.{Registry, Riser}
  alias Sexy.Utils

  @doc "Default TDLib configuration. Set :api_id and :api_hash before use."
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
    - `:proxy` — enable proxychains (default: false)
    - `:encryption_key` — database encryption key (default: "")
    - `:children` — extra child specs for the Riser supervisor
  """
  def open(session_name, config, opts \\ []) do
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
      {:ok, pid} -> {:ok, pid}
      {:error, reason} ->
        Registry.drop(session_name)
        {:error, reason}
    end
  end

  @doc "Close the session and stop all its processes."
  def close(session_name) do
    case Registry.get(session_name) do
      %{supervisor_pid: pid} when is_pid(pid) ->
        Supervisor.stop(pid)
        Registry.drop(session_name)
        :ok

      _ ->
        Registry.drop(session_name)
        {:error, :not_found}
    end
  end

  @doc "Send a TDLib command over the session. Accepts maps or pre-encoded JSON strings."
  def transmit(session_name, msg) when is_map(msg) do
    json =
      msg
      |> Utils.strip()
      |> Jason.encode!()

    transmit(session_name, json)
  end

  def transmit(session_name, json) when is_binary(json) do
    case Registry.get(session_name, :backend_pid) do
      pid when is_pid(pid) -> GenServer.call(pid, {:transmit, json})
      _ -> {:error, :no_backend}
    end
  end

  # Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Registry,
      {DynamicSupervisor, name: Sexy.TDL.AccountVisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
