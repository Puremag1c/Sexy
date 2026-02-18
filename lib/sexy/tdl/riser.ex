defmodule Sexy.TDL.Riser do
  @moduledoc false
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
