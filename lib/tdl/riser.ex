defmodule Sexy.TDL.Riser do
  @moduledoc """
  Per-session supervisor for a TDLib account.

  Supervises `Sexy.TDL.Backend` and `Sexy.TDL.Handler` with a `:one_for_all` strategy
  (if one crashes, both restart). Additional child specs can be injected via the
  `:children` option in `Sexy.TDL.open/3`.

  Started automatically by `Sexy.TDL` via `DynamicSupervisor` — not called directly.
  """
  use Supervisor

  alias Sexy.TDL.{Backend, Handler, Registry}

  def start_link({session_name, proxy, extra_children}) do
    Supervisor.start_link(__MODULE__, {session_name, proxy, extra_children})
  end

  @impl true
  def init({session_name, proxy, extra_children}) do
    Registry.update(session_name, supervisor_pid: self())

    children =
      [
        {Backend, {session_name, proxy}},
        {Handler, session_name}
      ] ++ extra_children

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 30)
  end
end
