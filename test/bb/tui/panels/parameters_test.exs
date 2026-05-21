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
      assert widget.header == ["Parameter", "Value", "Type"]
      assert widget.rows == [["No parameters defined", "", ""]]
      assert %ExRatatui.Text.Line{spans: [%{content: " Parameters "}]} = widget.block.title
    end

    test "renders parameters with path, value, and edit hints" do
      params = [{[:speed], 100}, {[:controller, :kp], 0.5}]
      state = Fixtures.sample_state(%{parameters: params})
      widget = Parameters.render(state, true)

      assert length(widget.rows) == 2
      assert %ExRatatui.Text.Line{spans: spans} = widget.block.title
      assert Enum.map_join(spans, "", & &1.content) == " Parameters (2) "

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

    test "Type column reflects schema metadata when present" do
      params = [{[:speed], 100}, {[:mode], :fast}]

      meta = %{
        [:speed] => %{type: {:integer, [min: 0, max: 500]}, doc: "rpm", default: 0},
        [:mode] => %{type: :atom, doc: nil, default: :fast}
      }

      state = Fixtures.sample_state(%{parameters: params, parameter_metadata: meta})
      widget = Parameters.render(state, false)

      [mode_row, speed_row] = widget.rows
      assert Enum.at(mode_row, 2) == ":atom"
      assert Enum.at(speed_row, 2) == ":integer"
    end

    test "Type column falls back to em-dash when no metadata is present" do
      params = [{[:speed], 100}]
      state = Fixtures.sample_state(%{parameters: params, parameter_metadata: %{}})
      widget = Parameters.render(state, false)

      [row] = widget.rows
      assert Enum.at(row, 2) == "—"
    end
  end

  describe "render/2 — bridge tabs" do
    test "renders 'Loading…' row when the bridge has not yet been fetched" do
      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{}
        })

      widget = Parameters.render(state, true)

      assert widget.rows == [["Loading…", "", ""]]
      assert widget.selected == nil
    end

    test "renders an Error row when list_remote returned {:error, reason}" do
      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: {:error, :nodedown}}
        })

      widget = Parameters.render(state, true)

      assert [["Error: :nodedown", "", ""]] = widget.rows
      assert widget.selected == nil
    end

    test "renders 'No remote parameters' for an empty list" do
      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: []}
        })

      widget = Parameters.render(state, true)
      assert widget.rows == [["No remote parameters", "", ""]]
      assert widget.selected == nil
    end

    test "renders one row per remote parameter sorted by id" do
      remote = [
        %{id: "ROLL_P", value: 0.05, type: :float},
        %{id: "PITCH_P", value: 0.1, type: "float"}
      ]

      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      widget = Parameters.render(state, true)

      # Atom :type renders with leading colon; string :type renders as-is.
      assert [["PITCH_P", value_p, "float"], ["ROLL_P", _, ":float"]] = widget.rows
      assert value_p =~ "0.100"
      # Numeric values pick up the [h/l] hint.
      assert value_p =~ "[h/l]"
      assert widget.selected == 0
    end

    test "atom ids and missing types render cleanly" do
      remote = [%{id: :gain, value: true}]

      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote}
        })

      widget = Parameters.render(state, false)
      [[id, value, type]] = widget.rows
      assert id == "gain"
      assert value == "true [enter]"
      assert type == "—"
    end

    test "remote rows with no :id key fall back to an empty label" do
      remote = [%{value: 1}]

      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote}
        })

      widget = Parameters.render(state, false)
      [[id | _]] = widget.rows
      assert id == ""
    end

    test "non-numeric remote values get no edit hint" do
      remote = [%{id: "MODE", value: "AUTO"}]

      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote}
        })

      widget = Parameters.render(state, false)
      [[_id, value, _type]] = widget.rows
      refute value =~ "[h/l]"
      refute value =~ "[enter]"
    end

    test "title strip lists tabs with the active one highlighted" do
      state =
        Fixtures.sample_state(%{
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: [%{id: "ROLL_P", value: 0.0, type: :float}]}
        })

      widget = Parameters.render(state, true)
      assert %ExRatatui.Text.Line{spans: spans} = widget.block.title
      rendered = Enum.map_join(spans, "", & &1.content)
      assert rendered =~ "Local"
      assert rendered =~ "mavlink"
      assert rendered =~ "[t]"
      assert rendered =~ "(1)"
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
