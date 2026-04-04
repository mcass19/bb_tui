defmodule BB.TUI.Panels.JointsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Joints

  alias BB.TUI.Panels.Joints
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Table

  describe "render/2" do
    test "renders a table with joint data" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, true)

      assert %Table{} = widget
      assert widget.header == ["Joint", "Type", "Position", "Target"]
      assert length(widget.rows) == 2
    end

    test "rows are sorted by joint name" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, false)

      [first_row | _] = widget.rows
      assert hd(first_row) == "elbow"
    end

    test "formats revolute positions in degrees" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.57, upper: 1.57}},
          position: 0.5
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 1) == "rev"
      assert Enum.at(row, 2) == "28.6\u00B0"
    end

    test "formats prismatic positions in millimeters" do
      joints = %{
        gripper: %{
          joint: %{name: :gripper, type: :prismatic, limits: %{lower: 0.015, upper: 0.037}},
          position: 0.030
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 1) == "pri"
      assert Enum.at(row, 2) == "30.0 mm"
    end

    test "shows position bar for joints with limits" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.57, upper: 1.57}},
          position: 0.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      bar = Enum.at(row, 3)
      # Marker and line chars with limit labels
      assert bar =~ "\u{25CF}"
      assert bar =~ "\u{2500}"
      assert bar =~ "-90"
      assert bar =~ "90"
    end

    test "shows SIM tag for simulated joints" do
      joints = %{
        wrist: %{
          joint: %{
            name: :wrist,
            type: :revolute,
            actuators: [],
            limits: %{lower: -1.0, upper: 1.0}
          },
          position: 0.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert hd(row) == "wrist SIM"
    end

    test "does not show SIM tag for joints with actuator" do
      joints = %{
        wrist: %{
          joint: %{
            name: :wrist,
            type: :revolute,
            actuators: [:some_actuator],
            limits: %{lower: -1.0, upper: 1.0}
          },
          position: 0.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert hd(row) == "wrist"
    end

    test "handles nil position" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute},
          position: nil
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 2) == "N/A"
      assert Enum.at(row, 3) == ""
    end

    test "handles continuous joints without bar" do
      joints = %{
        wheel: %{
          joint: %{name: :wheel, type: :continuous},
          position: 3.14
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 1) == "con"
      assert Enum.at(row, 3) == ""
    end

    test "handles joints without limits" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute},
          position: 1.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 3) == ""
    end

    test "focused panel gets highlighted border" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, true)
      assert widget.block.border_style.fg == :cyan
    end

    test "focused panel shows selected row" do
      state = Fixtures.sample_state(%{joint_selected: 0})
      widget = Joints.render(state, true)
      assert widget.selected == 0
      assert widget.highlight_symbol == "\u{25B6} "
    end

    test "unfocused panel does not show selection" do
      state = Fixtures.sample_state(%{joint_selected: 0})
      widget = Joints.render(state, false)
      assert widget.selected == nil
    end

    test "selected index is passed through from state" do
      state = Fixtures.sample_state(%{joint_selected: 1})
      widget = Joints.render(state, true)
      assert widget.selected == 1
    end

    test "empty joints does not set selection" do
      state = Fixtures.sample_state(%{joints: %{}, joint_selected: 0})
      widget = Joints.render(state, true)
      assert widget.selected == nil
    end

    test "handles integer position for revolute joints" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 2) == "0.0\u00B0"
    end

    test "handles integer position for prismatic joints" do
      joints = %{
        gripper: %{
          joint: %{name: :gripper, type: :prismatic, limits: %{lower: 0, upper: 1}},
          position: 0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      # At lower limit, position gets danger suffix
      assert Enum.at(row, 2) == "0.0 mm !!"
    end
  end

  describe "limit warnings" do
    test "shows warning suffix when near limit" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.4
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      # Position text should have warning suffix
      assert Enum.at(row, 2) =~ " !"
    end

    test "shows danger suffix when at limit" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.55
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 2) =~ " !!"
    end

    test "uses warning marker in position bar when near limit" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.4
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      bar = Enum.at(row, 3)
      # Warning marker ◆ instead of normal ●
      assert bar =~ "\u{25C6}"
      refute bar =~ "\u{25CF}"
    end

    test "uses danger marker in position bar at limit" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.55
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      bar = Enum.at(row, 3)
      # Danger marker ◉ instead of normal ●
      assert bar =~ "\u{25C9}"
      refute bar =~ "\u{25CF}"
    end

    test "no warning for position well within limits" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 0.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      refute Enum.at(row, 2) =~ "!"
      assert Enum.at(row, 3) =~ "\u{25CF}"
    end
  end

  describe "format_type/1" do
    test "handles unknown joint type" do
      assert Joints.format_type(%{}) == "-"
    end

    test "handles fixed joints" do
      assert Joints.format_type(%{type: :fixed}) == "fix"
    end
  end

  describe "format_name/2" do
    test "does not show SIM when no actuator key exists" do
      assert Joints.format_name(:wrist, %{name: :wrist, type: :revolute}) == "wrist"
    end
  end
end
