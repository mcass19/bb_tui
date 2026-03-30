defmodule BB.TUI.App do
  @moduledoc """
  Main TUI application using `ExRatatui.App` behaviour.

  Renders the dashboard layout and handles keyboard events and PubSub messages
  from the BB robot. All state transitions are delegated to `BB.TUI.State`.
  """

  use ExRatatui.App

  alias BB.TUI.Panels
  alias BB.TUI.State
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

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

    state = %State{
      robot: robot,
      robot_struct: robot_struct,
      safety_state: BB.Safety.state(robot),
      runtime_state: BB.Robot.Runtime.state(robot),
      joints: joints,
      events: [],
      parameters: BB.Parameter.list(robot, []),
      commands: [],
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

    [top, bottom, status] =
      Layout.split(full, :vertical, [
        {:percentage, 40},
        {:min, 5},
        {:length, 1}
      ])

    [safety_area, runtime_area, joints_area] =
      Layout.split(top, :horizontal, [
        {:percentage, 20},
        {:percentage, 20},
        {:percentage, 60}
      ])

    [events_area, commands_area] =
      Layout.split(bottom, :horizontal, [
        {:percentage, 50},
        {:percentage, 50}
      ])

    panels = [
      {Panels.Safety.render(state, state.active_panel == :safety), safety_area},
      {Panels.Runtime.render(state), runtime_area},
      {Panels.Joints.render(state, state.active_panel == :joints), joints_area},
      {Panels.Events.render(state, state.active_panel == :events), events_area},
      {Panels.Commands.render(state, state.active_panel == :commands), commands_area},
      {Panels.StatusBar.render(state), status}
    ]

    panels = maybe_add_popup(panels, state, full)
    panels
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

  # ── Panel-scoped keys ──────────────────────────────────────
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

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  # ── Helpers ────────────────────────────────────────────────

  defp maybe_add_popup(panels, %{show_help: true}, full) do
    [{Panels.Help.render(), full} | panels]
  end

  defp maybe_add_popup(panels, %{confirm_force_disarm: true}, full) do
    [{Panels.ForceDisarm.render(), full} | panels]
  end

  defp maybe_add_popup(panels, _state, _full), do: panels
end
