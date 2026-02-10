defmodule Sexy.Visor do
  use Supervisor

  def start_link(init_arg \\ :ok) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Sexy.Poller
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 100, max_seconds: 2)
  end
end
