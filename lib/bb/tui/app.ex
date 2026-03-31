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

  ## Callbacks

    * `mount/1` — validates the robot module, subscribes to PubSub, snapshots ETS state
    * `render/2` — composes panel functions into `[{widget, rect}]` list
    * `handle_event/2` — keyboard input dispatches BB API calls and state transitions
    * `handle_info/2` — PubSub messages (`{:bb, path, msg}`) update state
    * `terminate/2` — cleanup (no-op)
  """

  use ExRatatui.App

  alias BB.TUI.Panels
  alias BB.TUI.State
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

  @command_timeout Application.compile_env(:bb_tui, :command_timeout, 30_000)

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def mount(opts) do
    robot = Keyword.fetch!(opts, :robot)

    unless Code.ensure_loaded?(robot) and
             function_exported?(robot, :robot, 0) and
             function_exported?(robot, :spark_dsl_config, 0) do
      raise ArgumentError, "#{inspect(robot)} is not a valid BB robot module"
    end

    BB.subscribe(robot, [:state_machine])
    BB.subscribe(robot, [:sensor])
    BB.subscribe(robot, [:param])

    robot_struct = BB.Robot.Runtime.get_robot(robot)
    positions = BB.Robot.Runtime.positions(robot)

    joints =
      robot_struct
      |> BB.Robot.joints_in_order()
      |> Enum.filter(&BB.Robot.Joint.movable?/1)
      |> Map.new(&{&1.name, %{joint: &1, position: positions[&1.name] || 0.0}})

    commands = discover_commands(robot)

    state = %State{
      robot: robot,
      robot_struct: robot_struct,
      safety_state: BB.Safety.state(robot),
      runtime_state: BB.Robot.Runtime.state(robot),
      joints: joints,
      events: [],
      parameters: BB.Parameter.list(robot, []),
      commands: commands,
      active_panel: :safety,
      scroll_offset: 0,
      show_help: false,
      confirm_force_disarm: false
    }

    {:ok, state}
  end

  @impl true
  def render(state, frame) do
    full = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Main area + status bar
    [main, status_bar_area] =
      Layout.split(full, :vertical, [
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

    panels = [
      {Panels.Safety.render(state, state.active_panel == :safety), safety_area},
      {Panels.Commands.render(state, state.active_panel == :commands), commands_area},
      {Panels.Joints.render(state, state.active_panel == :joints), joints_area},
      {Panels.Events.render(state, state.active_panel == :events), events_area},
      {Panels.Parameters.render(state, state.active_panel == :parameters), params_area},
      {Panels.StatusBar.render(state), status_bar_area}
    ]

    maybe_add_popup(panels, state, full)
  end

  @impl true
  # ── Popup intercepts ────────────────────────────────────────
  def handle_event(%ExRatatui.Event.Key{kind: "press"}, %{show_help: true} = state) do
    {:noreply, State.toggle_help(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "y", kind: "press"},
        %{confirm_force_disarm: true} = state
      ) do
    BB.Safety.force_disarm(state.robot)
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
    BB.Safety.arm(state.robot)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "d", kind: "press"}, state) do
    BB.Safety.disarm(state.robot)
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
    {:noreply, State.scroll_down(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{active_panel: :joints} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.scroll_up(state)}
  end

  # ── Catch-all ──────────────────────────────────────────────
  def handle_event(_event, state) do
    {:noreply, state}
  end

  # ── PubSub messages ────────────────────────────────────────

  @impl true
  def handle_info({:bb, [:state_machine | _] = path, msg}, state) do
    safety_state = BB.Safety.state(state.robot)
    runtime_state = BB.Robot.Runtime.state(state.robot)

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
    parameters = BB.Parameter.list(state.robot, [])

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

  defp maybe_add_popup(panels, %{show_help: true}, full) do
    panels ++ [{Panels.Help.render(), full}]
  end

  defp maybe_add_popup(panels, %{confirm_force_disarm: true}, full) do
    panels ++ [{Panels.ForceDisarm.render(), full}]
  end

  defp maybe_add_popup(panels, _state, _full), do: panels

  defp discover_commands(robot) do
    if Code.ensure_loaded?(BB.Dsl.Info) and function_exported?(BB.Dsl.Info, :commands, 1) do
      BB.Dsl.Info.commands(robot)
    else
      []
    end
  rescue
    _ -> []
  end

  defp execute_selected_command(%State{commands: commands, command_selected: idx} = state) do
    case Enum.at(commands, idx) do
      nil ->
        {:noreply, state}

      cmd ->
        if Panels.Commands.command_ready?(cmd, state.runtime_state) and
             state.executing_command == nil do
          tui_pid = self()

          pid =
            spawn(fn ->
              result = BB.Robot.Runtime.execute(state.robot, cmd.name, %{})

              case result do
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
            end)

          {:noreply, State.start_command(state, pid)}
        else
          {:noreply, state}
        end
    end
  end
end
