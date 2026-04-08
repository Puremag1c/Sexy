defmodule Sexy.TDL.Registry do
  @moduledoc """
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
  """
  use GenServer

  defstruct [
    :name,
    :config,
    :supervisor_pid,
    :backend_pid,
    :handler_pid,
    :app_pid,
    :encryption_key
  ]

  @type t :: %__MODULE__{}

  @name __MODULE__

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def init(:ok) do
    table = :ets.new(@name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, table}
  end

  # Public API

  @spec set(String.t(), t()) :: true
  def set(session_name, %__MODULE__{} = struct) do
    GenServer.call(@name, {:set, session_name, struct})
  end

  @spec get(String.t()) :: t() | nil
  def get(session_name) do
    case :ets.lookup(@name, session_name) do
      [{_key, value}] -> value
      [] -> nil
    end
  end

  @spec get(String.t(), atom()) :: term() | nil
  def get(session_name, field) do
    case get(session_name) do
      nil -> nil
      struct -> Map.get(struct, field)
    end
  end

  @spec update(String.t(), keyword() | map()) :: true | false
  def update(session_name, change) do
    GenServer.call(@name, {:update, session_name, change})
  end

  @spec drop(String.t()) :: true
  def drop(session_name) do
    GenServer.call(@name, {:drop, session_name})
  end

  @spec list() :: [{String.t(), t()}]
  def list do
    :ets.tab2list(@name)
  end

  # Worker discovery (delegates to Sexy.TDL.Workers registry)

  @doc """
  Register the calling process as a worker for the given session.

      # In your worker's init/1:
      Sexy.TDL.Registry.register_worker(session_name, :sorter)
  """
  @spec register_worker(String.t(), atom()) ::
          {:ok, pid()} | {:error, {:already_registered, pid()}}
  def register_worker(session_name, role) do
    Elixir.Registry.register(Sexy.TDL.Workers, {session_name, role}, nil)
  end

  @doc "Look up a worker PID by session and role. Returns `nil` if not found or dead."
  @spec get_worker(String.t(), atom()) :: pid() | nil
  def get_worker(session_name, role) do
    case Elixir.Registry.lookup(Sexy.TDL.Workers, {session_name, role}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "List all registered workers for a session as `[{role, pid}]`."
  @spec list_workers(String.t()) :: [{atom(), pid()}]
  def list_workers(session_name) do
    Elixir.Registry.select(Sexy.TDL.Workers, [
      {{{session_name, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  # Server callbacks

  def handle_call({:set, key, value}, _from, table) do
    reply = :ets.insert(table, {key, value})
    {:reply, reply, table}
  end

  def handle_call({:update, session_name, change}, _from, table) do
    reply =
      case :ets.lookup(table, session_name) do
        [{_key, struct}] ->
          new_struct = struct(struct, change)
          :ets.insert(table, {session_name, new_struct})

        [] ->
          false
      end

    {:reply, reply, table}
  end

  def handle_call({:drop, key}, _from, table) do
    reply = :ets.delete(table, key)
    {:reply, reply, table}
  end
end
