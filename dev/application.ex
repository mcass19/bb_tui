defmodule Dev.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{
        id: BB.Supervisor,
        start: {BB.Supervisor, :start_link, [Dev.TestRobot, [simulation: :kinematic]]}
      }
    ]

    opts = [strategy: :one_for_one, name: Dev.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
