defmodule BB.TUI.Panels.CommandsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Commands

  alias BB.TUI.Panels.Commands
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.List, as: WidgetList

  defp text(%Line{spans: spans}), do: Enum.map_join(spans, "", & &1.content)
  defp text(s) when is_binary(s), do: s

  describe "render/2" do
    test "renders empty command list" do
      state = Fixtures.sample_state(%{commands: []})
      widget = Commands.render(state, false)

      assert %WidgetList{} = widget
      assert widget.items == []
      assert text(widget.block.title) == " Commands "
    end

    test "renders commands with Ready badge" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, runtime_state: :idle})
      widget = Commands.render(state, true)

      first = text(hd(widget.items))
      assert first =~ "home"
      assert first =~ "Ready"
    end

    test "Ready badge renders green-bold" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, runtime_state: :idle})
      widget = Commands.render(state, true)

      %Line{spans: spans} = hd(widget.items)
      ready = Enum.find(spans, &(&1.content =~ "Ready"))
      assert ready.style.fg == :green
      assert :bold in ready.style.modifiers
    end

    test "renders commands with Blocked badge" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, runtime_state: :executing})
      widget = Commands.render(state, false)

      first = text(hd(widget.items))
      assert first =~ "home"
      assert first =~ "Blocked"
    end

    test "shows command count in title with bold-cyan number" do
      commands = [%{name: :a}, %{name: :b}]
      state = Fixtures.sample_state(%{commands: commands})
      widget = Commands.render(state, false)

      assert text(widget.block.title) == " Commands (2) "

      %Line{spans: title_spans} = widget.block.title
      count = Enum.find(title_spans, &(&1.content == "2"))
      assert count.style.fg == :cyan
      assert :bold in count.style.modifiers
    end

    test "uses command_selected as selected index" do
      commands = [%{name: :a}, %{name: :b}]
      state = Fixtures.sample_state(%{commands: commands, command_selected: 1})
      widget = Commands.render(state, false)

      assert widget.selected == 1
    end

    test "shows executing indicator" do
      state = Fixtures.sample_state(%{commands: [], executing_command: :running})
      widget = Commands.render(state, false)

      assert Enum.any?(widget.items, &(text(&1) =~ "Executing"))
    end

    test "shows success result (green)" do
      state = Fixtures.sample_state(%{commands: [], command_result: {:ok, :done}})
      widget = Commands.render(state, false)

      result =
        widget.items
        |> Enum.find(&(text(&1) =~ ":done"))

      assert result
      %Line{spans: [span]} = result
      assert span.style.fg == :green
    end

    test "shows error result (red)" do
      state = Fixtures.sample_state(%{commands: [], command_result: {:error, :timeout}})
      widget = Commands.render(state, false)

      result =
        widget.items
        |> Enum.find(&(text(&1) =~ ":timeout"))

      assert result
      %Line{spans: [span]} = result
      assert span.style.fg == :red
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
