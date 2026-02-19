defmodule Sexy.TDL do
  @moduledoc """
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
        └── AccountVisor (DynamicSupervisor)
              └── Riser per session (one_for_all)
                    ├── Backend (Port to tdlib_json_cli)
                    ├── Handler (JSON → Elixir structs)
                    └── ...your extra children

  ## Auto-generated types

  Sexy ships **2558 structs** generated from TDLib API documentation:

    * `Sexy.TDL.Method.*` — 786 API methods
    * `Sexy.TDL.Object.*` — 1772 response/event types

  Regenerate for a different TDLib version:

      mix sexy.tdl.generate_types /path/to/types.json
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
