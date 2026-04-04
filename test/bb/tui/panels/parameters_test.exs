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

    test "renders parameters with path, value, and edit hints" do
      params = [{[:speed], 100}, {[:controller, :kp], 0.5}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, true)

      assert length(widget.rows) == 2
      assert widget.block.title == " Parameters (2) "

      # Numeric values get [h/l] edit hint
      [_first, second] = widget.rows
      assert Enum.at(second, 1) =~ "[h/l]"
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

    test "formats float values with edit hint" do
      params = [{[:speed], 3.14159}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "3.142 [h/l]"
    end

    test "formats boolean values with toggle hint" do
      params = [{[:enabled], true}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "true [enter]"
    end

    test "formats atom values without edit hint" do
      params = [{[:mode], :fast}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == ":fast"
    end

    test "formats integer values with edit hint" do
      params = [{[:count], 42}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 1) == "42 [h/l]"
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

    test "focused panel shows selected row" do
      params = [{[:a], 1}, {[:b], 2}]
      state = Fixtures.sample_state(%{parameters: params, param_selected: 0})
      widget = Parameters.render(state, true)
      assert widget.selected == 0
      assert widget.highlight_symbol == "\u{25B6} "
    end

    test "unfocused panel does not show selection" do
      params = [{[:a], 1}, {[:b], 2}]
      state = Fixtures.sample_state(%{parameters: params, param_selected: 0})
      widget = Parameters.render(state, false)
      assert widget.selected == nil
    end

    test "empty parameters does not set selection" do
      state = Fixtures.sample_state(%{parameters: [], param_selected: 0})
      widget = Parameters.render(state, true)
      assert widget.selected == nil
    end
  end

  describe "edit_hint/1" do
    test "returns [h/l] for numbers" do
      assert Parameters.edit_hint(42) == " [h/l]"
      assert Parameters.edit_hint(3.14) == " [h/l]"
    end

    test "returns [enter] for booleans" do
      assert Parameters.edit_hint(true) == " [enter]"
      assert Parameters.edit_hint(false) == " [enter]"
    end

    test "returns empty for non-editable types" do
      assert Parameters.edit_hint(:atom) == ""
      assert Parameters.edit_hint("string") == ""
      assert Parameters.edit_hint(%{}) == ""
    end
  end
end
