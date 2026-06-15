defmodule BB.TUI.Viz.RobotSceneTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BB.TUI.Viz.RobotScene
  alias ExRatatui.ThreeD.{Object, Scene}

  # Minimal 2-link robot: base cylinder -> waist (revolute, +Z) -> arm box.
  defp robot do
    %BB.Robot{
      root_link: :base,
      links: %{
        base: %BB.Robot.Link{
          name: :base,
          child_joints: [:waist],
          visual: %{
            origin: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}},
            geometry: {:cylinder, %{radius: 0.04, height: 0.072}},
            material: %{name: :grey, color: %{red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0}}
          }
        },
        arm: %BB.Robot.Link{
          name: :arm,
          child_joints: [],
          visual: %{
            origin: {{0.0, 0.0, 0.1}, {0.0, 0.0, 0.0}},
            geometry: {:box, %{x: 0.035, y: 0.035, z: 0.2}},
            material: %{name: :silver, color: %{red: 0.7, green: 0.7, blue: 0.75, alpha: 1.0}}
          }
        }
      },
      joints: %{
        waist: %BB.Robot.Joint{
          name: :waist,
          type: :revolute,
          parent_link: :base,
          child_link: :arm,
          origin: %{position: {0.0, 0.0, 0.072}, orientation: {0.0, 0.0, 0.0}},
          axis: {0.0, 0.0, 1.0},
          limits: %{lower: -3.14, upper: 3.14}
        }
      }
    }
  end

  test "build produces one object per visual link with mapped meshes" do
    scene = RobotScene.build(robot(), %{waist: 0.0})
    assert %Scene{} = scene
    kinds = scene.objects |> Enum.map(& &1.mesh.kind) |> Enum.sort()
    # cylinder is a :custom mesh; box is a :cube (sorted: :cube < :custom)
    assert kinds == [:cube, :custom]
    assert length(scene.lights) >= 2
  end

  test "material colors convert from 0..1 floats to 0..255 ints" do
    scene = RobotScene.build(robot(), %{waist: 0.0})
    arm = Enum.find(scene.objects, &(&1.mesh.kind == :cube))
    # round(0.7*255)=179, round(0.75*255)=191
    assert arm.material.color == {179, 179, 191}
  end

  test "box geometry maps to a cube scaled by its dimensions" do
    scene = RobotScene.build(robot(), %{waist: 0.0})
    arm = Enum.find(scene.objects, &(&1.mesh.kind == :cube))
    {sx, sy, sz} = arm.transform.scale
    assert_in_delta sx, 0.035, 1.0e-9
    assert_in_delta sy, 0.035, 1.0e-9
    assert_in_delta sz, 0.2, 1.0e-9
  end

  test "rotating the waist moves the arm's world position" do
    s0 = RobotScene.build(robot(), %{waist: 0.0})
    s90 = RobotScene.build(robot(), %{waist: :math.pi() / 2})
    arm0 = Enum.find(s0.objects, &(&1.mesh.kind == :cube)).transform.position
    arm90 = Enum.find(s90.objects, &(&1.mesh.kind == :cube)).transform.position
    refute arm0 == arm90
  end

  test "unknown geometry falls back to a cube and logs a warning" do
    r = robot()
    r = put_in(r.links[:arm].visual.geometry, {:mesh, %{file: "x.stl"}})

    log =
      capture_log(fn ->
        scene = RobotScene.build(r, %{waist: 0.0})
        assert Enum.any?(scene.objects, &(&1.mesh.kind == :cube))
      end)

    assert log =~ "unsupported geometry"
  end

  test "missing material yields a default-colored object" do
    r = robot()
    r = put_in(r.links[:arm].visual.material, nil)
    scene = RobotScene.build(r, %{waist: 0.0})
    arm = Enum.find(scene.objects, &(&1.mesh.kind == :cube))
    assert %Object{} = arm
    assert match?({_, _, _}, arm.material.color)
  end

  test "sphere geometry, prismatic motion, fixed/nil-axis joints, and nil visual are handled" do
    r = %BB.Robot{
      root_link: :a,
      links: %{
        a: %BB.Robot.Link{
          name: :a,
          child_joints: [:slide],
          visual: %{
            origin: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}},
            geometry: {:sphere, %{radius: 0.05}},
            material: nil
          }
        },
        b: %BB.Robot.Link{name: :b, child_joints: [:fixed_j], visual: nil},
        c: %BB.Robot.Link{
          name: :c,
          child_joints: [],
          visual: %{
            origin: nil,
            geometry: {:box, %{x: 0.1, y: 0.1, z: 0.1}},
            material: nil
          }
        }
      },
      joints: %{
        slide: %BB.Robot.Joint{
          name: :slide,
          type: :prismatic,
          parent_link: :a,
          child_link: :b,
          origin: %{position: {0.0, 0.0, 0.0}, orientation: {0.0, 0.0, 0.0}},
          axis: nil,
          limits: nil
        },
        fixed_j: %BB.Robot.Joint{
          name: :fixed_j,
          type: :fixed,
          parent_link: :b,
          child_link: :c,
          origin: nil,
          axis: nil,
          limits: nil
        }
      }
    }

    scene = RobotScene.build(r, %{slide: 0.2})
    sphere = Enum.find(scene.objects, &(&1.mesh.kind == :sphere))
    {sx, _, _} = sphere.transform.scale
    # radius 0.05 -> scale 2r = 0.1
    assert_in_delta sx, 0.1, 1.0e-9
    # base sphere link + fixed-chain box link both rendered
    assert length(scene.objects) == 2
  end

  test "default_camera returns a camera" do
    assert %ExRatatui.ThreeD.Camera{} = RobotScene.default_camera()
  end
end
