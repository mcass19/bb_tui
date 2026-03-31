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
    confirm_force_disarm: false,
    throbber_step: 0,
    events_paused: false,
    command_selected: 0,
    command_result: nil,
    executing_command: nil
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
          confirm_force_disarm: boolean(),
          throbber_step: non_neg_integer(),
          events_paused: boolean(),
          command_selected: non_neg_integer(),
          command_result: {:ok, term()} | {:error, term()} | nil,
          executing_command: pid() | nil
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
    %{state | show_help: !state.show_help}
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
end
