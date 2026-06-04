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
      refute state.safety.confirm_force_disarm?

      state = State.show_force_disarm(state)
      assert state.safety.confirm_force_disarm?

      state = State.dismiss_force_disarm(state)
      refute state.safety.confirm_force_disarm?
    end
  end

  describe "update_safety/3" do
    test "updates safety and runtime state" do
      state = Fixtures.sample_state()
      state = State.update_safety(state, :armed, :idle)

      assert state.safety.state == :armed
      assert state.safety.runtime == :idle
    end
  end

  describe "update_positions/2" do
    test "updates known joint positions" do
      state = Fixtures.sample_state()
      state = State.update_positions(state, %{shoulder: 42.0})

      assert state.joints.entries.shoulder.position == 42.0
      assert state.joints.entries.elbow.position == 45.0
    end

    test "ignores unknown joints" do
      state = Fixtures.sample_state()
      state = State.update_positions(state, %{wrist: 10.0})

      assert state.joints.entries.shoulder.position == 0.0
      assert state.joints.entries.elbow.position == 45.0
    end
  end

  describe "update_parameters/2" do
    test "replaces parameters list" do
      state = Fixtures.sample_state()
      params = [{[:speed], 100}, {[:mode], :auto}]
      state = State.update_parameters(state, params)

      assert state.parameters == params
    end

    test "extracts metadata side-channel from BB.Parameter.list/2 maps" do
      state = Fixtures.sample_state()

      params = [
        {[:speed], %{value: 100, type: {:integer, [min: 0, max: 500]}, doc: "rpm", default: 0}},
        {[:mode], %{value: :fast, type: :atom}}
      ]

      state = State.update_parameters(state, params)

      assert state.parameters == [{[:speed], 100}, {[:mode], :fast}]

      assert state.parameter_metadata == %{
               [:speed] => %{type: {:integer, [min: 0, max: 500]}, doc: "rpm", default: 0},
               [:mode] => %{type: :atom, doc: nil, default: nil}
             }
    end

    test "plain-value inputs leave metadata empty for that path" do
      state = Fixtures.sample_state()
      state = State.update_parameters(state, [{[:speed], 42}])

      assert state.parameters == [{[:speed], 42}]
      assert state.parameter_metadata == %{}
    end

    test "subsequent updates discard stale metadata" do
      state = Fixtures.sample_state()

      state =
        State.update_parameters(state, [{[:speed], %{value: 1, type: :integer}}])

      assert Map.has_key?(state.parameter_metadata, [:speed])

      state = State.update_parameters(state, [{[:speed], 2}])
      assert state.parameter_metadata == %{}
    end
  end

  describe "event_debounced?/4" do
    test "returns false when the key has never been seen" do
      refute State.event_debounced?(%{}, {[:sensor], :map}, 1_000, 1_000)
    end

    test "returns true when the same key was seen within the window" do
      last_seen = %{{[:sensor], :map} => 500}
      assert State.event_debounced?(last_seen, {[:sensor], :map}, 1_000, 1_000)
    end

    test "returns false once the window has elapsed" do
      last_seen = %{{[:sensor], :map} => 0}
      refute State.event_debounced?(last_seen, {[:sensor], :map}, 1_000, 1_000)
    end

    test "a zero window never debounces" do
      last_seen = %{{[:sensor], :map} => 1_000}
      refute State.event_debounced?(last_seen, {[:sensor], :map}, 1_000, 0)
    end
  end

  describe "event_debounce_key/2" do
    test "keys a %BB.Message{} by path and payload struct" do
      msg = %BB.Message{
        wall_time: 0,
        node: :nonode@nohost,
        payload: %BB.Message.Sensor.JointState{
          names: [],
          positions: [],
          velocities: [],
          efforts: []
        }
      }

      assert State.event_debounce_key([:sensor, :imu], msg) ==
               {[:sensor, :imu], BB.Message.Sensor.JointState}
    end

    test "keys a plain %{payload: map} by path and :map" do
      assert State.event_debounce_key([:state_machine], %{payload: %{to: :armed}}) ==
               {[:state_machine], :map}
    end

    test "keys a bare payload value by its term" do
      assert State.event_debounce_key([:unknown], %{payload: :something}) ==
               {[:unknown], :something}
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

    test "uses BB.Message.wall_time as the event timestamp" do
      wall_time = DateTime.to_unix(~U[2026-05-18 12:34:56Z], :nanosecond)
      message = %BB.Message{wall_time: wall_time, node: :nonode@nohost, payload: %{}}

      state = State.append_event(Fixtures.sample_state(), [:test], message)
      {ts, _path, _msg} = hd(state.events)

      assert DateTime.truncate(ts, :second) == ~U[2026-05-18 12:34:56Z]
    end

    test "drops a repeat of the same path + payload-type within the window" do
      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})
      msg = %{payload: %{x: 1}}

      state = State.append_event(state, [:sensor, :imu], msg)
      state = State.append_event(state, [:sensor, :imu], msg)

      assert length(state.events) == 1
    end

    test "lets a different payload-type from the same path through" do
      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})

      state = State.append_event(state, [:sensor, :imu], %{payload: %{x: 1}})
      state = State.append_event(state, [:sensor, :imu], %{payload: :different})

      assert length(state.events) == 2
    end

    test "lets the same payload-type from a different path through" do
      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})

      state = State.append_event(state, [:sensor, :imu], %{payload: %{x: 1}})
      state = State.append_event(state, [:sensor, :arm], %{payload: %{x: 1}})

      assert length(state.events) == 2
    end

    test "records last-seen only for accepted events" do
      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})
      state = State.append_event(state, [:sensor, :imu], %{payload: %{x: 1}})

      assert Map.has_key?(state.throttle.last_seen, {[:sensor, :imu], :map})
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

    test "resets debounce tracking so the next event is accepted immediately" do
      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})
      state = State.append_event(state, [:sensor, :imu], %{payload: %{x: 1}})
      state = State.clear_events(state)

      assert state.throttle.last_seen == %{}

      state = State.append_event(state, [:sensor, :imu], %{payload: %{x: 1}})
      assert length(state.events) == 1
    end
  end

  describe "mark_render_pending/1 and clear_render_pending/1" do
    test "mark sets the flag and clear unsets it" do
      state = Fixtures.sample_state()
      refute state.throttle.render_pending?

      state = State.mark_render_pending(state)
      assert state.throttle.render_pending?

      state = State.clear_render_pending(state)
      refute state.throttle.render_pending?
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

  describe "command argument edit mode" do
    defp cmd_with_args do
      %{
        name: :move,
        allowed_states: [:idle],
        arguments: [
          %{name: :angle, type: "float", default: 1.5, required: true, doc: nil},
          %{name: :side, type: "atom", default: :left, required: false, doc: nil}
        ]
      }
    end

    defp cmd_no_args, do: %{name: :home, allowed_states: [:idle], arguments: []}

    defp edit_state(opts) do
      base = %{commands: [cmd_with_args()], command_selected: 0, command_edit_mode: true}
      Fixtures.sample_state(Map.merge(base, opts))
    end

    test "selected_command/1 returns the selected map or nil" do
      state =
        Fixtures.sample_state(%{commands: [cmd_no_args(), cmd_with_args()], command_selected: 1})

      assert State.selected_command(state).name == :move
      assert State.selected_command(Fixtures.sample_state(%{commands: []})) == nil
    end

    test "enter_command_edit_mode/1 enters when selected command has args" do
      state = Fixtures.sample_state(%{commands: [cmd_with_args()], command_selected: 0})
      assert State.enter_command_edit_mode(state).command_edit_mode == true
    end

    test "enter_command_edit_mode/1 is a no-op for arg-less commands" do
      state = Fixtures.sample_state(%{commands: [cmd_no_args()], command_selected: 0})
      assert State.enter_command_edit_mode(state).command_edit_mode == false
    end

    test "enter_command_edit_mode/1 is a no-op when no command is selected" do
      state = Fixtures.sample_state(%{commands: [], command_selected: 0})
      assert State.enter_command_edit_mode(state).command_edit_mode == false
    end

    test "exit_command_edit_mode/1 turns the flag off and keeps form_values" do
      state = edit_state(%{command_form_values: %{move: %{angle: "2.0"}}})
      exited = State.exit_command_edit_mode(state)
      assert exited.command_edit_mode == false
      assert exited.command_form_values == %{move: %{angle: "2.0"}}
    end

    test "focus_next_arg/1 wraps at the end" do
      state = edit_state(%{command_focused_arg: 1})
      assert State.focus_next_arg(state).command_focused_arg == 0
    end

    test "focus_prev_arg/1 wraps at the start" do
      state = edit_state(%{command_focused_arg: 0})
      assert State.focus_prev_arg(state).command_focused_arg == 1
    end

    test "focus_next_arg/1 is a no-op without a selected arg-bearing command" do
      state = Fixtures.sample_state(%{commands: [], command_focused_arg: 0})
      assert State.focus_next_arg(state).command_focused_arg == 0
    end

    test "focus_prev_arg/1 is a no-op without a selected arg-bearing command" do
      state = Fixtures.sample_state(%{commands: [], command_focused_arg: 0})
      assert State.focus_prev_arg(state).command_focused_arg == 0
    end

    test "arg_value/3 falls back to the argument's default when unset" do
      state = Fixtures.sample_state(%{command_form_values: %{}})
      assert State.arg_value(state, :move, %{name: :angle, default: 1.5}) == "1.5"
      assert State.arg_value(state, :move, %{name: :side, default: :left}) == ":left"
      assert State.arg_value(state, :move, %{name: :missing, default: nil}) == ""
      assert State.arg_value(state, :move, %{name: :raw, default: "hello"}) == "hello"
    end

    test "append_to_focused_arg/2 appends to the focused field's current value" do
      state = edit_state(%{command_focused_arg: 0})
      state = State.append_to_focused_arg(state, "2")
      state = State.append_to_focused_arg(state, ".")
      state = State.append_to_focused_arg(state, "5")

      assert State.arg_value(state, :move, %{name: :angle, default: 1.5}) == "1.5" <> "2.5"
    end

    test "append_to_focused_arg/2 is a no-op outside of edit mode" do
      state = Fixtures.sample_state(%{command_edit_mode: false})
      assert State.append_to_focused_arg(state, "x") == state
    end

    test "backspace_focused_arg/1 deletes the last char" do
      state =
        edit_state(%{
          command_focused_arg: 0,
          command_form_values: %{move: %{angle: "1.5"}}
        })

      state = State.backspace_focused_arg(state)
      assert State.arg_value(state, :move, %{name: :angle, default: 0.0}) == "1."
    end

    test "backspace_focused_arg/1 leaves empty strings alone" do
      state =
        edit_state(%{
          command_focused_arg: 0,
          command_form_values: %{move: %{angle: ""}}
        })

      state = State.backspace_focused_arg(state)
      assert State.arg_value(state, :move, %{name: :angle, default: 0.0}) == ""
    end

    test "backspace_focused_arg/1 is a no-op outside of edit mode" do
      state = Fixtures.sample_state(%{command_edit_mode: false})
      assert State.backspace_focused_arg(state) == state
    end

    test "append_to_focused_arg/2 is a no-op when no command is selected" do
      state = Fixtures.sample_state(%{command_edit_mode: true, commands: []})
      assert State.append_to_focused_arg(state, "x") == state
    end

    test "parsed_args_for_selected/1 parses each type" do
      cmd = %{
        name: :move,
        arguments: [
          %{name: :flag, type: "boolean", default: false},
          %{name: :off, type: "boolean", default: true},
          %{name: :int, type: "integer", default: 0},
          %{name: :flo, type: "float", default: 0.0},
          %{name: :side, type: "atom", default: :left},
          %{name: :unknown, type: "atom", default: nil},
          %{name: :note, type: "string", default: "hi"}
        ]
      }

      state =
        Fixtures.sample_state(%{
          commands: [cmd],
          command_selected: 0,
          command_form_values: %{
            move: %{
              flag: "true",
              off: "false",
              int: "42",
              flo: "3.14",
              side: ":right",
              unknown: ":__definitely_undefined_atom__",
              note: "hello"
            }
          }
        })

      args = State.parsed_args_for_selected(state)
      assert args.flag == true
      assert args.off == false
      assert args.int == 42
      assert args.flo == 3.14
      assert args.side == :right
      # falls through unchanged when atom isn't existing
      assert args.unknown == ":__definitely_undefined_atom__"
      assert args.note == "hello"
    end

    test "parsed_args_for_selected/1 returns an empty map when nothing is selected" do
      assert State.parsed_args_for_selected(Fixtures.sample_state(%{commands: []})) == %{}
    end
  end

  describe "sorted_joint_names/1" do
    test "returns joint names sorted alphabetically" do
      state = Fixtures.sample_state()
      assert State.sorted_joint_names(state) == [:elbow, :shoulder]
    end

    test "returns empty list when no joints" do
      state = Fixtures.sample_state(%{joints: %{}})
      assert State.sorted_joint_names(state) == []
    end
  end

  describe "selected_joint_name/1" do
    test "returns the joint at the selected index" do
      state = Fixtures.sample_state(%{joint_selected: 0})
      assert State.selected_joint_name(state) == :elbow

      state = Fixtures.sample_state(%{joint_selected: 1})
      assert State.selected_joint_name(state) == :shoulder
    end

    test "returns nil when no joints" do
      state = Fixtures.sample_state(%{joints: %{}, joint_selected: 0})
      assert State.selected_joint_name(state) == nil
    end

    test "returns nil when index out of range" do
      state = Fixtures.sample_state(%{joint_selected: 5})
      assert State.selected_joint_name(state) == nil
    end
  end

  describe "select_next_joint/1 and select_prev_joint/1" do
    test "navigates joint selection" do
      state = Fixtures.sample_state(%{joint_selected: 0})

      state = State.select_next_joint(state)
      assert state.joints.selected == 1

      # Already at max (2 joints)
      state = State.select_next_joint(state)
      assert state.joints.selected == 1

      state = State.select_prev_joint(state)
      assert state.joints.selected == 0

      # Already at 0
      state = State.select_prev_joint(state)
      assert state.joints.selected == 0
    end

    test "select_next_joint handles empty joints" do
      state = Fixtures.sample_state(%{joints: %{}, joint_selected: 0})
      state = State.select_next_joint(state)
      assert state.joints.selected == 0
    end
  end

  describe "set_joint_position/3" do
    test "updates position for existing joint" do
      state = Fixtures.sample_state()
      state = State.set_joint_position(state, :shoulder, 1.5)
      assert state.joints.entries.shoulder.position == 1.5
    end

    test "ignores unknown joint name" do
      state = Fixtures.sample_state()
      original = state.joints.entries
      state = State.set_joint_position(state, :wrist, 1.0)
      assert state.joints.entries == original
    end
  end

  describe "joint_step/1" do
    test "computes step from limits" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.joint_step(joint) == 0.02
    end

    test "computes step from wide limits" do
      joint = %{limits: %{lower: 0.0, upper: 100.0}}
      assert State.joint_step(joint) == 1.0
    end

    test "returns default step for unlimited joints" do
      joint = %{type: :continuous}
      assert_in_delta State.joint_step(joint), :math.pi() / 50, 1.0e-10
    end
  end

  describe "select_next_param/1 and select_prev_param/1" do
    test "navigates parameter selection" do
      params = [{[:a], 1}, {[:b], 2}, {[:c], 3}]
      state = Fixtures.sample_state(%{parameters: params, param_selected: 0})

      state = State.select_next_param(state)
      assert state.param_selected == 1

      state = State.select_next_param(state)
      assert state.param_selected == 2

      # At max
      state = State.select_next_param(state)
      assert state.param_selected == 2

      state = State.select_prev_param(state)
      assert state.param_selected == 1

      state = State.select_prev_param(state)
      assert state.param_selected == 0

      # At min
      state = State.select_prev_param(state)
      assert state.param_selected == 0
    end

    test "handles empty parameters" do
      state = Fixtures.sample_state(%{parameters: [], param_selected: 0})
      state = State.select_next_param(state)
      assert state.param_selected == 0
    end
  end

  describe "selected_param/1" do
    test "returns the parameter at the selected index (sorted by path)" do
      params = [{[:z], 99}, {[:a], 1}, {[:m], 50}]
      state = Fixtures.sample_state(%{parameters: params, param_selected: 0})
      assert State.selected_param(state) == {[:a], 1}

      state = %{state | param_selected: 2}
      assert State.selected_param(state) == {[:z], 99}
    end

    test "returns nil for empty parameters" do
      state = Fixtures.sample_state(%{parameters: [], param_selected: 0})
      assert State.selected_param(state) == nil
    end
  end

  describe "limit_proximity/2" do
    test "returns :normal when well within limits" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.limit_proximity(0.0, joint) == :normal
      assert State.limit_proximity(0.5, joint) == :normal
    end

    test "returns :warning when within 15% of a limit" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      # 0.85 is at 92.5% of range, 7.5% from upper limit
      assert State.limit_proximity(0.85, joint) == :warning
      # -0.85 is 7.5% from lower limit
      assert State.limit_proximity(-0.85, joint) == :warning
    end

    test "returns :danger when within 5% of a limit" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.limit_proximity(0.96, joint) == :danger
      assert State.limit_proximity(-0.96, joint) == :danger
    end

    test "returns :danger at exact limit" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.limit_proximity(1.0, joint) == :danger
      assert State.limit_proximity(-1.0, joint) == :danger
    end

    test "returns :normal for joints without limits" do
      assert State.limit_proximity(99.0, %{type: :continuous}) == :normal
    end

    test "returns :normal for nil position" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.limit_proximity(nil, joint) == :normal
    end
  end

  describe "clamp_position/2" do
    test "clamps above upper limit" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.clamp_position(2.0, joint) == 1.0
    end

    test "clamps below lower limit" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.clamp_position(-2.0, joint) == -1.0
    end

    test "passes through within limits" do
      joint = %{limits: %{lower: -1.0, upper: 1.0}}
      assert State.clamp_position(0.5, joint) == 0.5
    end

    test "passes through for unlimited joints" do
      joint = %{type: :continuous}
      assert State.clamp_position(99.0, joint) == 99.0
    end
  end

  describe "cycle_focused_enum/2" do
    setup do
      cmd = %{
        name: :move,
        arguments: [
          %{
            name: :side,
            type: "enum:[:left, :right, :up]",
            enum_values: [:left, :right, :up],
            default: :left
          },
          %{name: :angle, type: "float", enum_values: nil, default: 0.0}
        ]
      }

      state = %BB.TUI.State{
        commands: [cmd],
        command_selected: 0,
        command_edit_mode: true,
        command_focused_arg: 0,
        command_form_values: %{}
      }

      {:ok, state: state}
    end

    test "cycles forward through enum values, wrapping at the end", %{state: state} do
      next = State.cycle_focused_enum(state, :next)
      assert next.command_form_values[:move][:side] == ":right"

      next = State.cycle_focused_enum(next, :next)
      assert next.command_form_values[:move][:side] == ":up"

      next = State.cycle_focused_enum(next, :next)
      assert next.command_form_values[:move][:side] == ":left"
    end

    test "cycles backward through enum values, wrapping at the start", %{state: state} do
      prev = State.cycle_focused_enum(state, :prev)
      assert prev.command_form_values[:move][:side] == ":up"

      prev = State.cycle_focused_enum(prev, :prev)
      assert prev.command_form_values[:move][:side] == ":right"
    end

    test "starts from the first value when the current buffer is garbage", %{state: state} do
      seeded = %{state | command_form_values: %{move: %{side: "not_an_atom"}}}

      next = State.cycle_focused_enum(seeded, :next)
      # Garbage parses to a string, so cycle_enum_value falls back to index 0,
      # then advances by +1.
      assert next.command_form_values[:move][:side] == ":right"
    end

    test "is a no-op when not in edit mode", %{state: state} do
      out = State.cycle_focused_enum(%{state | command_edit_mode: false}, :next)
      assert out == %{state | command_edit_mode: false}
    end

    test "is a no-op for non-enum args", %{state: state} do
      out = State.cycle_focused_enum(%{state | command_focused_arg: 1}, :next)
      assert out == %{state | command_focused_arg: 1}
    end
  end

  describe "focused_arg_enum_values/1" do
    test "returns nil when the selected command has no args" do
      state = %BB.TUI.State{commands: [], command_selected: 0, command_focused_arg: 0}
      assert State.focused_arg_enum_values(state) == nil
    end
  end
end
