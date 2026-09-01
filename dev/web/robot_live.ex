defmodule Dev.Web.RobotLive do
  @moduledoc """
  The dev robot's dashboard in the browser — the demo consumer of
  `BB.TUI.Live`. Every browser tab gets its own isolated dashboard
  session over the shared `Dev.TestRobot`, exactly like concurrent SSH
  clients.
  """

  use BB.TUI.Live, robot: Dev.TestRobot
end
