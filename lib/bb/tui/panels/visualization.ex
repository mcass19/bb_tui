defmodule BB.TUI.Panels.Visualization do
  @moduledoc """
  Visualization tab — renders the live robot in 3D via `ExRatatui.Widgets.Viewport3D`.

  The scene is rebuilt from the current joint positions each render, so the robot
  animates as sensor data arrives. Pure function: state + main `Rect` ->
  `[{widget, rect}]`.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias BB.TUI.Viz.RobotScene
  alias ExRatatui.Widgets.{Block, Viewport3D}

  @spec render_panes(State.t(), struct()) :: [{struct(), struct()}]
  def render_panes(%State{robot_struct: robot} = state, area) do
    scene = RobotScene.build(robot, positions(state))

    # `render_mode` (cycled with `m`) is a cell-blit mode — `:braille` is the
    # supersampled, anti-aliased default. For crisp pixel graphics on Kitty/Sixel
    # terminals (Ghostty/WezTerm), see the "Future: true pixel graphics" note on
    # `BB.TUI.State.Viz`.
    widget = %Viewport3D{
      scene: scene,
      camera: State.viz_camera(state),
      render_mode: State.viz_render_mode(state),
      pipeline: :rasterize,
      block: %Block{
        title: "Robot",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(true)
      }
    }

    [{widget, area}]
  end

  defp positions(%State{joints: %{entries: entries}}) do
    Map.new(entries, fn {name, %{position: pos}} -> {name, pos} end)
  end
end
