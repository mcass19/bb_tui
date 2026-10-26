defmodule BB.TUI.Panels.CommandsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Commands

  alias BB.TUI.Panels.Commands
  alias BB.TUI.State
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
      assert text(widget.block.title) == "  2  Commands "
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

      assert text(widget.block.title) == "  2  Commands (2) "

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

    test "a command this dashboard started shows Running before it is listed" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      state = Fixtures.sample_state(%{commands: commands, executing_command: :home})
      widget = Commands.render(state, false)

      assert Enum.map(widget.items, &text/1) == ["home  \u{23F3} Running"]
    end

    test "a command entry without a name is never shown as running" do
      state =
        Fixtures.sample_state(%{commands: [%{allowed_states: [:idle]}], runtime_state: :idle})

      widget = Commands.render(state, false)

      assert [row] = Enum.map(widget.items, &text/1)
      assert row =~ "Ready"
    end

    test "a command running elsewhere shows Running with its execution count" do
      commands = [%{name: :home, allowed_states: [:idle]}, %{name: :log, allowed_states: [:idle]}]
      now = DateTime.utc_now()

      running = [
        %{name: :home, execution_id: make_ref(), started_at: now},
        %{name: :home, execution_id: make_ref(), started_at: now}
      ]

      state =
        Fixtures.sample_state(%{commands: commands, runtime_state: :idle})
        |> State.put_running_commands(running)

      widget = Commands.render(state, false)

      assert Enum.map(widget.items, &text/1) == [
               "home  \u{23F3} Running \u{00D7}2",
               "log  \u{25CF} Ready"
             ]

      %Line{spans: [_, _, badge]} = hd(widget.items)
      assert badge.style.fg == :yellow
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

    test "shows an exception error result through its message" do
      error = %BB.Error.State.CommandPending{actuator: :elbow, command: Position, timeout_ms: 250}
      state = Fixtures.sample_state(%{commands: [], command_result: {:error, error}})
      widget = Commands.render(state, false)

      assert Enum.any?(widget.items, &(text(&1) =~ "✖ Actuator :elbow has not answered"))
      refute Enum.any?(widget.items, &(text(&1) =~ "%BB.Error"))
    end

    test "uses arrow symbol as highlight" do
      state = Fixtures.sample_state()
      widget = Commands.render(state, false)

      assert widget.highlight_symbol == "\u{25B6} "
    end

    test "does not inline arg fields in edit mode (the popup owns that)" do
      cmd = %{
        name: :move,
        allowed_states: [:idle],
        arguments: [%{name: :angle, type: "float", default: 1.5, required: true, doc: nil}]
      }

      state =
        Fixtures.sample_state(%{
          commands: [cmd],
          command_selected: 0,
          command_edit_mode: true,
          command_focused_arg: 0
        })

      widget = Commands.render(state, true)
      texts = Enum.map(widget.items, &text/1)
      refute Enum.any?(texts, &String.contains?(&1, "angle:"))
      refute Enum.any?(texts, &String.contains?(&1, "[Tab] next"))
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
