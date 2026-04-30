defmodule BB.TUI.AppTest do
  use ExUnit.Case, async: false
  use Mimic
  doctest BB.TUI

  alias BB.TUI.App
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Layout.Rect

  setup :set_mimic_global

  describe "mount/1" do
    test "initializes state from robot module" do
      Fixtures.stub_bb_modules()

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)

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
      assert state.executing_command == nil
    end

    test "raises on invalid robot module" do
      assert_raise ArgumentError, ~r/is not a valid BB robot module/, fn ->
        App.init(robot: __MODULE__)
      end
    end

    test "loads commands from BB.Dsl.Info" do
      commands = [%{name: :home, allowed_states: [:idle]}]
      Fixtures.stub_bb_modules()
      Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> commands end)

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)
      assert state.commands == commands
    end

    test "handles BB.Dsl.Info.commands raising" do
      Fixtures.stub_bb_modules()
      Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> raise "boom" end)

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)
      assert state.commands == []
    end

    test "extracts parameter values from BB.Parameter.list metadata" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Parameter, :list, fn _robot, _opts ->
        [
          {[:controller, :kp], %{value: 1.0, type: :float, default: 1.0, doc: "gain"}},
          {[:grip, :force], %{value: 50, type: :integer, default: 50, doc: "force"}}
        ]
      end)

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)

      assert state.parameters == [
               {[:controller, :kp], 1.0},
               {[:grip, :force], 50}
             ]
    end
  end

  describe "render/2" do
    test "returns a list of widget-rect pairs" do
      state = Fixtures.sample_state()
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      # title_bar, safety, commands, joints, events, parameters, status_bar = 7
      # No scrollbar pane when events are empty.
      assert is_list(widgets)
      assert length(widgets) == 7

      Enum.each(widgets, fn {widget, rect} ->
        assert is_struct(widget)
        assert %Rect{} = rect
      end)
    end

    test "renders a Scrollbar pane alongside the events list when events exist" do
      events = [
        {~U[2026-03-30 12:00:00Z], [:state_machine], %{payload: %{from: :disarmed, to: :armed}}}
      ]

      state = Fixtures.sample_state(%{events: events, scroll_offset: 0})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      # 7 base panels + 1 scrollbar overlay = 8
      assert length(widgets) == 8
      assert Enum.any?(widgets, fn {w, _} -> match?(%ExRatatui.Widgets.Scrollbar{}, w) end)
    end

    test "includes help popup when show_help is true" do
      state = Fixtures.sample_state(%{show_help: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 8
    end

    test "includes force disarm popup when confirm_force_disarm is true" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 8
    end

    test "popup is rendered last (on top)" do
      state = Fixtures.sample_state(%{show_help: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      {last_widget, _rect} = List.last(widgets)
      assert %ExRatatui.Widgets.Popup{} = last_widget
    end

    test "includes event detail popup when show_event_detail is true" do
      events = [
        {~U[2026-03-30 12:00:00Z], [:state_machine], %{payload: %{from: :disarmed, to: :armed}}}
      ]

      state =
        Fixtures.sample_state(%{
          show_event_detail: true,
          events: events,
          scroll_offset: 0
        })

      frame = %ExRatatui.Frame{width: 120, height: 40}
      widgets = App.render(state, frame)

      # 7 base panels + 1 scrollbar overlay + 1 popup = 9
      assert length(widgets) == 9
      {last_widget, _rect} = List.last(widgets)
      assert %ExRatatui.Widgets.Popup{} = last_widget
    end

    test "skips the event detail popup when show_event_detail is set but no event is selected" do
      state =
        Fixtures.sample_state(%{
          show_event_detail: true,
          events: [],
          scroll_offset: 0
        })

      frame = %ExRatatui.Frame{width: 120, height: 40}
      widgets = App.render(state, frame)

      # No popup added — just the 7 base panels.
      assert length(widgets) == 7
    end
  end

  describe "handle_event/2" do
    setup do
      Mimic.stub(BB, :publish, fn _robot, _path, _msg -> :ok end)
      :ok
    end

    test "q key stops the app" do
      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "q", kind: "press"}

      assert {:stop, ^state} = App.update({:event, event}, state)
    end

    test "tab key cycles active panel" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      event = %ExRatatui.Event.Key{code: "tab", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.active_panel == :commands
    end

    test "? key toggles help" do
      state = Fixtures.sample_state(%{show_help: false})
      event = %ExRatatui.Event.Key{code: "?", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.show_help
    end

    test "j/down scrolls help overlay down" do
      state = Fixtures.sample_state(%{show_help: true, help_scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.help_scroll_offset == 1
      assert new_state.show_help
    end

    test "k/up scrolls help overlay up" do
      state = Fixtures.sample_state(%{show_help: true, help_scroll_offset: 3})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.help_scroll_offset == 2
      assert new_state.show_help
    end

    test "any key dismisses help overlay" do
      state = Fixtures.sample_state(%{show_help: true})
      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.show_help
    end

    test "any key dismisses event detail popup" do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{payload: :data}}]

      state =
        Fixtures.sample_state(%{show_event_detail: true, events: events, scroll_offset: 0})

      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.show_event_detail
    end

    test "a key calls BB.Safety.arm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :arm, fn _robot -> :ok end)

      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "a", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "d key calls BB.Safety.disarm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :disarm, fn _robot -> :ok end)

      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Key{code: "d", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "f key shows force disarm popup when in error state" do
      state = Fixtures.sample_state(%{safety_state: :error})
      event = %ExRatatui.Event.Key{code: "f", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.confirm_force_disarm
    end

    test "f key does nothing when not in error state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      event = %ExRatatui.Event.Key{code: "f", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.confirm_force_disarm
    end

    test "y key confirms force disarm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :force_disarm, fn _robot -> :ok end)

      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "y", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.confirm_force_disarm
    end

    test "n key dismisses force disarm popup" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "n", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.confirm_force_disarm
    end

    test "other keys are ignored during force disarm popup" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    # Events panel keys
    test "j/down scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.scroll_offset == 1
    end

    test "down arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.scroll_offset == 1
    end

    test "up arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.scroll_offset == 1
    end

    test "k/up scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.scroll_offset == 1
    end

    test "p key toggles events pause" do
      state = Fixtures.sample_state(%{active_panel: :events, events_paused: false})
      event = %ExRatatui.Event.Key{code: "p", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events_paused
    end

    test "c key clears events" do
      events = [{DateTime.utc_now(), [:test], %{}}]
      state = Fixtures.sample_state(%{active_panel: :events, events: events})
      event = %ExRatatui.Event.Key{code: "c", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events == []
    end

    test "enter key opens event detail when events panel is active" do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{payload: :data}}]

      state =
        Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.show_event_detail
    end

    test "enter key does nothing when events panel is empty" do
      state = Fixtures.sample_state(%{active_panel: :events, events: []})
      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute Map.get(new_state, :show_event_detail)
    end

    # Commands panel keys
    test "j/down selects next command" do
      commands = [%{name: :a}, %{name: :b}]

      state =
        Fixtures.sample_state(%{active_panel: :commands, commands: commands, command_selected: 0})

      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.command_selected == 1
    end

    test "k/up selects prev command" do
      commands = [%{name: :a}, %{name: :b}]

      state =
        Fixtures.sample_state(%{active_panel: :commands, commands: commands, command_selected: 1})

      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.command_selected == 0
    end

    test "enter on a Ready command returns Command.batch with async + send_after" do
      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state, opts} = App.update({:event, event}, state)
      assert new_state.executing_command == :running
      assert new_state.command_result == nil

      # The reducer hands the runtime two commands wrapped in a batch: the
      # async work (which monitors the spawned command pid and reports
      # `{:command_result, _}`), and a `send_after` for the timeout.
      assert [%ExRatatui.Command{kind: :batch}] = opts[:commands]
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

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.executing_command == nil
    end

    test "enter does nothing with no commands" do
      state = Fixtures.sample_state(%{active_panel: :commands, commands: []})
      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "enter does nothing when already executing" do
      commands = [%{name: :home, allowed_states: [:idle]}]

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: commands,
          command_selected: 0,
          runtime_state: :idle,
          executing_command: :running
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    # Result/timeout/error semantics are exercised by the integration suite,
    # which boots a real ExRatatui.Server so that Command.async + send_after
    # actually drive the {:info, _} mailbox round-trip. See
    # `test/bb/tui/integration_test.exs` ("Command result flow").

    # Joints panel keys — navigation
    test "j/down selects next joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joint_selected == 1
    end

    test "down arrow selects next joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 0})
      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joint_selected == 1
    end

    test "k/up selects previous joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 1})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joint_selected == 0
    end

    test "up arrow selects previous joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 1})
      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joint_selected == 0
    end

    # Joints panel keys — position control (simulated joints, no actuator)
    test "l/right increases simulated joint position when armed" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position > 0.0
    end

    test "h/left decreases simulated joint position when armed" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "h", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position < 0.0
    end

    test "right arrow adjusts simulated joint position" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "right", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position > 0.0
    end

    test "L key increases position by 10x step" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      small_event = %ExRatatui.Event.Key{code: "l", kind: "press"}
      big_event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      {:noreply, small_state} = App.update({:event, small_event}, state)
      {:noreply, big_state} = App.update({:event, big_event}, state)

      small_delta = small_state.joints.shoulder.position
      big_delta = big_state.joints.shoulder.position

      assert_in_delta big_delta, small_delta * 10, 1.0e-10
    end

    test "H key decreases position by 10x step" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      small_event = %ExRatatui.Event.Key{code: "h", kind: "press"}
      big_event = %ExRatatui.Event.Key{code: "H", kind: "press"}

      {:noreply, small_state} = App.update({:event, small_event}, state)
      {:noreply, big_state} = App.update({:event, big_event}, state)

      small_delta = abs(small_state.joints.shoulder.position)
      big_delta = abs(big_state.joints.shoulder.position)

      assert_in_delta big_delta, small_delta * 10, 1.0e-10
    end

    test "position is clamped to joint limits" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.99
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      # Big step that would exceed upper limit
      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position == 1.0
    end

    test "joint control does nothing when not armed" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :disarmed
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position == 0.0
    end

    test "joint control does nothing with nil position" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: nil
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.shoulder.position == nil
    end

    test "joint control does nothing with empty joints" do
      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: %{},
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    # Joints panel keys — real actuator joints
    test "l key calls BB.Actuator.set_position! for joint with actuator" do
      Fixtures.stub_bb_modules(safety_state: :armed)

      Mimic.expect(BB.Actuator, :set_position!, fn _robot, :shoulder_motor, pos ->
        assert pos > 0.0
        :ok
      end)

      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      robot_struct =
        Map.put(Fixtures.sample_robot_struct(), :actuators, %{
          shoulder_motor: %{joint: :shoulder}
        })

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed,
          robot_struct: robot_struct
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      # Position NOT updated locally for real actuators — waits for sensor feedback
      assert new_state.joints.shoulder.position == 0.0
    end

    test "l key publishes simulated state when robot has actuators map but no match for joint" do
      Fixtures.stub_bb_modules(safety_state: :armed)

      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0
        }
      }

      # Robot has actuators, but none of them are linked to :shoulder.
      # This exercises the `nil -> nil` branch in find_actuator_for_joint/2.
      robot_struct =
        Map.put(Fixtures.sample_robot_struct(), :actuators, %{
          gripper_motor: %{joint: :gripper}
        })

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed,
          robot_struct: robot_struct
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      # No matching actuator → simulated path → local position updated
      assert new_state.joints.shoulder.position > 0.0
    end

    # Parameters panel keys — navigation
    test "j/down selects next parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.param_selected == 1
    end

    test "down arrow selects next parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.param_selected == 1
    end

    test "k/up selects previous parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 1})

      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.param_selected == 0
    end

    test "up arrow selects previous parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 1})

      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.param_selected == 0
    end

    # Parameters panel keys — value editing
    test "l/right increases integer parameter" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 2 -> :ok end)

      params = [{[:count], 1}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "h/left decreases integer parameter" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 9 -> :ok end)

      params = [{[:count], 10}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "h", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "right arrow increases float parameter by 0.1" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 1.1, 0.001
        :ok
      end)

      params = [{[:kp], 1.0}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "right", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "left arrow decreases float parameter by 0.1" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 0.9, 0.001
        :ok
      end)

      params = [{[:kp], 1.0}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "left", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "L key increases integer parameter by 10" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 15 -> :ok end)

      params = [{[:count], 5}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "H key decreases integer parameter by 10" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], -5 -> :ok end)

      params = [{[:count], 5}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "H", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "L key increases float parameter by 1.0" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 3.5, 0.001
        :ok
      end)

      params = [{[:kp], 2.5}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "enter toggles boolean parameter" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:enabled], false -> :ok end)

      params = [{[:enabled], true}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "enter toggles boolean parameter from false to true" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:enabled], true -> :ok end)

      params = [{[:enabled], false}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "enter does nothing for non-boolean parameter" do
      params = [{[:count], 42}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "parameter adjustment does nothing for atom values" do
      params = [{[:mode], :fast}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "parameter adjustment does nothing with empty parameters" do
      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: [], param_selected: 0})

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "ignores unknown events" do
      state = Fixtures.sample_state()
      event = %ExRatatui.Event.Mouse{kind: "down", button: "left", x: 0, y: 0, modifiers: []}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end
  end

  describe "handle_info/2" do
    test "state_machine message updates safety and appends event" do
      Fixtures.stub_bb_modules(safety_state: :armed, runtime_state: :idle)

      state = Fixtures.sample_state()
      msg = %{payload: %{to: :armed}}

      assert {:noreply, new_state} = App.update({:info, {:bb, [:state_machine], msg}}, state)
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
               App.update({:info, {:bb, [:sensor, :joints], msg}}, state)

      assert new_state.joints.shoulder.position == 10.0
      assert new_state.joints.elbow.position == 20.0
      assert length(new_state.events) == 1
    end

    test "sensor message with non-standard payload still appends event" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      msg = %{payload: %{something_else: true}}

      assert {:noreply, new_state} =
               App.update({:info, {:bb, [:sensor, :other], msg}}, state)

      assert new_state.joints == state.joints
      assert length(new_state.events) == 1
    end

    test "param message updates parameters and appends event" do
      Fixtures.stub_bb_modules()
      params = [{[:speed], 100}]
      Mimic.stub(BB.Parameter, :list, fn _robot, _opts -> params end)

      state = Fixtures.sample_state()
      msg = %{payload: %{path: [:speed], value: 100}}

      assert {:noreply, new_state} = App.update({:info, {:bb, [:param, :speed], msg}}, state)
      assert new_state.parameters == params
      assert length(new_state.events) == 1
    end

    test "catch-all bb message only appends event" do
      state = Fixtures.sample_state()
      msg = %{payload: :something}

      assert {:noreply, new_state} = App.update({:info, {:bb, [:unknown], msg}}, state)
      assert length(new_state.events) == 1
    end

    test "command_result message sets result" do
      state = Fixtures.sample_state(%{executing_command: self()})

      assert {:noreply, new_state} =
               App.update({:info, {:command_result, {:ok, :completed}}}, state)

      assert new_state.command_result == {:ok, :completed}
      assert new_state.executing_command == nil
    end

    test "non-bb messages are ignored" do
      state = Fixtures.sample_state()

      assert {:noreply, ^state} = App.update({:info, :random_message}, state)
    end
  end

  describe "subscriptions/1" do
    test "no subscriptions when nothing is animating" do
      state = Fixtures.sample_state(%{safety_state: :armed, executing_command: nil})
      assert App.subscriptions(state) == []
    end

    test "throbber tick subscription while disarming" do
      state = Fixtures.sample_state(%{safety_state: :disarming})

      assert [%ExRatatui.Subscription{id: :throbber, kind: :interval, interval_ms: 100}] =
               App.subscriptions(state)
    end

    test "throbber tick subscription while a command is executing" do
      state = Fixtures.sample_state(%{safety_state: :armed, executing_command: :running})

      assert [%ExRatatui.Subscription{id: :throbber, kind: :interval, interval_ms: 100}] =
               App.subscriptions(state)
    end

    test ":throbber_tick info increments the throbber step" do
      state = Fixtures.sample_state(%{throbber_step: 7})
      assert {:noreply, next} = App.update({:info, :throbber_tick}, state)
      assert next.throbber_step == 8
    end
  end

  describe "command timeout" do
    test ":command_timeout with executing_command nil is a no-op" do
      state = Fixtures.sample_state(%{executing_command: nil})
      assert {:noreply, ^state} = App.update({:info, :command_timeout}, state)
    end

    test ":command_timeout while a command is running surfaces a timeout error" do
      state = Fixtures.sample_state(%{executing_command: :running, command_result: nil})
      assert {:noreply, next} = App.update({:info, :command_timeout}, state)
      assert next.command_result == {:error, :timeout}
      assert next.executing_command == nil
    end
  end
end
