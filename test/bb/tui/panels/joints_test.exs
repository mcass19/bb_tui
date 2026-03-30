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
      assert widget.header == ["Joint", "Position", "Min", "Max"]
      assert length(widget.rows) == 2
    end

    test "rows are sorted by joint name" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, false)

      [first_row | _] = widget.rows
      assert hd(first_row) == "elbow"
    end

    test "formats positions with two decimals" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, false)

      elbow_row = Enum.find(widget.rows, &(hd(&1) == "elbow"))
      assert Enum.at(elbow_row, 1) == "45.00"
    end

    test "shows limits from joint data" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, false)

      shoulder_row = Enum.find(widget.rows, &(hd(&1) == "shoulder"))
      assert Enum.at(shoulder_row, 2) == "-90.00"
      assert Enum.at(shoulder_row, 3) == "90.00"
    end

    test "focused panel gets highlighted border" do
      state = Fixtures.sample_state()
      widget = Joints.render(state, true)
      assert widget.block.border_style.fg == :cyan
    end

    test "handles joints without limits" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute},
          position: 10.0
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 2) == "-"
      assert Enum.at(row, 3) == "-"
    end

    test "formats integer positions" do
      joints = %{
        wrist: %{
          joint: %{name: :wrist, type: :revolute, limit: %{lower: 0, upper: 100}},
          position: 42
        }
      }

      state = Fixtures.sample_state(%{joints: joints})
      widget = Joints.render(state, false)

      row = hd(widget.rows)
      assert Enum.at(row, 1) == "42"
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
      assert Enum.at(row, 1) == "-"
    end
  end
end
