defmodule BB.TUI.Panels.CommandsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Commands

  alias BB.TUI.Panels.Commands
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.List, as: WidgetList

  describe "render/2" do
    test "renders empty command list" do
      state = Fixtures.sample_state(%{commands: []})
      widget = Commands.render(state, false)

      assert %WidgetList{} = widget
      assert widget.items == []
      assert widget.block.title == " Commands "
    end

    test "renders commands with ready status" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, runtime_state: :idle})
      widget = Commands.render(state, true)

      assert hd(widget.items) =~ "home"
      assert hd(widget.items) =~ "Ready"
    end

    test "renders commands with blocked status" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, runtime_state: :executing})
      widget = Commands.render(state, false)

      assert hd(widget.items) =~ "home"
      assert hd(widget.items) =~ "Blocked"
    end

    test "shows command count in title" do
      commands = [%{name: :a}, %{name: :b}]
      state = Fixtures.sample_state(%{commands: commands})
      widget = Commands.render(state, false)

      assert widget.block.title == " Commands (2) "
    end

    test "uses command_selected as selected index" do
      commands = [%{name: :a}, %{name: :b}]
      state = Fixtures.sample_state(%{commands: commands, command_selected: 1})
      widget = Commands.render(state, false)

      assert widget.selected == 1
    end

    test "shows executing indicator" do
      state = Fixtures.sample_state(%{commands: [], executing_command: self()})
      widget = Commands.render(state, false)

      assert Enum.any?(widget.items, &(&1 =~ "Executing"))
    end

    test "shows success result" do
      state = Fixtures.sample_state(%{commands: [], command_result: {:ok, :done}})
      widget = Commands.render(state, false)

      assert Enum.any?(widget.items, &(&1 =~ ":done"))
    end

    test "shows error result" do
      state = Fixtures.sample_state(%{commands: [], command_result: {:error, :timeout}})
      widget = Commands.render(state, false)

      assert Enum.any?(widget.items, &(&1 =~ ":timeout"))
    end

    test "uses arrow symbol as highlight" do
      state = Fixtures.sample_state()
      widget = Commands.render(state, false)

      assert widget.highlight_symbol == "\u{25B6} "
    end
  end

  describe "command_ready?/2" do
    test "returns true when state is in allowed_states" do
      assert Commands.command_ready?(%{allowed_states: [:idle, :armed]}, :idle)
    end

    test "returns false when state is not in allowed_states" do
      refute Commands.command_ready?(%{allowed_states: [:idle]}, :executing)
    end

    test "returns true when command has no allowed_states" do
      assert Commands.command_ready?(%{name: :test}, :anything)
    end
  end
end
