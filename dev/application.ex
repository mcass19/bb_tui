defmodule Dev.Application do
  @moduledoc """
  Dev supervision tree for local `mix`/`iex` sessions.

  Boots the simulated `Dev.TestRobot` under `BB.Supervisor` plus an
  `ExRatatui.Distributed.Listener` pre-wired to `BB.TUI.App`.

  Having the listener up at boot means any connected BEAM node can
  attach with `ExRatatui.Distributed.attach/2` without further setup
  on the robot side — just start `iex --sname robot -S mix` on this
  app and attach from a second node. See the README's
  "Testing distribution locally" section for the two-terminal recipe.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{
        id: BB.Supervisor,
        start: {BB.Supervisor, :start_link, [Dev.TestRobot, [simulation: :kinematic]]}
      },
      {ExRatatui.Distributed.Listener, mod: BB.TUI.App, app_opts: [robot: Dev.TestRobot]}
    ]

    opts = [strategy: :one_for_one, name: Dev.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
