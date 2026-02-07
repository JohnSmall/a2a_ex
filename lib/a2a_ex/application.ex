defmodule A2AEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: A2AEx.EventQueue.Registry},
      {DynamicSupervisor, name: A2AEx.EventQueue.Supervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: A2AEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
