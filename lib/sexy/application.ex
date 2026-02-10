defmodule Sexy.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Sexy.Visor
    ]

    opts = [strategy: :one_for_one, name: Sexy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
