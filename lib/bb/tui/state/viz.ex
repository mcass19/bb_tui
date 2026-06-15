defmodule BB.TUI.State.Viz do
  @moduledoc """
  Visualization-tab state: the orbit camera for the 3D robot view.

  `camera` is `nil` until first used; `BB.TUI.State.viz_camera/1` falls back to
  `BB.TUI.Viz.RobotScene.default_camera/0` so a fresh state still renders.
  """

  alias ExRatatui.ThreeD.Camera

  defstruct camera: nil

  @type t :: %__MODULE__{camera: Camera.t() | nil}
end
