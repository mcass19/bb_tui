defmodule BB.TUI.Panels.ParametersTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Parameters

  alias BB.TUI.Panels.Parameters
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Table

  describe "render/2" do
    test "renders empty state with placeholder row" do
      state = Fixtures.sample_state(%{parameters: []})
      widget = Parameters.render(state, false)

      assert %Table{} = widget
      assert widget.header == ["Parameter", "Value"]
      assert widget.rows == [["No parameters defined", ""]]
      assert widget.block.title == " Parameters "
    end

    test "renders parameters with path and value" do
      params = [{[:speed], 100}, {[:controller, :kp], 0.5}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, true)

      assert length(widget.rows) == 2
      assert widget.block.title == " Parameters (2) "
    end

    test "sorts parameters by path" do
      params = [{[:z_param], 1}, {[:a_param], 2}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [first, second] = widget.rows
      assert hd(first) == "a_param"
      assert hd(second) == "z_param"
    end

    test "formats nested paths with dots" do
      params = [{[:controller, :pid, :kp], 0.5}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert hd(row) == "controller.pid.kp"
    end

    test "formats float values" do
      params = [{[:speed], 3.14159}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "3.142"
    end

    test "formats boolean values" do
      params = [{[:enabled], true}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "true"
    end

    test "formats atom values" do
      params = [{[:mode], :fast}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == ":fast"
    end

    test "formats integer values" do
      params = [{[:count], 42}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "42"
    end

    test "formats complex values" do
      params = [{[:config], %{a: 1, b: 2}}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) =~ "%{"
    end

    test "focused panel gets cyan border" do
      state = Fixtures.sample_state()
      widget = Parameters.render(state, true)
      assert widget.block.border_style.fg == :cyan
    end
  end
end
