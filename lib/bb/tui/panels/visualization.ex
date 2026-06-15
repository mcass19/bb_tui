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
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, Viewport3D}

  @spec render_panes(State.t(), struct()) :: [{struct(), struct()}]
  def render_panes(%State{robot_struct: robot} = state, area) do
    scene = RobotScene.build(robot, positions(state))
    mode = State.viz_render_mode(state)

    # `render_mode` (cycled with `m`) is `:auto` by default — crisp pixel graphics
    # (Kitty/Sixel) on capable terminals, braille fallback elsewhere. The active
    # mode is shown dim in the title so it is clear what is on screen.
    widget = %Viewport3D{
      scene: scene,
      camera: State.viz_camera(state),
      render_mode: mode,
      pipeline: :rasterize,
      block: %Block{
        title: title_line(mode),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(true)
      }
    }

    [{widget, area}]
  end

  defp title_line(mode) do
    %Line{
      spans: [
        %Span{content: "Robot "},
        %Span{content: "[#{mode}]", style: %Style{fg: Theme.dim_text()}}
      ]
    }
  end

  defp positions(%State{joints: %{entries: entries}}) do
    Map.new(entries, fn {name, %{position: pos}} -> {name, pos} end)
  end
end
