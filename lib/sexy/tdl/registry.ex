defmodule Sexy.TDL.Registry do
  @moduledoc false
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

  @name __MODULE__

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def init(:ok) do
    table = :ets.new(@name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, table}
  end

  # Public API

  def set(session_name, %__MODULE__{} = struct) do
    GenServer.call(@name, {:set, session_name, struct})
  end

  def get(session_name) do
    case :ets.lookup(@name, session_name) do
      [{_key, value}] -> value
      [] -> nil
    end
  end

  def get(session_name, field) do
    case get(session_name) do
      nil -> nil
      struct -> Map.get(struct, field)
    end
  end

  def update(session_name, change) do
    GenServer.call(@name, {:update, session_name, change})
  end

  def drop(session_name) do
    GenServer.call(@name, {:drop, session_name})
  end

  def list do
    :ets.tab2list(@name)
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
