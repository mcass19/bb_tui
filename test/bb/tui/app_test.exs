defmodule BB.TUI.AppTest do
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.App
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Layout.Rect

  setup :set_mimic_global

  describe "mount/1" do
    test "initializes state from robot module" do
      Fixtures.stub_bb_modules()

      assert {:ok, state} = App.mount(robot: BB.TUI.TestRobot)

      assert state.robot == BB.TUI.TestRobot
      assert state.safety_state == :disarmed
      assert state.runtime_state == :disarmed
      assert map_size(state.joints) == 2
      assert state.joints.shoulder.position == 0.0
      assert state.joints.elbow.position == 45.0
      assert state.events == []
      assert state.active_panel == :safety
      assert state.events_paused == false
      assert state.command_selected == 0
    end

    test "raises on invalid robot module" do
      assert_raise ArgumentError, ~r/is not a valid BB robot module/, fn ->
        App.mount(robot: __MODULE__)
      end
    end

    test "loads commands from BB.Dsl.Info" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      Fixtures.stub_bb_modules()
      Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> commands end)

      assert {:ok, state} = App.mount(robot: BB.TUI.TestRobot)
      assert state.commands == commands
    end

    test "handles BB.Dsl.Info.commands raising" do
      Fixtures.stub_bb_modules()
      Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> raise "boom" end)

      assert {:ok, state} = App.mount(robot: BB.TUI.TestRobot)
      assert state.commands == []
    end
  end

  describe "render/2" do
    test "returns a list of widget-rect pairs" do
      state = Fixtures.sample_state()
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      # safety, commands, joints, events, parameters, status_bar = 6
      assert is_list(widgets)
      assert length(widgets) == 6

      Enum.each(widgets, fn {widget, rect} ->
        assert is_struct(widget)
        assert %Rect{} = rect
      end)
    end

    test "includes help popup when show_help is true" do
      state = Fixtures.sample_state(%{show_help: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 7
    end

    test "includes force disarm popup when confirm_force_disarm is true" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 7
    end

    test "popup is rendered last (on top)" do
      state = Fixtures.sample_state(%{show_help: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      {last_widget, _rect} = List.last(widgets)
      assert %ExRatatui.Widgets.Popup{} = last_widget
    end
  end

  describe "handle_event/2" do
    test "q key stops the app" do
      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "q", kind: "press"}

      assert {:stop, ^state} = App.handle_event(event, state)
    end

    test "tab key cycles active panel" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      event = %ExRatatui.Event.Key{code: "tab", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.active_panel == :commands
    end

    test "? key toggles help" do
      state = Fixtures.sample_state(%{show_help: false})
      event = %ExRatatui.Event.Key{code: "?", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.show_help
    end

    test "any key dismisses help overlay" do
      state = Fixtures.sample_state(%{show_help: true})
      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      refute new_state.show_help
    end

    test "a key calls BB.Safety.arm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :arm, fn _robot -> :ok end)

      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "a", kind: "press"}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end

    test "d key calls BB.Safety.disarm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :disarm, fn _robot -> :ok end)

      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "d", kind: "press"}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end

    test "f key shows force disarm popup when in error state" do
      state = Fixtures.sample_state(%{safety_state: :error})
      event = %ExRatatui.Event.Key{code: "f", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.confirm_force_disarm
    end

    test "f key does nothing when not in error state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      event = %ExRatatui.Event.Key{code: "f", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      refute new_state.confirm_force_disarm
    end

    test "y key confirms force disarm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :force_disarm, fn _robot -> :ok end)

      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "y", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      refute new_state.confirm_force_disarm
    end

    test "n key dismisses force disarm popup" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "n", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      refute new_state.confirm_force_disarm
    end

    test "other keys are ignored during force disarm popup" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end

    # Events panel keys
    test "j/down scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "down arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "up arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "k/up scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "p key toggles events pause" do
      state = Fixtures.sample_state(%{active_panel: :events, events_paused: false})
      event = %ExRatatui.Event.Key{code: "p", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.events_paused
    end

    test "c key clears events" do
      events = [{DateTime.utc_now(), [:test], %{}}]
      state = Fixtures.sample_state(%{active_panel: :events, events: events})
      event = %ExRatatui.Event.Key{code: "c", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.events == []
    end

    # Commands panel keys
    test "j/down selects next command" do
      commands = [%{name: :a}, %{name: :b}]

      state =
        Fixtures.sample_state(%{active_panel: :commands, commands: commands, command_selected: 0})

      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.command_selected == 1
    end

    test "k/up selects prev command" do
      commands = [%{name: :a}, %{name: :b}]

      state =
        Fixtures.sample_state(%{active_panel: :commands, commands: commands, command_selected: 1})

      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.command_selected == 0
    end

    test "enter executes selected command" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        pid = spawn(fn -> :ok end)
        {:ok, pid}
      end)

      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.executing_command != nil
    end

    test "enter does nothing for blocked command" do
      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :executing
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.executing_command == nil
    end

    test "enter does nothing with no commands" do
      state = Fixtures.sample_state(%{active_panel: :commands, commands: []})
      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end

    test "enter does nothing when already executing" do
      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle,
          executing_command: self()
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end

    test "enter sends error result when execute fails" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        {:error, :not_allowed}
      end)

      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.executing_command != nil

      # Wait for the spawn to send the error message
      assert_receive {:command_result, {:error, :not_allowed}}, 1000
    end

    test "enter sends timeout result when command process hangs" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        pid = spawn(fn -> Process.sleep(:infinity) end)
        {:ok, pid}
      end)

      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, _new_state} = App.handle_event(event, state)

      # With command_timeout set to 100ms in test config, this should fire quickly
      assert_receive {:command_result, {:error, :timeout}}, 1000
    end

    test "enter sends error result when command process exits abnormally" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        pid = spawn(fn -> exit(:boom) end)
        {:ok, pid}
      end)

      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, _new_state} = App.handle_event(event, state)

      # Wait for the spawn to send the error result
      assert_receive {:command_result, {:error, :boom}}, 1000
    end

    # Joints panel keys
    test "j/down scrolls joints" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :joints, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "k/up scrolls joints" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :joints, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.handle_event(event, state)
      assert new_state.scroll_offset == 1
    end

    test "ignores unknown events" do
      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Mouse{kind: "down", button: "left", x: 0, y: 0, modifiers: []}

      assert {:noreply, ^state} = App.handle_event(event, state)
    end
  end

  describe "handle_info/2" do
    test "state_machine message updates safety and appends event" do
      Fixtures.stub_bb_modules(safety_state: :armed, runtime_state: :idle)

      state = Fixtures.sample_state()
      msg = %{payload: %{to: :armed}}

      assert {:noreply, new_state} = App.handle_info({:bb, [:state_machine], msg}, state)
      assert new_state.safety_state == :armed
      assert new_state.runtime_state == :idle
      assert length(new_state.events) == 1
    end

    test "sensor message updates positions and appends event" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      payload = %{names: [:shoulder, :elbow], positions: [10.0, 20.0]}
      msg = %{payload: payload}

      assert {:noreply, new_state} =
               App.handle_info({:bb, [:sensor, :joints], msg}, state)

      assert new_state.joints.shoulder.position == 10.0
      assert new_state.joints.elbow.position == 20.0
      assert length(new_state.events) == 1
    end

    test "sensor message with non-standard payload still appends event" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      msg = %{payload: %{something_else: true}}

      assert {:noreply, new_state} =
               App.handle_info({:bb, [:sensor, :other], msg}, state)

      assert new_state.joints == state.joints
      assert length(new_state.events) == 1
    end

    test "param message updates parameters and appends event" do
      Fixtures.stub_bb_modules()
      params = [{[:speed], 100}]
      Mimic.stub(BB.Parameter, :list, fn _robot, _opts -> params end)

      state = Fixtures.sample_state()
      msg = %{payload: %{path: [:speed], value: 100}}

      assert {:noreply, new_state} = App.handle_info({:bb, [:param, :speed], msg}, state)
      assert new_state.parameters == params
      assert length(new_state.events) == 1
    end

    test "catch-all bb message only appends event" do
      state = Fixtures.sample_state()
      msg = %{payload: :something}

      assert {:noreply, new_state} = App.handle_info({:bb, [:unknown], msg}, state)
      assert length(new_state.events) == 1
    end

    test "command_result message sets result" do
      state = Fixtures.sample_state(%{executing_command: self()})

      assert {:noreply, new_state} =
               App.handle_info({:command_result, {:ok, :completed}}, state)

      assert new_state.command_result == {:ok, :completed}
      assert new_state.executing_command == nil
    end

    test "non-bb messages are ignored" do
      state = Fixtures.sample_state()

      assert {:noreply, ^state} = App.handle_info(:random_message, state)
    end
  end

  describe "terminate/2" do
    test "returns :ok" do
      assert :ok = App.terminate(:normal, Fixtures.sample_state())
    end
  end
end
