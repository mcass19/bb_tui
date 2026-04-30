defmodule BB.TUI.Panels.JointsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Joints

  alias BB.TUI.Panels.Joints
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Table

  # Cells in the joints table can be a plain string, a `%Span{}`, or a
  # `%Line{}` (rich text). Flatten them all back to a plain string for
  # substring assertions; tests that care about color check the spans
  # directly.
  defp cell_text(%Line{spans: spans}), do: Enum.map_join(spans, "", & &1.content)
  defp cell_text(%Span{content: c}), do: c
  defp cell_text(s) when is_binary(s), do: s

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
      assert cell_text(hd(first_row)) == "elbow"
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
      assert cell_text(Enum.at(row, 2)) == "28.6°"
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
      assert cell_text(Enum.at(row, 2)) == "30.0 mm"
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
      bar = cell_text(Enum.at(row, 3))

      assert bar =~ "\u{25CF}"
      assert bar =~ "\u{2500}"
      assert bar =~ "-90"
      assert bar =~ "90"
    end

    test "position-bar marker carries the proximity color" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.57, upper: 1.57}},
          position: 0.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      [%Line{spans: spans} | _] = widget.rows |> hd() |> Enum.filter(&match?(%Line{}, &1))
      marker = Enum.find(spans, &(&1.content == "\u{25CF}"))
      assert marker.style.fg == :green
    end

    test "shows SIM tag (yellow) for simulated joints" do
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
      assert cell_text(hd(row)) =~ "wrist"
      assert cell_text(hd(row)) =~ "SIM"
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
      assert cell_text(hd(row)) == "wrist"
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
      assert cell_text(Enum.at(row, 2)) == "N/A"
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
      assert cell_text(Enum.at(row, 2)) == "0.0°"
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
      assert cell_text(Enum.at(row, 2)) == "0.0 mm !!"
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
      assert cell_text(Enum.at(row, 2)) =~ " !"
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
      assert cell_text(Enum.at(row, 2)) =~ " !!"
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
      bar = cell_text(Enum.at(row, 3))
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
      bar = cell_text(Enum.at(row, 3))
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
      refute cell_text(Enum.at(row, 2)) =~ "!"
      assert cell_text(Enum.at(row, 3)) =~ "\u{25CF}"
    end

    test "warning marker carries yellow color" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.4
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      %Line{spans: spans} = Enum.at(row, 3)
      marker = Enum.find(spans, &(&1.content == "\u{25C6}"))
      assert marker.style.fg == :yellow
    end

    test "danger marker carries red color" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.5708, upper: 1.5708}},
          position: 1.55
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      %Line{spans: spans} = Enum.at(row, 3)
      marker = Enum.find(spans, &(&1.content == "\u{25C9}"))
      assert marker.style.fg == :red
    end

    test "joints with empty/zero-width limits skip the bar" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute, limits: %{lower: 1.0, upper: 1.0}},
          position: 1.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 3) == ""
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
