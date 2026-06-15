defmodule BB.TUI.Panels.VisualizationTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.Visualization
  alias BB.TUI.Viz.RobotScene
  alias ExRatatui.Layout.Rect
  alias ExRatatui.ThreeD.Scene
  alias ExRatatui.Widgets.Viewport3D

  defp robot do
    %BB.Robot{
      root_link: :base,
      links: %{
        base: %BB.Robot.Link{
          name: :base,
          child_joints: [],
          visual: %{
            origin: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}},
            geometry: {:box, %{x: 0.1, y: 0.1, z: 0.1}},
            material: nil
          }
        }
      },
      joints: %{}
    }
  end

  test "renders a Viewport3D with the robot scene and the viz camera" do
    state = %BB.TUI.State{
      robot_struct: robot(),
      joints: %BB.TUI.State.Joints{entries: %{}},
      viz: %BB.TUI.State.Viz{camera: RobotScene.default_camera()}
    }

    [{widget, rect}] = Visualization.render_panes(state, %Rect{x: 0, y: 0, width: 80, height: 24})

    assert %Viewport3D{scene: %Scene{} = scene, camera: cam, render_mode: :auto} = widget
    assert length(scene.objects) == 1
    assert cam == RobotScene.default_camera()
    assert %Rect{} = rect
  end

  test "uses the render mode from viz state" do
    state = %BB.TUI.State{
      robot_struct: robot(),
      joints: %BB.TUI.State.Joints{entries: %{}},
      viz: %BB.TUI.State.Viz{camera: RobotScene.default_camera(), render_mode: :ascii}
    }

    [{%Viewport3D{render_mode: mode}, _rect}] =
      Visualization.render_panes(state, %Rect{x: 0, y: 0, width: 80, height: 24})

    assert mode == :ascii
  end

  test "falls back to the default camera when viz camera is nil" do
    state = %BB.TUI.State{
      robot_struct: robot(),
      joints: %BB.TUI.State.Joints{entries: %{}},
      viz: %BB.TUI.State.Viz{camera: nil}
    }

    [{%Viewport3D{camera: cam}, _rect}] =
      Visualization.render_panes(state, %Rect{x: 0, y: 0, width: 80, height: 24})

    assert cam == RobotScene.default_camera()
  end
end
