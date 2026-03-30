defmodule BB.TUI.State do
  @moduledoc """
  State struct and pure update functions for the BB TUI dashboard.

  All state transitions are pure functions — no side effects, no process
  communication. The `BB.TUI.App` module handles IO and delegates here
  for state changes.
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
    throbber_step: 0
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
          active_panel: :safety | :joints | :events | :commands | :parameters,
          scroll_offset: non_neg_integer(),
          show_help: boolean(),
          confirm_force_disarm: boolean(),
          throbber_step: non_neg_integer()
        }

  @panels [:safety, :joints, :events, :commands, :parameters]

  @doc """
  Returns the ordered list of panel names for tab cycling.
  """
  @spec panels() :: [atom()]
  def panels, do: @panels

  @doc """
  Cycles the active panel to the next one in order.
  """
  @spec cycle_panel(t()) :: t()
  def cycle_panel(%__MODULE__{active_panel: current} = state) do
    idx = Enum.find_index(@panels, &(&1 == current))
    next = Enum.at(@panels, rem(idx + 1, length(@panels)))
    %{state | active_panel: next}
  end

  @doc """
  Toggles the help overlay.
  """
  @spec toggle_help(t()) :: t()
  def toggle_help(%__MODULE__{} = state) do
    %{state | show_help: !state.show_help}
  end

  @doc """
  Shows the force disarm confirmation popup.
  """
  @spec show_force_disarm(t()) :: t()
  def show_force_disarm(%__MODULE__{} = state) do
    %{state | confirm_force_disarm: true}
  end

  @doc """
  Dismisses the force disarm confirmation popup.
  """
  @spec dismiss_force_disarm(t()) :: t()
  def dismiss_force_disarm(%__MODULE__{} = state) do
    %{state | confirm_force_disarm: false}
  end

  @doc """
  Updates safety and runtime state from a state machine message.
  """
  @spec update_safety(t(), atom(), atom()) :: t()
  def update_safety(%__MODULE__{} = state, safety_state, runtime_state) do
    %{state | safety_state: safety_state, runtime_state: runtime_state}
  end

  @doc """
  Updates joint positions from a sensor message.
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
  """
  @spec update_parameters(t(), [{list(), term()}]) :: t()
  def update_parameters(%__MODULE__{} = state, parameters) do
    %{state | parameters: parameters}
  end

  @doc """
  Appends an event to the event list, capping at #{@max_events}.
  """
  @spec append_event(t(), list(), term()) :: t()
  def append_event(%__MODULE__{events: events} = state, path, message) do
    event = {DateTime.utc_now(), path, message}
    %{state | events: Enum.take([event | events], @max_events)}
  end

  @doc """
  Scrolls the event panel down (newer events).
  """
  @spec scroll_down(t()) :: t()
  def scroll_down(%__MODULE__{scroll_offset: offset, events: events} = state) do
    max_offset = max(length(events) - 1, 0)
    %{state | scroll_offset: min(offset + 1, max_offset)}
  end

  @doc """
  Scrolls the event panel up (older events).
  """
  @spec scroll_up(t()) :: t()
  def scroll_up(%__MODULE__{scroll_offset: offset} = state) do
    %{state | scroll_offset: max(offset - 1, 0)}
  end

  @doc """
  Increments the throbber animation step.
  """
  @spec tick_throbber(t()) :: t()
  def tick_throbber(%__MODULE__{throbber_step: step} = state) do
    %{state | throbber_step: step + 1}
  end
end
