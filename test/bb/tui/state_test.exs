defmodule BB.TUI.StateTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.State

  alias BB.TUI.State
  alias BB.TUI.Test.Fixtures

  describe "panels/0" do
    test "returns the ordered panel list" do
      assert State.panels() == [:safety, :commands, :joints, :events, :parameters]
    end
  end

  describe "cycle_panel/1" do
    test "cycles through panels in order" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      state = State.cycle_panel(state)
      assert state.active_panel == :commands

      state = State.cycle_panel(state)
      assert state.active_panel == :joints

      state = State.cycle_panel(state)
      assert state.active_panel == :events

      state = State.cycle_panel(state)
      assert state.active_panel == :parameters

      state = State.cycle_panel(state)
      assert state.active_panel == :safety
    end
  end

  describe "toggle_help/1" do
    test "toggles help overlay on and off" do
      state = Fixtures.sample_state(%{show_help: false})
      state = State.toggle_help(state)
      assert state.show_help

      state = State.toggle_help(state)
      refute state.show_help
    end
  end

  describe "show_force_disarm/1 and dismiss_force_disarm/1" do
    test "shows and dismisses force disarm popup" do
      state = Fixtures.sample_state()
      refute state.confirm_force_disarm

      state = State.show_force_disarm(state)
      assert state.confirm_force_disarm

      state = State.dismiss_force_disarm(state)
      refute state.confirm_force_disarm
    end
  end

  describe "update_safety/3" do
    test "updates safety and runtime state" do
      state = Fixtures.sample_state()
      state = State.update_safety(state, :armed, :idle)

      assert state.safety_state == :armed
      assert state.runtime_state == :idle
    end
  end

  describe "update_positions/2" do
    test "updates known joint positions" do
      state = Fixtures.sample_state()
      state = State.update_positions(state, %{shoulder: 42.0})

      assert state.joints.shoulder.position == 42.0
      assert state.joints.elbow.position == 45.0
    end

    test "ignores unknown joints" do
      state = Fixtures.sample_state()
      state = State.update_positions(state, %{wrist: 10.0})

      assert state.joints.shoulder.position == 0.0
      assert state.joints.elbow.position == 45.0
    end
  end

  describe "update_parameters/2" do
    test "replaces parameters list" do
      state = Fixtures.sample_state()
      params = [{[:speed], 100}, {[:mode], :auto}]
      state = State.update_parameters(state, params)

      assert state.parameters == params
    end
  end

  describe "append_event/3" do
    test "prepends event to list" do
      state = Fixtures.sample_state()
      state = State.append_event(state, [:state_machine], %{to: :armed})

      assert length(state.events) == 1
      {_ts, path, msg} = hd(state.events)
      assert path == [:state_machine]
      assert msg == %{to: :armed}
    end

    test "caps events at 100" do
      state = Fixtures.sample_state()

      state =
        Enum.reduce(1..110, state, fn i, acc ->
          State.append_event(acc, [:test], %{i: i})
        end)

      assert length(state.events) == 100
    end

    test "does not append when paused" do
      state = Fixtures.sample_state(%{events_paused: true})
      state = State.append_event(state, [:test], %{})

      assert state.events == []
    end
  end

  describe "scroll_down/1 and scroll_up/1" do
    test "scrolls within bounds" do
      events = Enum.map(1..10, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{events: events, scroll_offset: 0})

      state = State.scroll_down(state)
      assert state.scroll_offset == 1

      state = State.scroll_up(state)
      assert state.scroll_offset == 0
    end

    test "scroll_up does not go below 0" do
      state = Fixtures.sample_state(%{scroll_offset: 0})
      state = State.scroll_up(state)
      assert state.scroll_offset == 0
    end

    test "scroll_down does not exceed event count" do
      events = [{DateTime.utc_now(), [:test], %{}}]
      state = Fixtures.sample_state(%{events: events, scroll_offset: 0})

      state = State.scroll_down(state)
      assert state.scroll_offset == 0
    end
  end

  describe "tick_throbber/1" do
    test "increments throbber step" do
      state = Fixtures.sample_state(%{throbber_step: 5})
      state = State.tick_throbber(state)
      assert state.throbber_step == 6
    end
  end

  describe "toggle_events_pause/1" do
    test "toggles pause state" do
      state = Fixtures.sample_state(%{events_paused: false})
      state = State.toggle_events_pause(state)
      assert state.events_paused

      state = State.toggle_events_pause(state)
      refute state.events_paused
    end
  end

  describe "clear_events/1" do
    test "clears events and resets scroll" do
      events = [{DateTime.utc_now(), [:test], %{}}]
      state = Fixtures.sample_state(%{events: events, scroll_offset: 3})
      state = State.clear_events(state)

      assert state.events == []
      assert state.scroll_offset == 0
    end
  end

  describe "select_next_command/1 and select_prev_command/1" do
    test "navigates command selection" do
      commands = [%{name: :a}, %{name: :b}, %{name: :c}]
      state = Fixtures.sample_state(%{commands: commands, command_selected: 0})

      state = State.select_next_command(state)
      assert state.command_selected == 1

      state = State.select_next_command(state)
      assert state.command_selected == 2

      state = State.select_next_command(state)
      assert state.command_selected == 2

      state = State.select_prev_command(state)
      assert state.command_selected == 1

      state = State.select_prev_command(state)
      assert state.command_selected == 0

      state = State.select_prev_command(state)
      assert state.command_selected == 0
    end

    test "select_next_command handles empty commands" do
      state = Fixtures.sample_state(%{commands: [], command_selected: 0})
      state = State.select_next_command(state)
      assert state.command_selected == 0
    end
  end

  describe "set_command_result/2" do
    test "sets result and clears executing pid" do
      state = Fixtures.sample_state(%{executing_command: self()})
      state = State.set_command_result(state, {:ok, :done})

      assert state.command_result == {:ok, :done}
      assert state.executing_command == nil
    end
  end

  describe "start_command/2" do
    test "sets executing pid and clears previous result" do
      pid = self()
      state = Fixtures.sample_state(%{command_result: {:ok, :old}})
      state = State.start_command(state, pid)

      assert state.executing_command == pid
      assert state.command_result == nil
    end
  end
end
