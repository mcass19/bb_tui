defmodule BB.TUI.App do
  @moduledoc """
  Main TUI application using `ExRatatui.App` behaviour.

  Renders the dashboard layout and handles keyboard events and PubSub messages
  from the BB robot. All state transitions are delegated to `BB.TUI.State`.

  ## Layout

      ┌ Safety ────────┬─ Joint Control ──────────────────────────────┐
      │ ● ARMED        │ Joint       Type  Position  Range           │
      │ Runtime: Idle  │ elbow       rev   -63.8°    ████████░░░░░░  │
      │ [a] Arm        │ gripper SIM pri    30.6mm   ███░░░░░░░░░░░  │
      │ [d] Disarm     │ ...                                         │
      ├ Commands ──────┤                                             │
      │ ▶ home   Ready │                                             │
      │   calibrate    │                                             │
      ├ Events (47) ───┴── Parameters ───────────────────────────────┤
      │ 18:23:12 sensor.sim  │ speed              100               │
      │ 18:23:11 state_m...  │ controller.kp      0.5               │
      └──────────────────────┴───────────────────────────────────────┘
       Robot | ● Armed | idle | [q]Quit [Tab]Panel [?]Help

  ## Runtime

  Uses the ExRatatui **callback runtime** (`use ExRatatui.App`, which
  defaults to `runtime: :callbacks`). Each mount owns a linked
  `Task.Supervisor` that runs robot command execution off the render
  loop so a slow `Robot.execute_command/4` can't block input.

  > **Planned:** migrate to `use ExRatatui.App, runtime: :reducer` so
  > command execution and subscriptions become declarative
  > `ExRatatui.Command` / `ExRatatui.Subscription` values and the
  > unified `update/2` path replaces the split between `handle_event/2`
  > / `handle_info/2`. See `BB.TUI` for the full rationale.

  ## Callbacks

    * `mount/1` — validates the robot module, subscribes to PubSub,
      snapshots ETS state, and starts a per-session `Task.Supervisor`
    * `render/2` — composes panel functions into a flat
      `[{widget, rect}]` list (the events panel contributes two panes:
      the list and an overlay `ExRatatui.Widgets.Scrollbar`)
    * `handle_event/2` — keyboard input dispatches BB API calls and
      state transitions
    * `handle_info/2` — PubSub messages (`{:bb, path, msg}`) update
      state; `{:command_result, _}` messages arrive from the supervised
      command Task
    * `terminate/2` — cleanup (no-op)
  """

  use ExRatatui.App

  alias BB.TUI.Panels
  alias BB.TUI.Robot
  alias BB.TUI.State
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

  @command_timeout Application.compile_env(:bb_tui, :command_timeout, 30_000)

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def mount(opts) do
    robot = Keyword.fetch!(opts, :robot)
    node = Keyword.get(opts, :node)

    unless Code.ensure_loaded?(robot) and
             function_exported?(robot, :robot, 0) and
             function_exported?(robot, :spark_dsl_config, 0) do
      raise ArgumentError, "#{inspect(robot)} is not a valid BB robot module"
    end

    Robot.subscribe(robot, [[:state_machine], [:sensor], [:param]], node)

    {:ok, task_supervisor} = Task.Supervisor.start_link()

    robot_struct = Robot.get_robot(robot, node)
    positions = Robot.positions(robot, node)

    joints =
      robot_struct
      |> BB.Robot.joints_in_order()
      |> Enum.filter(&BB.Robot.Joint.movable?/1)
      |> Map.new(&{&1.name, %{joint: &1, position: positions[&1.name] || 0.0}})

    commands = Robot.discover_commands(robot, node)

    state =
      %State{
        robot: robot,
        robot_struct: robot_struct,
        node: node,
        safety_state: Robot.safety_state(robot, node),
        runtime_state: Robot.runtime_state(robot, node),
        joints: joints,
        events: [],
        commands: commands,
        active_panel: :safety,
        scroll_offset: 0,
        show_help: false,
        confirm_force_disarm: false,
        task_supervisor: task_supervisor
      }
      |> State.update_parameters(Robot.list_parameters(robot, [], node))

    {:ok, state}
  end

  @impl true
  def render(state, frame) do
    full = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Title bar + main area + status bar
    [title_bar_area, main, status_bar_area] =
      Layout.split(full, :vertical, [
        {:length, 1},
        {:min, 0},
        {:length, 1}
      ])

    # Top section (60%) + bottom section (40%)
    [top, bottom] =
      Layout.split(main, :vertical, [
        {:percentage, 60},
        {:percentage, 40}
      ])

    # Top: left sidebar (25%) + joints (75%)
    [left_col, joints_area] =
      Layout.split(top, :horizontal, [
        {:percentage, 25},
        {:percentage, 75}
      ])

    # Left sidebar: safety (55%) + commands (45%)
    [safety_area, commands_area] =
      Layout.split(left_col, :vertical, [
        {:percentage, 55},
        {:percentage, 45}
      ])

    # Bottom: events (55%) + parameters (45%)
    [events_area, params_area] =
      Layout.split(bottom, :horizontal, [
        {:percentage, 55},
        {:percentage, 45}
      ])

    panels =
      [
        {Panels.TitleBar.render(state), title_bar_area},
        {Panels.Safety.render(state, state.active_panel == :safety), safety_area},
        {Panels.Commands.render(state, state.active_panel == :commands), commands_area},
        {Panels.Joints.render(state, state.active_panel == :joints), joints_area}
      ] ++
        Panels.Events.render_panes(state, state.active_panel == :events, events_area) ++
        [
          {Panels.Parameters.render(state, state.active_panel == :parameters), params_area},
          {Panels.StatusBar.render(state), status_bar_area}
        ]

    maybe_add_popup(panels, state, full)
  end

  @impl true
  # ── Popup intercepts ────────────────────────────────────────
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{show_help: true} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.scroll_help_down(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{show_help: true} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.scroll_help_up(state)}
  end

  def handle_event(%ExRatatui.Event.Key{kind: "press"}, %{show_help: true} = state) do
    {:noreply, State.toggle_help(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "y", kind: "press"},
        %{confirm_force_disarm: true} = state
      ) do
    Robot.force_disarm(state.robot, state.node)
    {:noreply, State.dismiss_force_disarm(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "n", kind: "press"},
        %{confirm_force_disarm: true} = state
      ) do
    {:noreply, State.dismiss_force_disarm(state)}
  end

  def handle_event(%ExRatatui.Event.Key{kind: "press"}, %{confirm_force_disarm: true} = state) do
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{kind: "press"}, %{show_event_detail: true} = state) do
    {:noreply, State.dismiss_event_detail(state)}
  end

  # ── Global keys ─────────────────────────────────────────────
  def handle_event(%ExRatatui.Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "tab", kind: "press"}, state) do
    {:noreply, State.cycle_panel(state)}
  end

  def handle_event(%ExRatatui.Event.Key{code: "?", kind: "press"}, state) do
    {:noreply, State.toggle_help(state)}
  end

  def handle_event(%ExRatatui.Event.Key{code: "a", kind: "press"}, state) do
    Robot.arm(state.robot, state.node)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "d", kind: "press"}, state) do
    Robot.disarm(state.robot, state.node)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "f", kind: "press"}, state) do
    if state.safety_state == :error do
      {:noreply, State.show_force_disarm(state)}
    else
      {:noreply, state}
    end
  end

  # ── Events panel keys ──────────────────────────────────────
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :events} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.scroll_down(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :events} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.scroll_up(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "p", kind: "press"},
        %{active_panel: :events} = state
      ) do
    {:noreply, State.toggle_events_pause(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "c", kind: "press"},
        %{active_panel: :events} = state
      ) do
    {:noreply, State.clear_events(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "enter", kind: "press"},
        %{active_panel: :events} = state
      ) do
    if State.selected_event(state) do
      {:noreply, State.toggle_event_detail(state)}
    else
      {:noreply, state}
    end
  end

  # ── Commands panel keys ────────────────────────────────────
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :commands} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_command(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :commands} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_command(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "enter", kind: "press"},
        %{active_panel: :commands} = state
      ) do
    execute_selected_command(state)
  end

  # ── Joints panel keys ──────────────────────────────────────
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :joints} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_joint(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :joints} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_joint(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :joints} = state
      )
      when code in ["l", "right"] do
    adjust_selected_joint(state, :increase, 1)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :joints} = state
      )
      when code in ["h", "left"] do
    adjust_selected_joint(state, :decrease, 1)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "L", kind: "press"},
        %{active_panel: :joints} = state
      ) do
    adjust_selected_joint(state, :increase, 10)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "H", kind: "press"},
        %{active_panel: :joints} = state
      ) do
    adjust_selected_joint(state, :decrease, 10)
  end

  # ── Parameters panel keys ───────────────────────────────────
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :parameters} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_param(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :parameters} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_param(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :parameters} = state
      )
      when code in ["l", "right"] do
    adjust_selected_param(state, :increase, 1)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :parameters} = state
      )
      when code in ["h", "left"] do
    adjust_selected_param(state, :decrease, 1)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "L", kind: "press"},
        %{active_panel: :parameters} = state
      ) do
    adjust_selected_param(state, :increase, 10)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "H", kind: "press"},
        %{active_panel: :parameters} = state
      ) do
    adjust_selected_param(state, :decrease, 10)
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "enter", kind: "press"},
        %{active_panel: :parameters} = state
      ) do
    toggle_selected_param(state)
  end

  # ── Catch-all ──────────────────────────────────────────────
  def handle_event(_event, state) do
    {:noreply, state}
  end

  # ── PubSub messages ────────────────────────────────────────

  @impl true
  def handle_info({:bb, [:state_machine | _] = path, msg}, state) do
    safety_state = Robot.safety_state(state.robot, state.node)
    runtime_state = Robot.runtime_state(state.robot, state.node)

    state =
      state
      |> State.update_safety(safety_state, runtime_state)
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  def handle_info({:bb, [:sensor | _] = path, %{payload: payload} = msg}, state) do
    positions =
      case payload do
        %{names: names, positions: pos} -> Enum.zip(names, pos) |> Map.new()
        _ -> %{}
      end

    state =
      state
      |> State.update_positions(positions)
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  def handle_info({:bb, [:param | _] = path, msg}, state) do
    parameters = Robot.list_parameters(state.robot, [], state.node)

    state =
      state
      |> State.update_parameters(parameters)
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  def handle_info({:bb, path, msg}, state) do
    {:noreply, State.append_event(state, path, msg)}
  end

  def handle_info({:command_result, result}, state) do
    {:noreply, State.set_command_result(state, result)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  # ── Helpers ────────────────────────────────────────────────

  defp maybe_add_popup(panels, %{show_help: true, help_scroll_offset: offset}, full) do
    panels ++ [{Panels.Help.render(offset), full}]
  end

  defp maybe_add_popup(panels, %{confirm_force_disarm: true}, full) do
    panels ++ [{Panels.ForceDisarm.render(), full}]
  end

  defp maybe_add_popup(panels, %{show_event_detail: true} = state, full) do
    case State.selected_event(state) do
      nil -> panels
      event -> panels ++ [{Panels.EventDetail.render(event), full}]
    end
  end

  defp maybe_add_popup(panels, _state, _full), do: panels

  defp adjust_selected_joint(state, _direction, _multiplier)
       when state.safety_state not in [:armed, :disarming] do
    {:noreply, state}
  end

  defp adjust_selected_joint(state, direction, multiplier) do
    name = State.selected_joint_name(state)

    case name && Map.get(state.joints, name) do
      nil ->
        {:noreply, state}

      %{position: nil} ->
        {:noreply, state}

      %{position: pos, joint: joint} ->
        step = State.joint_step(joint) * multiplier

        new_pos =
          case direction do
            :increase -> pos + step
            :decrease -> pos - step
          end
          |> State.clamp_position(joint)

        actuator = find_actuator_for_joint(state.robot_struct, name)

        if actuator do
          Robot.set_actuator(state.robot, actuator, new_pos, state.node)
          {:noreply, state}
        else
          publish_simulated_position(state.robot, name, new_pos, state.node)
          {:noreply, State.set_joint_position(state, name, new_pos)}
        end
    end
  end

  defp publish_simulated_position(robot, joint_name, position, node) do
    {:ok, msg} =
      BB.Message.new(BB.Message.Sensor.JointState, :simulated,
        names: [joint_name],
        positions: [position * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    Robot.publish(robot, [:sensor, :simulated], msg, node)
  end

  defp find_actuator_for_joint(%{actuators: actuators}, joint_name) do
    actuators
    |> Enum.find(fn {_name, info} -> info.joint == joint_name end)
    |> case do
      {actuator_name, _info} -> actuator_name
      nil -> nil
    end
  end

  defp find_actuator_for_joint(_, _joint_name), do: nil

  defp adjust_selected_param(state, direction, multiplier) do
    case State.selected_param(state) do
      {path, value} when is_integer(value) ->
        step = multiplier
        new_value = if direction == :increase, do: value + step, else: value - step
        Robot.set_parameter(state.robot, path, new_value, state.node)
        {:noreply, state}

      {path, value} when is_float(value) ->
        step = 0.1 * multiplier
        new_value = if direction == :increase, do: value + step, else: value - step
        Robot.set_parameter(state.robot, path, new_value, state.node)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp toggle_selected_param(state) do
    case State.selected_param(state) do
      {path, value} when is_boolean(value) ->
        Robot.set_parameter(state.robot, path, !value, state.node)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp execute_selected_command(%State{commands: commands, command_selected: idx} = state) do
    case Enum.at(commands, idx) do
      nil ->
        {:noreply, state}

      cmd ->
        if Panels.Commands.command_ready?(cmd, state.runtime_state) and
             state.executing_command == nil do
          tui_pid = self()
          robot = state.robot
          node = state.node
          name = cmd.name

          {:ok, pid} =
            Task.Supervisor.start_child(state.task_supervisor, fn ->
              run_command(tui_pid, robot, name, node)
            end)

          {:noreply, State.start_command(state, pid)}
        else
          {:noreply, state}
        end
    end
  end

  defp run_command(tui_pid, robot, name, node) do
    case Robot.execute_command(robot, name, %{}, node) do
      {:ok, cmd_pid} ->
        ref = Process.monitor(cmd_pid)

        receive do
          {:DOWN, ^ref, :process, ^cmd_pid, :normal} ->
            send(tui_pid, {:command_result, {:ok, :completed}})

          {:DOWN, ^ref, :process, ^cmd_pid, reason} ->
            send(tui_pid, {:command_result, {:error, reason}})
        after
          @command_timeout ->
            send(tui_pid, {:command_result, {:error, :timeout}})
        end

      {:error, reason} ->
        send(tui_pid, {:command_result, {:error, reason}})
    end
  end
end
