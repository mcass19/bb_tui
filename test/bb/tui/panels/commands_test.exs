defmodule BB.TUI.Panels.CommandsTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.Commands
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.List, as: WidgetList

  describe "render/2" do
    test "renders empty command list" do
      state = Fixtures.sample_state(%{commands: []})
      widget = Commands.render(state, false)

      assert %WidgetList{} = widget
      assert widget.items == []
    end

    test "renders commands with names" do
      commands = [
        %{name: :home},
        %{name: :calibrate},
        %{name: :wave}
      ]

      state = Fixtures.sample_state(%{commands: commands})
      widget = Commands.render(state, true)

      assert widget.items == ["home", "calibrate", "wave"]
    end

    test "has Commands title" do
      state = Fixtures.sample_state()
      widget = Commands.render(state, false)

      assert widget.block.title == " Commands "
    end

    test "uses arrow symbol as highlight" do
      state = Fixtures.sample_state()
      widget = Commands.render(state, false)

      assert widget.highlight_symbol == "\u{25B6} "
    end
  end
end
