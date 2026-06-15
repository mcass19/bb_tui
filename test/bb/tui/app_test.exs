defmodule BB.TUI.AppTest do
  use ExUnit.Case, async: true
  use Mimic
  doctest BB.TUI

  alias BB.TUI.App
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Layout.Rect

  setup :verify_on_exit!
  setup :set_mimic_private

  describe "mount/1" do
    test "initializes state from robot module" do
      Fixtures.stub_bb_modules()

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)

      assert state.robot == BB.TUI.TestRobot
      assert state.safety.state == :disarmed
      assert state.safety.runtime == :disarmed
      assert map_size(state.joints.entries) == 2
      assert state.joints.entries.shoulder.position == 0.0
      assert state.joints.entries.elbow.position == 45.0
      assert state.events.list == []
      assert state.ui.active_panel == :safety
      assert state.events.paused? == false
      assert state.commands.selected == 0
      assert state.commands.executing == nil
    end

    test "raises on invalid robot module" do
      assert_raise ArgumentError, ~r/is not a valid BB robot module/, fn ->
        App.init(robot: __MODULE__)
      end
    end

    test "subscribes to safety and estimator paths so their messages reach the event log" do
      Fixtures.stub_bb_modules()
      test_pid = self()

      Mimic.stub(BB, :subscribe, fn _robot, path ->
        send(test_pid, {:subscribed, path})
        :ok
      end)

      assert {:ok, _state} = App.init(robot: BB.TUI.TestRobot)

      # The newly-surfaced subtrees: hardware-error detail and estimator output.
      assert_received {:subscribed, [:safety]}
      assert_received {:subscribed, [:estimator]}
      # …without dropping the pre-existing subscriptions.
      assert_received {:subscribed, [:state_machine]}
      assert_received {:subscribed, [:sensor]}
    end

    test "loads commands from BB.Dsl.Info" do
      Fixtures.stub_bb_modules()

      Mimic.stub(BB.Dsl.Info, :commands, fn _robot ->
        [%{name: :home, allowed_states: [:idle]}]
      end)

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)
      assert [%{name: :home, allowed_states: [:idle], arguments: []}] = state.commands.available
    end

    test "handles BB.Dsl.Info.commands raising" do
      Fixtures.stub_bb_modules()
      Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> raise "boom" end)

      assert {:ok, state} = App.init(robot: BB.TUI.TestRobot)
      assert state.commands.available == []
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

      assert state.parameters.list == [
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

      # brand, tab_bar, status_bar, safety, commands, joints, events, parameters = 8
      # No scrollbar pane when events are empty.
      assert is_list(widgets)
      assert length(widgets) == 8

      Enum.each(widgets, fn {widget, rect} ->
        assert is_struct(widget)
        assert %Rect{} = rect
      end)
    end

    test "renders the visualization tab body when active_tab is visualization" do
      base = Fixtures.sample_state()
      state = %{base | ui: %{base.ui | active_tab: :visualization}}
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      # brand, tab_bar, status_bar, visualization pane = 4
      assert length(widgets) == 4

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

      # 8 base panels + 1 scrollbar overlay = 9
      assert length(widgets) == 9
      assert Enum.any?(widgets, fn {w, _} -> match?(%ExRatatui.Widgets.Scrollbar{}, w) end)
    end

    test "includes help popup when show_help is true" do
      state = Fixtures.sample_state(%{show_help: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 9
    end

    test "includes force disarm popup when confirm_force_disarm is true" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      frame = %ExRatatui.Frame{width: 120, height: 40}

      widgets = App.render(state, frame)

      assert length(widgets) == 9
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

      # 8 base panels + 1 scrollbar overlay + 1 popup = 10
      assert length(widgets) == 10
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

      # No popup added — just the 8 base panels.
      assert length(widgets) == 8
    end

    test "includes the command-edit popup when in edit mode on an arg-bearing command" do
      cmd = %{
        name: :move,
        allowed_states: [:idle],
        arguments: [%{name: :angle, type: "float", default: 0.0, required: true, doc: nil}]
      }

      state =
        Fixtures.sample_state(%{
          commands: [cmd],
          command_selected: 0,
          command_edit_mode: true
        })

      frame = %ExRatatui.Frame{width: 120, height: 40}
      widgets = App.render(state, frame)

      assert length(widgets) == 9
      {last_widget, _rect} = List.last(widgets)
      assert %ExRatatui.Widgets.Popup{} = last_widget
    end

    test "skips the command-edit popup when edit mode is on but no arguments are declared" do
      no_args = %{name: :home, allowed_states: [:idle], arguments: []}

      state =
        Fixtures.sample_state(%{
          commands: [no_args],
          command_selected: 0,
          command_edit_mode: true
        })

      frame = %ExRatatui.Frame{width: 120, height: 40}
      widgets = App.render(state, frame)

      assert length(widgets) == 8
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
      assert new_state.ui.active_panel == :commands
    end

    test "shift+tab (code: back_tab) cycles to the previous panel" do
      state = Fixtures.sample_state(%{active_panel: :commands})
      event = %ExRatatui.Event.Key{code: "back_tab", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.ui.active_panel == :safety
    end

    test "number keys 1..5 jump directly to the matching panel" do
      state = Fixtures.sample_state(%{active_panel: :safety})

      for {code, panel} <- [
            {"1", :safety},
            {"2", :commands},
            {"3", :joints},
            {"4", :events},
            {"5", :parameters}
          ] do
        event = %ExRatatui.Event.Key{code: code, kind: "press"}
        assert {:noreply, new_state} = App.update({:event, event}, state)
        assert new_state.ui.active_panel == panel
      end
    end

    test "number keys are inert inside command edit mode (so digits can be typed into args)" do
      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: [
            %{
              name: :log,
              allowed_states: [:idle],
              arguments: [%{name: :level, type: "integer", default: 1}]
            }
          ],
          command_selected: 0,
          command_edit_mode: true,
          command_focused_arg: 0
        })

      event = %ExRatatui.Event.Key{code: "3", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      # Did NOT jump to :joints; the digit was appended to the focused arg.
      assert new_state.ui.active_panel == :commands
      assert new_state.commands.form_values == %{log: %{level: "13"}}
    end

    test "? key toggles help" do
      state = Fixtures.sample_state(%{show_help: false})
      event = %ExRatatui.Event.Key{code: "?", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.ui.show_help?
    end

    test "j/down scrolls help overlay down" do
      state = Fixtures.sample_state(%{show_help: true, help_scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.ui.help_scroll_offset == 1
      assert new_state.ui.show_help?
    end

    test "k/up scrolls help overlay up" do
      state = Fixtures.sample_state(%{show_help: true, help_scroll_offset: 3})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.ui.help_scroll_offset == 2
      assert new_state.ui.show_help?
    end

    test "any key dismisses help overlay" do
      state = Fixtures.sample_state(%{show_help: true})
      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.ui.show_help?
    end

    test "any key dismisses event detail popup" do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{payload: :data}}]

      state =
        Fixtures.sample_state(%{show_event_detail: true, events: events, scroll_offset: 0})

      event = %ExRatatui.Event.Key{code: "x", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.events.show_detail?
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
      assert new_state.safety.confirm_force_disarm?
    end

    test "f key does nothing when not in error state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      event = %ExRatatui.Event.Key{code: "f", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.safety.confirm_force_disarm?
    end

    test "y key confirms force disarm" do
      Fixtures.stub_bb_modules()
      Mimic.expect(BB.Safety, :force_disarm, fn _robot -> :ok end)

      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "y", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.safety.confirm_force_disarm?
    end

    test "n key dismisses force disarm popup" do
      state = Fixtures.sample_state(%{confirm_force_disarm: true})
      event = %ExRatatui.Event.Key{code: "n", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      refute new_state.safety.confirm_force_disarm?
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
      assert new_state.events.scroll_offset == 1
    end

    test "down arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})
      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.scroll_offset == 1
    end

    test "up arrow scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.scroll_offset == 1
    end

    test "k/up scrolls events when events panel is active" do
      events = Enum.map(1..5, &{DateTime.utc_now(), [:test], %{i: &1}})
      state = Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 2})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.scroll_offset == 1
    end

    test "p key toggles events pause" do
      state = Fixtures.sample_state(%{active_panel: :events, events_paused: false})
      event = %ExRatatui.Event.Key{code: "p", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.paused?
    end

    test "c key clears events" do
      events = [{DateTime.utc_now(), [:test], %{}}]
      state = Fixtures.sample_state(%{active_panel: :events, events: events})
      event = %ExRatatui.Event.Key{code: "c", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.list == []
    end

    test "enter key opens event detail when events panel is active" do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{payload: :data}}]

      state =
        Fixtures.sample_state(%{active_panel: :events, events: events, scroll_offset: 0})

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.events.show_detail?
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
      assert new_state.commands.selected == 1
    end

    test "k/up selects prev command" do
      commands = [%{name: :a}, %{name: :b}]

      state =
        Fixtures.sample_state(%{active_panel: :commands, commands: commands, command_selected: 1})

      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.selected == 0
    end

    test "enter on a Ready command returns a Command.async that reports {:command_result, _}" do
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
      assert new_state.commands.executing == :running
      assert new_state.commands.result == nil

      # BB.Command.await/2 enforces the timeout internally, so we hand
      # the runtime a single async (no separate send_after backstop).
      assert [%ExRatatui.Command{kind: :async}] = opts[:commands]
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
      assert new_state.commands.executing == nil
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

    # Commands panel — argument edit mode

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

    defp edit_mode_state(opts \\ %{}) do
      Fixtures.sample_state(
        Map.merge(
          %{
            active_panel: :commands,
            commands: [cmd_with_args()],
            command_selected: 0,
            command_edit_mode: true,
            runtime_state: :idle
          },
          opts
        )
      )
    end

    test "enter on a command with args enters edit mode without executing" do
      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: [cmd_with_args()],
          command_selected: 0,
          runtime_state: :idle
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.edit_mode? == true
      assert new_state.commands.executing == nil
    end

    test "esc exits edit mode" do
      state = edit_mode_state()
      event = %ExRatatui.Event.Key{code: "esc", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.edit_mode? == false
    end

    test "tab/down focuses the next arg in edit mode" do
      state = edit_mode_state(%{command_focused_arg: 0})

      for code <- ["tab", "down"] do
        event = %ExRatatui.Event.Key{code: code, kind: "press"}
        assert {:noreply, new_state} = App.update({:event, event}, state)
        assert new_state.commands.focused_arg == 1
      end
    end

    test "back_tab/up focuses the previous arg in edit mode" do
      state = edit_mode_state(%{command_focused_arg: 1})

      for code <- ["back_tab", "up"] do
        event = %ExRatatui.Event.Key{code: code, kind: "press"}
        assert {:noreply, new_state} = App.update({:event, event}, state)
        assert new_state.commands.focused_arg == 0
      end
    end

    test "typing a char appends to the focused arg" do
      state = edit_mode_state(%{command_focused_arg: 0})
      event = %ExRatatui.Event.Key{code: "2", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.form_values == %{move: %{angle: "1.52"}}
    end

    test "backspace deletes the last char of the focused arg" do
      state =
        edit_mode_state(%{
          command_focused_arg: 0,
          command_form_values: %{move: %{angle: "1.5"}}
        })

      event = %ExRatatui.Event.Key{code: "backspace", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.form_values == %{move: %{angle: "1."}}
    end

    test "right arrow cycles the focused enum forward" do
      enum_cmd = %{
        name: :move,
        allowed_states: [:idle],
        arguments: [
          %{
            name: :side,
            type: "enum:[:left, :right]",
            enum_values: [:left, :right],
            default: :left
          }
        ]
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: [enum_cmd],
          command_selected: 0,
          command_edit_mode: true,
          command_focused_arg: 0
        })

      event = %ExRatatui.Event.Key{code: "right", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.form_values == %{move: %{side: ":right"}}
    end

    test "h cycles the focused enum backward when the focused arg is enum-typed" do
      enum_cmd = %{
        name: :move,
        allowed_states: [:idle],
        arguments: [
          %{
            name: :side,
            type: "enum:[:left, :right]",
            enum_values: [:left, :right],
            default: :left
          }
        ]
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :commands,
          commands: [enum_cmd],
          command_selected: 0,
          command_edit_mode: true,
          command_focused_arg: 0
        })

      event = %ExRatatui.Event.Key{code: "h", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.form_values == %{move: %{side: ":right"}}
    end

    test "h on a non-enum arg falls through to the append handler" do
      state = edit_mode_state(%{command_focused_arg: 0})

      event = %ExRatatui.Event.Key{code: "h", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.commands.form_values == %{move: %{angle: "1.5h"}}
    end

    test "left arrow on a non-enum arg is a no-op" do
      state = edit_mode_state(%{command_focused_arg: 0})

      event = %ExRatatui.Event.Key{code: "left", kind: "press"}

      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "enter in edit mode executes with parsed args and exits edit mode" do
      state =
        edit_mode_state(%{
          command_focused_arg: 0,
          command_form_values: %{move: %{angle: "2.5"}}
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}

      assert {:noreply, new_state, opts} = App.update({:event, event}, state)
      assert new_state.commands.edit_mode? == false
      assert new_state.commands.executing == :running
      assert [%ExRatatui.Command{kind: :async}] = opts[:commands]
    end

    # Result/timeout/error semantics are exercised by the integration suite,
    # which boots a real ExRatatui.Server so that Command.async actually
    # drives the {:info, _} mailbox round-trip. See
    # `test/bb/tui/integration_test.exs` ("Command result flow").

    # Joints panel keys — navigation
    test "j/down selects next joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 0})
      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.selected == 1
    end

    test "down arrow selects next joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 0})
      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.selected == 1
    end

    test "k/up selects previous joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 1})
      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.selected == 0
    end

    test "up arrow selects previous joint" do
      state = Fixtures.sample_state(%{active_panel: :joints, joint_selected: 1})
      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.joints.selected == 0
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
      assert new_state.joints.entries.shoulder.position > 0.0
    end

    test "adjusting a joint records the commanded target alongside the new position" do
      joints = %{
        shoulder: %{
          joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.0, upper: 1.0}},
          position: 0.0,
          target: nil
        }
      }

      state =
        Fixtures.sample_state(%{
          active_panel: :joints,
          joints: joints,
          joint_selected: 0,
          safety_state: :armed
        })

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      target = new_state.joints.entries.shoulder.target
      assert is_float(target)
      assert target == new_state.joints.entries.shoulder.position
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
      assert new_state.joints.entries.shoulder.position < 0.0
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
      assert new_state.joints.entries.shoulder.position > 0.0
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

      small_delta = small_state.joints.entries.shoulder.position
      big_delta = big_state.joints.entries.shoulder.position

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

      small_delta = abs(small_state.joints.entries.shoulder.position)
      big_delta = abs(big_state.joints.entries.shoulder.position)

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
      assert new_state.joints.entries.shoulder.position == 1.0
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
      assert new_state.joints.entries.shoulder.position == 0.0
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
      assert new_state.joints.entries.shoulder.position == nil
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
      assert new_state.joints.entries.shoulder.position == 0.0
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
      assert new_state.joints.entries.shoulder.position > 0.0
    end

    # Parameters panel keys — navigation
    test "j/down selects next parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "j", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.selected == 1
    end

    test "down arrow selects next parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 0})

      event = %ExRatatui.Event.Key{code: "down", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.selected == 1
    end

    test "k/up selects previous parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 1})

      event = %ExRatatui.Event.Key{code: "k", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.selected == 0
    end

    test "up arrow selects previous parameter" do
      params = [{[:a], 1}, {[:b], 2}]

      state =
        Fixtures.sample_state(%{active_panel: :parameters, parameters: params, param_selected: 1})

      event = %ExRatatui.Event.Key{code: "up", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.selected == 0
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

    test "l/right scales float step to 1% of declared range" do
      Fixtures.stub_bb_modules()

      # Range 0.0..1.0 → step = (1.0 - 0.0) / 100 = 0.01 per keypress.
      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 0.51, 0.0001
        :ok
      end)

      params = [{[:kp], 0.5}]
      meta = %{[:kp] => %{type: {:float, [min: 0.0, max: 1.0]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "L scales float step to 10% of declared range" do
      Fixtures.stub_bb_modules()

      # Range 0.0..1.0 → 10x step = 0.1.
      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 0.6, 0.0001
        :ok
      end)

      params = [{[:kp], 0.5}]
      meta = %{[:kp] => %{type: {:float, [min: 0.0, max: 1.0]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "l/right clamps float value at upper bound" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:kp], val ->
        assert_in_delta val, 1.0, 0.0001
        :ok
      end)

      params = [{[:kp], 1.0}]
      meta = %{[:kp] => %{type: {:float, [min: 0.0, max: 1.0]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "h/left clamps integer value at lower bound" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 0 -> :ok end)

      params = [{[:count], 0}]
      meta = %{[:count] => %{type: {:integer, [min: 0, max: 1_000]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "H", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "l/right scales integer step to 1% of declared range" do
      Fixtures.stub_bb_modules()

      # Range 0..1_000 → step = div(1_000 - 0, 100) = 10 per keypress.
      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 110 -> :ok end)

      params = [{[:count], 100}]
      meta = %{[:count] => %{type: {:integer, [min: 0, max: 1_000]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
    end

    test "t key on local tab is a no-op when no bridges are discovered" do
      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local],
          parameter_tab_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "t", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.tab_selected == 0
      assert new_state.parameters.remote == %{}
    end

    test "t key cycles to a bridge tab and fetches its parameters" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :list_remote, fn _robot, :mavlink ->
        {:ok, [%{id: "ROLL_P", value: 0.1, type: :float}]}
      end)

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 0,
          param_selected: 3
        })

      event = %ExRatatui.Event.Key{code: "t", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.tab_selected == 1
      assert new_state.parameters.selected == 0
      assert [%{id: "ROLL_P"}] = new_state.parameters.remote.mavlink
    end

    test "t key stores {:error, _} as-is when list_remote fails" do
      Fixtures.stub_bb_modules()

      Mimic.expect(BB.Parameter, :list_remote, fn _robot, :mavlink ->
        {:error, :nodedown}
      end)

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "t", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.remote.mavlink == {:error, :nodedown}
    end

    test "l on a bridge tab calls set_remote_parameter with the selected param id" do
      Fixtures.stub_bb_modules()

      remote = [%{id: "PITCH_P", value: 0.10, min: 0.0, max: 1.0}]

      Mimic.expect(BB.Parameter, :set_remote, fn _robot, :mavlink, "PITCH_P", value ->
        # Range 0.0..1.0 → step = 0.01 per keypress.
        assert_in_delta value, 0.11, 0.0001
        :ok
      end)

      # set_remote success triggers a refresh; provide the updated list.
      Mimic.expect(BB.Parameter, :list_remote, fn _robot, :mavlink ->
        {:ok, [%{id: "PITCH_P", value: 0.11, min: 0.0, max: 1.0}]}
      end)

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      # Cache reflects the refresh fired after :ok.
      assert [%{value: 0.11}] = new_state.parameters.remote.mavlink
    end

    test "remote adjustment clamps integer to declared bounds" do
      Fixtures.stub_bb_modules()

      remote = [%{id: "RATE", value: 1000, min: 0, max: 1000}]

      Mimic.expect(BB.Parameter, :set_remote, fn _robot, :mavlink, "RATE", 1000 -> :ok end)
      Mimic.expect(BB.Parameter, :list_remote, fn _robot, :mavlink -> {:ok, remote} end)

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "L", kind: "press"}
      assert {:noreply, _} = App.update({:event, event}, state)
    end

    test "Enter on a bridge tab toggles a boolean remote param" do
      Fixtures.stub_bb_modules()

      remote = [%{id: "ARM_CHECKS", value: true}]

      Mimic.expect(BB.Parameter, :set_remote, fn _robot, :mavlink, "ARM_CHECKS", false ->
        :ok
      end)

      Mimic.expect(BB.Parameter, :list_remote, fn _robot, :mavlink ->
        {:ok, [%{id: "ARM_CHECKS", value: false}]}
      end)

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}
      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert [%{value: false}] = new_state.parameters.remote.mavlink
    end

    test "remote set returning {:error, _} leaves the cache untouched" do
      Fixtures.stub_bb_modules()

      remote = [%{id: "PITCH_P", value: 0.10, min: 0.0, max: 1.0}]

      Mimic.expect(BB.Parameter, :set_remote, fn _, _, _, _ -> {:error, :nodedown} end)
      # No Mimic.expect on list_remote — refresh must not fire on failure.

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}
      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.remote.mavlink == remote
    end

    test "remote adjustment is a no-op for a non-numeric remote param" do
      remote = [%{id: "MODE", value: "AUTO"}]

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}
      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "remote Enter is a no-op for a non-boolean remote param" do
      remote = [%{id: "PITCH_P", value: 0.1}]

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: remote},
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "enter", kind: "press"}
      assert {:noreply, ^state} = App.update({:event, event}, state)
    end

    test "t key cycling back to :local does not call list_remote" do
      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}],
          parameter_tab_selected: 1,
          remote_parameters: %{mavlink: []}
        })

      # No Mimic.expect — if list_remote were called the test would fail.
      event = %ExRatatui.Event.Key{code: "t", kind: "press"}

      assert {:noreply, new_state} = App.update({:event, event}, state)
      assert new_state.parameters.tab_selected == 0
    end

    test "integer step is at least 1 even for tiny ranges" do
      Fixtures.stub_bb_modules()

      # Range 0..10 → div(10, 100) would be 0, so the floor kicks in.
      Mimic.expect(BB.Parameter, :set, fn _robot, [:count], 6 -> :ok end)

      params = [{[:count], 5}]
      meta = %{[:count] => %{type: {:integer, [min: 0, max: 10]}}}

      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameters: params,
          parameter_metadata: meta,
          param_selected: 0
        })

      event = %ExRatatui.Event.Key{code: "l", kind: "press"}

      assert {:noreply, _new_state} = App.update({:event, event}, state)
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
      assert new_state.safety.state == :armed
      assert new_state.safety.runtime == :idle
      assert length(new_state.events.list) == 1
    end

    test "sensor message updates positions and appends event" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      payload = %{names: [:shoulder, :elbow], positions: [10.0, 20.0]}
      msg = %{payload: payload}

      assert {:noreply, new_state, render?: false} =
               App.update({:info, {:bb, [:sensor, :joints], msg}}, state)

      assert new_state.joints.entries.shoulder.position == 10.0
      assert new_state.joints.entries.elbow.position == 20.0
      assert length(new_state.events.list) == 1
      assert new_state.throttle.render_pending?
    end

    test "sensor message carrying battery telemetry records it in state.power" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      battery = %BB.Message.Sensor.BatteryState{voltage: 12.0, percentage: 0.42}
      msg = %{payload: battery}

      assert {:noreply, new_state, render?: false} =
               App.update({:info, {:bb, [:sensor, :battery_bus], msg}}, state)

      assert new_state.power.battery == battery
      assert length(new_state.events.list) == 1
    end

    test "sensor message with non-standard payload still appends event" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state()
      msg = %{payload: %{something_else: true}}

      assert {:noreply, new_state, render?: false} =
               App.update({:info, {:bb, [:sensor, :other], msg}}, state)

      assert new_state.joints.entries == state.joints.entries
      assert length(new_state.events.list) == 1
      assert new_state.throttle.render_pending?
    end

    test "a burst of identical sensor messages collapses to one event row" do
      Fixtures.stub_bb_modules()

      state = Fixtures.sample_state(%{event_debounce_ms: 1_000})
      payload = %{names: [:shoulder], positions: [1.0]}
      msg = %{payload: payload}

      state =
        Enum.reduce(1..5, state, fn _i, acc ->
          {:noreply, next, render?: false} =
            App.update({:info, {:bb, [:sensor, :joints], msg}}, acc)

          next
        end)

      assert length(state.events.list) == 1
      assert state.throttle.render_pending?
    end

    test "param message updates parameters and appends event" do
      Fixtures.stub_bb_modules()
      params = [{[:speed], 100}]
      Mimic.stub(BB.Parameter, :list, fn _robot, _opts -> params end)

      state = Fixtures.sample_state()
      msg = %{payload: %{path: [:speed], value: 100}}

      assert {:noreply, new_state} = App.update({:info, {:bb, [:param, :speed], msg}}, state)
      assert new_state.parameters.list == params
      assert length(new_state.events.list) == 1
    end

    test "catch-all bb message only appends event" do
      state = Fixtures.sample_state()
      msg = %{payload: :something}

      assert {:noreply, new_state} = App.update({:info, {:bb, [:unknown], msg}}, state)
      assert length(new_state.events.list) == 1
    end

    test "hardware-error detail on [:safety, :error] surfaces in the event log" do
      state = Fixtures.sample_state()
      error = %BB.Safety.HardwareError{path: [:actuator, :elbow], error: :overcurrent}
      msg = %{payload: error}

      assert {:noreply, new_state} =
               App.update({:info, {:bb, [:safety, :error], msg}}, state)

      assert [{_ts, [:safety, :error], ^msg}] = new_state.events.list
    end

    test "estimator output on [:estimator | _] surfaces in the event log" do
      state = Fixtures.sample_state()
      msg = %{payload: %BB.Message.Estimator.Pose{transform: :stub}}

      assert {:noreply, new_state} =
               App.update({:info, {:bb, [:estimator, :base_link], msg}}, state)

      assert [{_ts, [:estimator, :base_link], ^msg}] = new_state.events.list
    end

    test "command_result message sets result" do
      state = Fixtures.sample_state(%{executing_command: self()})

      assert {:noreply, new_state} =
               App.update({:info, {:command_result, {:ok, :completed}}}, state)

      assert new_state.commands.result == {:ok, :completed}
      assert new_state.commands.executing == nil
    end

    test ":sensor_flush clears the pending flag and renders" do
      state = Fixtures.sample_state(%{render_pending?: true})

      assert {:noreply, new_state} = App.update({:info, :sensor_flush}, state)
      refute new_state.throttle.render_pending?
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
      assert next.ui.throbber_step == 8
    end

    test "arms the sensor_flush one-shot while a render is pending" do
      state = Fixtures.sample_state(%{render_pending?: true, sensor_flush_ms: 33})

      subs = App.subscriptions(state)

      assert Enum.any?(subs, fn s ->
               s.id == :sensor_flush and s.kind == :once and s.interval_ms == 33 and
                 s.message == :sensor_flush
             end)
    end

    test "does not arm sensor_flush when no render is pending" do
      state = Fixtures.sample_state(%{render_pending?: false})

      refute Enum.any?(App.subscriptions(state), &(&1.id == :sensor_flush))
    end

    test "arms both throbber and sensor_flush when animating and pending" do
      state =
        Fixtures.sample_state(%{
          safety_state: :disarming,
          render_pending?: true,
          sensor_flush_ms: 33
        })

      ids = Enum.map(App.subscriptions(state), & &1.id)
      assert :throbber in ids
      assert :sensor_flush in ids
    end
  end
end
