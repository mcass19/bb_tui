defmodule BB.TUI.State do
  @moduledoc """
  State struct and pure update functions for the BB TUI dashboard.

  All state transitions are pure functions — no side effects, no process
  communication. The `BB.TUI.App` module handles IO and delegates here
  for state changes.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :safety, show_help: false}
      iex> state.active_panel
      :safety
  """

  @max_events 100

  defstruct [
    :robot,
    :robot_struct,
    :safety_state,
    :runtime_state,
    :joints,
    :parameters,
    :commands,
    :command_input,
    events: [],
    active_panel: :safety,
    scroll_offset: 0,
    show_help: false,
    help_scroll_offset: 0,
    confirm_force_disarm: false,
    throbber_step: 0,
    events_paused: false,
    show_event_detail: false,
    command_selected: 0,
    command_result: nil,
    executing_command: nil,
    joint_selected: 0,
    param_selected: 0
  ]

  @type t :: %__MODULE__{
          robot: module(),
          robot_struct: term(),
          safety_state: :armed | :disarmed | :disarming | :error,
          runtime_state: atom(),
          joints: %{atom() => %{position: float(), joint: term()}},
          events: [{DateTime.t(), list(), term()}],
          parameters: [{list(), term()}],
          commands: [term()],
          command_input: reference() | nil,
          active_panel: :safety | :commands | :joints | :events | :parameters,
          scroll_offset: non_neg_integer(),
          show_help: boolean(),
          help_scroll_offset: non_neg_integer(),
          confirm_force_disarm: boolean(),
          throbber_step: non_neg_integer(),
          events_paused: boolean(),
          show_event_detail: boolean(),
          command_selected: non_neg_integer(),
          command_result: {:ok, term()} | {:error, term()} | nil,
          executing_command: pid() | nil,
          joint_selected: non_neg_integer(),
          param_selected: non_neg_integer()
        }

  @panels [:safety, :commands, :joints, :events, :parameters]

  @doc """
  Returns the ordered list of panel names for tab cycling.

  ## Examples

      iex> BB.TUI.State.panels()
      [:safety, :commands, :joints, :events, :parameters]
  """
  @spec panels() :: [atom()]
  def panels, do: @panels

  @doc """
  Cycles the active panel to the next one in order.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :safety}
      iex> BB.TUI.State.cycle_panel(state).active_panel
      :commands

      iex> state = %BB.TUI.State{active_panel: :parameters}
      iex> BB.TUI.State.cycle_panel(state).active_panel
      :safety
  """
  @spec cycle_panel(t()) :: t()
  def cycle_panel(%__MODULE__{active_panel: current} = state) do
    idx = Enum.find_index(@panels, &(&1 == current))
    next = Enum.at(@panels, rem(idx + 1, length(@panels)))
    %{state | active_panel: next}
  end

  @doc """
  Toggles the help overlay.

  ## Examples

      iex> state = %BB.TUI.State{show_help: false}
      iex> BB.TUI.State.toggle_help(state).show_help
      true

      iex> state = %BB.TUI.State{show_help: true}
      iex> BB.TUI.State.toggle_help(state).show_help
      false
  """
  @spec toggle_help(t()) :: t()
  def toggle_help(%__MODULE__{} = state) do
    %{state | show_help: !state.show_help, help_scroll_offset: 0}
  end

  @doc """
  Scrolls the help popup down by one line.

  ## Examples

      iex> state = %BB.TUI.State{show_help: true, help_scroll_offset: 0}
      iex> BB.TUI.State.scroll_help_down(state).help_scroll_offset
      1
  """
  @spec scroll_help_down(t()) :: t()
  def scroll_help_down(%__MODULE__{help_scroll_offset: offset} = state) do
    %{state | help_scroll_offset: offset + 1}
  end

  @doc """
  Scrolls the help popup up by one line.

  ## Examples

      iex> state = %BB.TUI.State{show_help: true, help_scroll_offset: 0}
      iex> BB.TUI.State.scroll_help_up(state).help_scroll_offset
      0

      iex> state = %BB.TUI.State{show_help: true, help_scroll_offset: 5}
      iex> BB.TUI.State.scroll_help_up(state).help_scroll_offset
      4
  """
  @spec scroll_help_up(t()) :: t()
  def scroll_help_up(%__MODULE__{help_scroll_offset: offset} = state) do
    %{state | help_scroll_offset: max(offset - 1, 0)}
  end

  @doc """
  Shows the force disarm confirmation popup.

  ## Examples

      iex> state = %BB.TUI.State{confirm_force_disarm: false}
      iex> BB.TUI.State.show_force_disarm(state).confirm_force_disarm
      true
  """
  @spec show_force_disarm(t()) :: t()
  def show_force_disarm(%__MODULE__{} = state) do
    %{state | confirm_force_disarm: true}
  end

  @doc """
  Dismisses the force disarm confirmation popup.

  ## Examples

      iex> state = %BB.TUI.State{confirm_force_disarm: true}
      iex> BB.TUI.State.dismiss_force_disarm(state).confirm_force_disarm
      false
  """
  @spec dismiss_force_disarm(t()) :: t()
  def dismiss_force_disarm(%__MODULE__{} = state) do
    %{state | confirm_force_disarm: false}
  end

  @doc """
  Updates safety and runtime state from a state machine message.

  ## Examples

      iex> state = %BB.TUI.State{safety_state: :disarmed, runtime_state: :disarmed}
      iex> state = BB.TUI.State.update_safety(state, :armed, :idle)
      iex> {state.safety_state, state.runtime_state}
      {:armed, :idle}
  """
  @spec update_safety(t(), atom(), atom()) :: t()
  def update_safety(%__MODULE__{} = state, safety_state, runtime_state) do
    %{state | safety_state: safety_state, runtime_state: runtime_state}
  end

  @doc """
  Updates joint positions from a sensor message.

  Only updates joints that exist in the current state; unknown joint names
  are silently ignored.

  ## Examples

      iex> joints = %{shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints}
      iex> BB.TUI.State.update_positions(state, %{shoulder: 42.0}).joints.shoulder.position
      42.0
  """
  @spec update_positions(t(), %{atom() => float()}) :: t()
  def update_positions(%__MODULE__{joints: joints} = state, new_positions) do
    updated_joints =
      Map.new(joints, fn {name, joint_data} ->
        case Map.fetch(new_positions, name) do
          {:ok, position} -> {name, %{joint_data | position: position}}
          :error -> {name, joint_data}
        end
      end)

    %{state | joints: updated_joints}
  end

  @doc """
  Updates parameters from a parameter change message.

  ## Examples

      iex> state = %BB.TUI.State{parameters: []}
      iex> BB.TUI.State.update_parameters(state, [{[:speed], 100}]).parameters
      [{[:speed], 100}]
  """
  @spec update_parameters(t(), [{list(), term()}]) :: t()
  def update_parameters(%__MODULE__{} = state, parameters) do
    %{state | parameters: parameters}
  end

  @doc """
  Appends an event to the event list, capping at #{@max_events}.

  Events are prepended (newest first) and the list is trimmed to
  #{@max_events} entries. When events are paused, the event is not appended.
  """
  @spec append_event(t(), list(), term()) :: t()
  def append_event(%__MODULE__{events_paused: true} = state, _path, _message), do: state

  def append_event(%__MODULE__{events: events} = state, path, message) do
    event = {DateTime.utc_now(), path, message}
    %{state | events: Enum.take([event | events], @max_events)}
  end

  @doc """
  Scrolls the event panel down (newer events).

  ## Examples

      iex> events = [{~U[2026-01-01 00:00:00Z], [:test], %{}}]
      iex> state = %BB.TUI.State{events: events, scroll_offset: 0}
      iex> BB.TUI.State.scroll_down(state).scroll_offset
      0
  """
  @spec scroll_down(t()) :: t()
  def scroll_down(%__MODULE__{scroll_offset: offset, events: events} = state) do
    max_offset = max(length(events) - 1, 0)
    %{state | scroll_offset: min(offset + 1, max_offset)}
  end

  @doc """
  Scrolls the event panel up (older events).

  ## Examples

      iex> state = %BB.TUI.State{scroll_offset: 0}
      iex> BB.TUI.State.scroll_up(state).scroll_offset
      0

      iex> state = %BB.TUI.State{scroll_offset: 5}
      iex> BB.TUI.State.scroll_up(state).scroll_offset
      4
  """
  @spec scroll_up(t()) :: t()
  def scroll_up(%__MODULE__{scroll_offset: offset} = state) do
    %{state | scroll_offset: max(offset - 1, 0)}
  end

  @doc """
  Increments the throbber animation step.

  ## Examples

      iex> state = %BB.TUI.State{throbber_step: 3}
      iex> BB.TUI.State.tick_throbber(state).throbber_step
      4
  """
  @spec tick_throbber(t()) :: t()
  def tick_throbber(%__MODULE__{throbber_step: step} = state) do
    %{state | throbber_step: step + 1}
  end

  @doc """
  Toggles the event stream pause state.

  ## Examples

      iex> state = %BB.TUI.State{events_paused: false}
      iex> BB.TUI.State.toggle_events_pause(state).events_paused
      true

      iex> state = %BB.TUI.State{events_paused: true}
      iex> BB.TUI.State.toggle_events_pause(state).events_paused
      false
  """
  @spec toggle_events_pause(t()) :: t()
  def toggle_events_pause(%__MODULE__{} = state) do
    %{state | events_paused: !state.events_paused}
  end

  @doc """
  Clears all events and resets scroll offset.

  ## Examples

      iex> events = [{~U[2026-01-01 00:00:00Z], [:test], %{}}]
      iex> state = %BB.TUI.State{events: events, scroll_offset: 5}
      iex> new_state = BB.TUI.State.clear_events(state)
      iex> {new_state.events, new_state.scroll_offset}
      {[], 0}
  """
  @spec clear_events(t()) :: t()
  def clear_events(%__MODULE__{} = state) do
    %{state | events: [], scroll_offset: 0}
  end

  @doc """
  Toggles the event detail popup for the currently selected event.

  ## Examples

      iex> state = %BB.TUI.State{show_event_detail: false}
      iex> BB.TUI.State.toggle_event_detail(state).show_event_detail
      true
  """
  @spec toggle_event_detail(t()) :: t()
  def toggle_event_detail(%__MODULE__{} = state) do
    %{state | show_event_detail: !state.show_event_detail}
  end

  @doc """
  Dismisses the event detail popup.

  ## Examples

      iex> state = %BB.TUI.State{show_event_detail: true}
      iex> BB.TUI.State.dismiss_event_detail(state).show_event_detail
      false
  """
  @spec dismiss_event_detail(t()) :: t()
  def dismiss_event_detail(%__MODULE__{} = state) do
    %{state | show_event_detail: false}
  end

  @doc """
  Returns the currently selected event, or nil if no events.

  ## Examples

      iex> events = [{~U[2026-01-01 00:00:00Z], [:test], %{payload: :ok}}]
      iex> state = %BB.TUI.State{events: events, scroll_offset: 0}
      iex> {_, [:test], _} = BB.TUI.State.selected_event(state)

      iex> state = %BB.TUI.State{events: [], scroll_offset: 0}
      iex> BB.TUI.State.selected_event(state)
      nil
  """
  @spec selected_event(t()) :: {DateTime.t(), list(), term()} | nil
  def selected_event(%__MODULE__{events: events, scroll_offset: offset}) do
    Enum.at(events, offset)
  end

  @doc """
  Selects the next command in the list.

  ## Examples

      iex> state = %BB.TUI.State{command_selected: 0, commands: [%{name: :a}, %{name: :b}]}
      iex> BB.TUI.State.select_next_command(state).command_selected
      1

      iex> state = %BB.TUI.State{command_selected: 1, commands: [%{name: :a}, %{name: :b}]}
      iex> BB.TUI.State.select_next_command(state).command_selected
      1
  """
  @spec select_next_command(t()) :: t()
  def select_next_command(%__MODULE__{command_selected: idx, commands: cmds} = state) do
    max_idx = max(length(cmds) - 1, 0)
    %{state | command_selected: min(idx + 1, max_idx)}
  end

  @doc """
  Selects the previous command in the list.

  ## Examples

      iex> state = %BB.TUI.State{command_selected: 1}
      iex> BB.TUI.State.select_prev_command(state).command_selected
      0

      iex> state = %BB.TUI.State{command_selected: 0}
      iex> BB.TUI.State.select_prev_command(state).command_selected
      0
  """
  @spec select_prev_command(t()) :: t()
  def select_prev_command(%__MODULE__{command_selected: idx} = state) do
    %{state | command_selected: max(idx - 1, 0)}
  end

  @doc """
  Sets the command execution result.

  ## Examples

      iex> state = %BB.TUI.State{command_result: nil, executing_command: self()}
      iex> new_state = BB.TUI.State.set_command_result(state, {:ok, :done})
      iex> {new_state.command_result, new_state.executing_command}
      {{:ok, :done}, nil}
  """
  @spec set_command_result(t(), {:ok, term()} | {:error, term()}) :: t()
  def set_command_result(%__MODULE__{} = state, result) do
    %{state | command_result: result, executing_command: nil}
  end

  @doc """
  Marks a command as currently executing.

  ## Examples

      iex> state = %BB.TUI.State{executing_command: nil, command_result: {:ok, :old}}
      iex> pid = self()
      iex> new_state = BB.TUI.State.start_command(state, pid)
      iex> {new_state.executing_command, new_state.command_result}
      {pid, nil}
  """
  @spec start_command(t(), pid()) :: t()
  def start_command(%__MODULE__{} = state, pid) do
    %{state | executing_command: pid, command_result: nil}
  end

  # ── Joint control ──────────────────────────────────────────

  @doc """
  Returns sorted joint names, matching the render order of the joints panel.

  ## Examples

      iex> joints = %{elbow: %{joint: %{}, position: 0.0}, shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints}
      iex> BB.TUI.State.sorted_joint_names(state)
      [:elbow, :shoulder]
  """
  @spec sorted_joint_names(t()) :: [atom()]
  def sorted_joint_names(%__MODULE__{joints: joints}) do
    joints |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns the name of the currently selected joint, or nil if no joints exist.

  ## Examples

      iex> joints = %{elbow: %{joint: %{}, position: 0.0}, shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints, joint_selected: 1}
      iex> BB.TUI.State.selected_joint_name(state)
      :shoulder

      iex> state = %BB.TUI.State{joints: %{}, joint_selected: 0}
      iex> BB.TUI.State.selected_joint_name(state)
      nil
  """
  @spec selected_joint_name(t()) :: atom() | nil
  def selected_joint_name(%__MODULE__{} = state) do
    Enum.at(sorted_joint_names(state), state.joint_selected)
  end

  @doc """
  Selects the next joint in the sorted list.

  ## Examples

      iex> joints = %{a: %{joint: %{}, position: 0.0}, b: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints, joint_selected: 0}
      iex> BB.TUI.State.select_next_joint(state).joint_selected
      1

      iex> joints = %{a: %{joint: %{}, position: 0.0}, b: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints, joint_selected: 1}
      iex> BB.TUI.State.select_next_joint(state).joint_selected
      1
  """
  @spec select_next_joint(t()) :: t()
  def select_next_joint(%__MODULE__{joints: joints, joint_selected: idx} = state) do
    max_idx = max(map_size(joints) - 1, 0)
    %{state | joint_selected: min(idx + 1, max_idx)}
  end

  @doc """
  Selects the previous joint in the sorted list.

  ## Examples

      iex> state = %BB.TUI.State{joints: %{a: %{joint: %{}, position: 0.0}}, joint_selected: 1}
      iex> BB.TUI.State.select_prev_joint(state).joint_selected
      0

      iex> state = %BB.TUI.State{joints: %{a: %{joint: %{}, position: 0.0}}, joint_selected: 0}
      iex> BB.TUI.State.select_prev_joint(state).joint_selected
      0
  """
  @spec select_prev_joint(t()) :: t()
  def select_prev_joint(%__MODULE__{joint_selected: idx} = state) do
    %{state | joint_selected: max(idx - 1, 0)}
  end

  @doc """
  Updates the position of a specific joint in state.

  ## Examples

      iex> joints = %{shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints}
      iex> BB.TUI.State.set_joint_position(state, :shoulder, 1.5).joints.shoulder.position
      1.5
  """
  @spec set_joint_position(t(), atom(), float()) :: t()
  def set_joint_position(%__MODULE__{joints: joints} = state, name, position) do
    case Map.fetch(joints, name) do
      {:ok, joint_data} ->
        %{state | joints: Map.put(joints, name, %{joint_data | position: position})}

      :error ->
        state
    end
  end

  @doc """
  Computes the step size for a joint based on its limits.

  Returns `(upper - lower) / 100` for joints with limits, or a default
  step of `π/50` (~3.6°) for unlimited joints.

  ## Examples

      iex> BB.TUI.State.joint_step(%{limits: %{lower: -1.0, upper: 1.0}})
      0.02

      iex> BB.TUI.State.joint_step(%{type: :continuous})
      :math.pi() / 50
  """
  @spec joint_step(map()) :: float()
  def joint_step(joint) do
    case joint_limits(joint) do
      {lower, upper} when upper > lower -> (upper - lower) / 100
      _ -> :math.pi() / 50
    end
  end

  @doc """
  Clamps a position value within a joint's limits.

  Returns the position unchanged if the joint has no limits.

  ## Examples

      iex> BB.TUI.State.clamp_position(2.0, %{limits: %{lower: -1.0, upper: 1.0}})
      1.0

      iex> BB.TUI.State.clamp_position(-2.0, %{limits: %{lower: -1.0, upper: 1.0}})
      -1.0

      iex> BB.TUI.State.clamp_position(99.0, %{type: :continuous})
      99.0
  """
  @spec clamp_position(float(), map()) :: float()
  def clamp_position(pos, joint) do
    case joint_limits(joint) do
      {lower, upper} -> max(lower, min(upper, pos))
      _ -> pos
    end
  end

  # ── Parameter navigation ───────────────────────────────────

  @doc """
  Selects the next parameter in the sorted list.

  ## Examples

      iex> state = %BB.TUI.State{parameters: [{[:a], 1}, {[:b], 2}], param_selected: 0}
      iex> BB.TUI.State.select_next_param(state).param_selected
      1

      iex> state = %BB.TUI.State{parameters: [{[:a], 1}, {[:b], 2}], param_selected: 1}
      iex> BB.TUI.State.select_next_param(state).param_selected
      1
  """
  @spec select_next_param(t()) :: t()
  def select_next_param(%__MODULE__{param_selected: idx, parameters: params} = state) do
    max_idx = max(length(params) - 1, 0)
    %{state | param_selected: min(idx + 1, max_idx)}
  end

  @doc """
  Selects the previous parameter in the sorted list.

  ## Examples

      iex> state = %BB.TUI.State{parameters: [{[:a], 1}], param_selected: 1}
      iex> BB.TUI.State.select_prev_param(state).param_selected
      0

      iex> state = %BB.TUI.State{parameters: [{[:a], 1}], param_selected: 0}
      iex> BB.TUI.State.select_prev_param(state).param_selected
      0
  """
  @spec select_prev_param(t()) :: t()
  def select_prev_param(%__MODULE__{param_selected: idx} = state) do
    %{state | param_selected: max(idx - 1, 0)}
  end

  @doc """
  Returns the currently selected parameter as `{path, value}`, or nil.

  Parameters are sorted by path to match the render order.

  ## Examples

      iex> state = %BB.TUI.State{parameters: [{[:b], 2}, {[:a], 1}], param_selected: 0}
      iex> BB.TUI.State.selected_param(state)
      {[:a], 1}

      iex> state = %BB.TUI.State{parameters: [], param_selected: 0}
      iex> BB.TUI.State.selected_param(state)
      nil
  """
  @spec selected_param(t()) :: {list(), term()} | nil
  def selected_param(%__MODULE__{parameters: params, param_selected: idx}) do
    params
    |> Enum.sort_by(fn {path, _} -> path end)
    |> Enum.at(idx)
  end

  # ── Joint limit proximity ────────────────────────────────────

  @warning_threshold 0.15
  @danger_threshold 0.05

  @doc """
  Returns the proximity of a joint position to its nearest limit.

  Returns `:danger` when within #{@danger_threshold * 100}% of a limit,
  `:warning` when within #{@warning_threshold * 100}% of a limit,
  or `:normal` otherwise.

  Joints without limits always return `:normal`.

  ## Examples

      iex> joint = %{limits: %{lower: -1.0, upper: 1.0}}
      iex> BB.TUI.State.limit_proximity(0.0, joint)
      :normal

      iex> joint = %{limits: %{lower: -1.0, upper: 1.0}}
      iex> BB.TUI.State.limit_proximity(0.75, joint)
      :warning

      iex> joint = %{limits: %{lower: -1.0, upper: 1.0}}
      iex> BB.TUI.State.limit_proximity(0.96, joint)
      :danger

      iex> joint = %{limits: %{lower: -1.0, upper: 1.0}}
      iex> BB.TUI.State.limit_proximity(-0.96, joint)
      :danger

      iex> BB.TUI.State.limit_proximity(99.0, %{type: :continuous})
      :normal
  """
  @spec limit_proximity(number() | nil, map()) :: :normal | :warning | :danger
  def limit_proximity(nil, _joint), do: :normal

  def limit_proximity(pos, joint) do
    case joint_limits(joint) do
      {lower, upper} when upper > lower ->
        range = upper - lower
        dist_to_nearest = min((pos - lower) / range, (upper - pos) / range)

        cond do
          dist_to_nearest <= @danger_threshold -> :danger
          dist_to_nearest <= @warning_threshold -> :warning
          true -> :normal
        end

      _ ->
        :normal
    end
  end

  @doc false
  @spec joint_limits(map()) :: {number(), number()} | nil
  def joint_limits(%{limits: %{lower: lower, upper: upper}})
      when not is_nil(lower) and not is_nil(upper),
      do: {lower, upper}

  def joint_limits(_), do: nil
end
