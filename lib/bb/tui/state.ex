defmodule BB.TUI.State do
  @moduledoc """
  State struct and pure update functions for the BB TUI dashboard.

  All state transitions are pure functions — no side effects, no process
  communication. The `BB.TUI.App` module handles IO and delegates here
  for state changes.

  High-rate-stream controls live in the `BB.TUI.State.Throttle` substruct
  (`throttle.debounce_ms`/`throttle.last_seen` back `append_event/3`'s log
  debouncing; `throttle.render_pending?`/`throttle.flush_ms` drive
  `BB.TUI.App`'s coalesced sensor re-render). See `BB.TUI.App` for the flow.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :safety, show_help: false}
      iex> state.active_panel
      :safety
  """

  alias BB.TUI.State.Events
  alias BB.TUI.State.Joints
  alias BB.TUI.State.Safety
  alias BB.TUI.State.Throttle

  @max_events 100

  defstruct [
    :robot,
    :robot_struct,
    :commands,
    node: nil,
    parameters: [],
    parameter_metadata: %{},
    parameter_tabs: [:local],
    parameter_tab_selected: 0,
    remote_parameters: %{},
    active_panel: :safety,
    show_help: false,
    help_scroll_offset: 0,
    throbber_step: 0,
    command_selected: 0,
    command_result: nil,
    executing_command: nil,
    command_edit_mode: false,
    command_focused_arg: 0,
    command_form_values: %{},
    param_selected: 0,
    events: %Events{},
    joints: %Joints{},
    safety: %Safety{},
    throttle: %Throttle{}
  ]

  @type t :: %__MODULE__{
          robot: module(),
          robot_struct: term(),
          parameters: [{list(), term()}],
          parameter_metadata: %{list() => map()},
          parameter_tabs: [:local | {:bridge, atom()}],
          parameter_tab_selected: non_neg_integer(),
          remote_parameters: %{atom() => [map()] | {:error, term()}},
          commands: [term()],
          node: node() | nil,
          active_panel: :safety | :commands | :joints | :events | :parameters,
          show_help: boolean(),
          help_scroll_offset: non_neg_integer(),
          throbber_step: non_neg_integer(),
          command_selected: non_neg_integer(),
          command_result: {:ok, term()} | {:error, term()} | nil,
          executing_command: term() | nil,
          command_edit_mode: boolean(),
          command_focused_arg: non_neg_integer(),
          command_form_values: %{atom() => %{atom() => String.t()}},
          param_selected: non_neg_integer(),
          events: Events.t(),
          joints: Joints.t(),
          safety: Safety.t(),
          throttle: Throttle.t()
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

  When `active_panel` is unknown (e.g. set out-of-band to a stale
  value), resets to the first panel.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :safety}
      iex> BB.TUI.State.cycle_panel(state).active_panel
      :commands

      iex> state = %BB.TUI.State{active_panel: :parameters}
      iex> BB.TUI.State.cycle_panel(state).active_panel
      :safety

      iex> state = %BB.TUI.State{active_panel: :unknown}
      iex> BB.TUI.State.cycle_panel(state).active_panel
      :safety
  """
  @spec cycle_panel(t()) :: t()
  def cycle_panel(%__MODULE__{active_panel: current} = state) when current in @panels do
    idx = Enum.find_index(@panels, &(&1 == current))
    next = Enum.at(@panels, rem(idx + 1, length(@panels)))
    %{state | active_panel: next}
  end

  def cycle_panel(%__MODULE__{} = state) do
    %{state | active_panel: hd(@panels)}
  end

  @doc """
  Cycles the active panel to the previous one in order (Shift+Tab).

  When `active_panel` is unknown, resets to the last panel so a stale
  state still lands somewhere navigable.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :commands}
      iex> BB.TUI.State.cycle_panel_back(state).active_panel
      :safety

      iex> state = %BB.TUI.State{active_panel: :safety}
      iex> BB.TUI.State.cycle_panel_back(state).active_panel
      :parameters

      iex> state = %BB.TUI.State{active_panel: :unknown}
      iex> BB.TUI.State.cycle_panel_back(state).active_panel
      :parameters
  """
  @spec cycle_panel_back(t()) :: t()
  def cycle_panel_back(%__MODULE__{active_panel: current} = state) when current in @panels do
    count = length(@panels)
    idx = Enum.find_index(@panels, &(&1 == current))
    prev = Enum.at(@panels, rem(idx - 1 + count, count))
    %{state | active_panel: prev}
  end

  def cycle_panel_back(%__MODULE__{} = state) do
    %{state | active_panel: List.last(@panels)}
  end

  @doc """
  Returns the 1-based number of a panel, suitable for number-key jump
  hints in panel titles and help text. Returns `nil` for unknown
  panels.

  ## Examples

      iex> BB.TUI.State.panel_number(:safety)
      1

      iex> BB.TUI.State.panel_number(:parameters)
      5

      iex> BB.TUI.State.panel_number(:unknown)
      nil
  """
  @spec panel_number(atom()) :: pos_integer() | nil
  def panel_number(panel) when panel in @panels do
    Enum.find_index(@panels, &(&1 == panel)) + 1
  end

  def panel_number(_), do: nil

  @doc """
  Returns the panel atom at a 1-based index, or `nil` when the index is
  out of range. Mirror of `panel_number/1`, used by the number-key
  jump handler.

  ## Examples

      iex> BB.TUI.State.panel_at(1)
      :safety

      iex> BB.TUI.State.panel_at(5)
      :parameters

      iex> BB.TUI.State.panel_at(9)
      nil
  """
  @spec panel_at(pos_integer()) :: atom() | nil
  def panel_at(n) when is_integer(n) and n >= 1 and n <= length(@panels) do
    Enum.at(@panels, n - 1)
  end

  def panel_at(_), do: nil

  @doc """
  Jumps directly to the named panel, leaving everything else
  unchanged. A no-op when the target isn't a known panel — so a
  stray key never silently parks the dashboard in an unreachable
  state.

  ## Examples

      iex> state = %BB.TUI.State{active_panel: :safety}
      iex> BB.TUI.State.jump_to_panel(state, :events).active_panel
      :events

      iex> state = %BB.TUI.State{active_panel: :safety}
      iex> BB.TUI.State.jump_to_panel(state, :unknown).active_panel
      :safety
  """
  @spec jump_to_panel(t(), atom()) :: t()
  def jump_to_panel(%__MODULE__{} = state, panel) when panel in @panels do
    %{state | active_panel: panel}
  end

  def jump_to_panel(%__MODULE__{} = state, _panel), do: state

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

      iex> BB.TUI.State.show_force_disarm(%BB.TUI.State{}).safety.confirm_force_disarm?
      true
  """
  @spec show_force_disarm(t()) :: t()
  def show_force_disarm(%__MODULE__{} = state) do
    put_in(state.safety.confirm_force_disarm?, true)
  end

  @doc """
  Dismisses the force disarm confirmation popup.

  ## Examples

      iex> state = %BB.TUI.State{safety: %BB.TUI.State.Safety{confirm_force_disarm?: true}}
      iex> BB.TUI.State.dismiss_force_disarm(state).safety.confirm_force_disarm?
      false
  """
  @spec dismiss_force_disarm(t()) :: t()
  def dismiss_force_disarm(%__MODULE__{} = state) do
    put_in(state.safety.confirm_force_disarm?, false)
  end

  @doc """
  Updates safety and runtime state from a state machine message.

  ## Examples

      iex> state = BB.TUI.State.update_safety(%BB.TUI.State{}, :armed, :idle)
      iex> {state.safety.state, state.safety.runtime}
      {:armed, :idle}
  """
  @spec update_safety(t(), atom(), atom()) :: t()
  def update_safety(%__MODULE__{} = state, safety_state, runtime_state) do
    %{state | safety: %{state.safety | state: safety_state, runtime: runtime_state}}
  end

  @doc """
  Updates joint positions from a sensor message.

  Only updates joints that exist in the current state; unknown joint names
  are silently ignored.

  ## Examples

      iex> entries = %{shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries}}
      iex> BB.TUI.State.update_positions(state, %{shoulder: 42.0}).joints.entries.shoulder.position
      42.0
  """
  @spec update_positions(t(), %{atom() => float()}) :: t()
  def update_positions(%__MODULE__{joints: %{entries: entries}} = state, new_positions) do
    updated =
      Map.new(entries, fn {name, joint_data} ->
        case Map.fetch(new_positions, name) do
          {:ok, position} -> {name, %{joint_data | position: position}}
          :error -> {name, joint_data}
        end
      end)

    %{state | joints: %{state.joints | entries: updated}}
  end

  @doc """
  Updates parameters from a parameter list.

  `BB.Parameter.list/2` returns `{path, metadata}` tuples where metadata
  is a map carrying `:value` plus schema-derived fields like `:type`,
  `:doc`, and `:default`. The plain value is mirrored into
  `state.parameters` so navigation code keeps working with simple
  `{path, value}` tuples, while the rest of the metadata is stashed in
  `state.parameter_metadata` keyed by path. Plain-value inputs (no
  metadata map) leave the metadata side-channel untouched for that path.

  ## Examples

      iex> state = %BB.TUI.State{parameters: []}
      iex> next = BB.TUI.State.update_parameters(state, [{[:speed], %{value: 100, type: :integer, doc: "rpm"}}])
      iex> next.parameters
      [{[:speed], 100}]
      iex> next.parameter_metadata
      %{[:speed] => %{type: :integer, doc: "rpm", default: nil}}

      iex> state = %BB.TUI.State{parameters: []}
      iex> BB.TUI.State.update_parameters(state, [{[:speed], 42}]).parameters
      [{[:speed], 42}]
  """
  @spec update_parameters(t(), [{list(), term()}]) :: t()
  def update_parameters(%__MODULE__{} = state, parameters) do
    {params, metadata} =
      Enum.map_reduce(parameters, %{}, fn
        {path, %{value: value} = meta}, acc ->
          {{path, value}, Map.put(acc, path, extract_metadata(meta))}

        {path, value}, acc ->
          {{path, value}, acc}
      end)

    %{state | parameters: params, parameter_metadata: metadata}
  end

  defp extract_metadata(meta) do
    %{
      type: Map.get(meta, :type),
      doc: Map.get(meta, :doc),
      default: Map.get(meta, :default)
    }
  end

  @doc """
  Appends an event to the event list, capping at #{@max_events}.

  Events are prepended (newest first) and the list is trimmed to
  #{@max_events} entries. When events are paused, the event is dropped.

  Under high-rate streams, a repeat of the same `{path, payload-type}` seen
  within `throttle.debounce_ms` (default 1s) is dropped so a fast sensor
  cannot flood the log; distinct paths or payload types always pass through.
  A debounce window of `0` disables this.
  """
  @spec append_event(t(), list(), term()) :: t()
  def append_event(%__MODULE__{events: %{paused?: true}} = state, _path, _message), do: state

  def append_event(
        %__MODULE__{events: %{list: list} = events, throttle: throttle} = state,
        path,
        message
      ) do
    key = event_debounce_key(path, message)
    now = System.monotonic_time(:millisecond)

    if event_debounced?(throttle.last_seen, key, now, throttle.debounce_ms) do
      state
    else
      event = {event_timestamp(message), path, message}

      %{
        state
        | events: %{events | list: Enum.take([event | list], @max_events)},
          throttle: %{throttle | last_seen: Map.put(throttle.last_seen, key, now)}
      }
    end
  end

  @doc false
  # Pure debounce predicate, split out so the time-dependent window logic can
  # be unit-tested with explicit timestamps. `append_event/3` calls it with
  # `System.monotonic_time(:millisecond)`.
  @spec event_debounced?(map(), {list(), term()}, integer(), non_neg_integer()) :: boolean()
  def event_debounced?(last_seen, key, now, window_ms) do
    case Map.get(last_seen, key) do
      nil -> false
      last -> now - last < window_ms
    end
  end

  @doc false
  # Debounce identity for an event: the publish path plus the payload's struct
  # module (or `:map` for a plain map, or the bare term otherwise). Keying on
  # type — not value — means a high-rate sensor emitting the same struct on the
  # same path collapses to one log row per window, while distinct paths/types
  # always pass through.
  @spec event_debounce_key(list(), term()) :: {list(), term()}
  def event_debounce_key(path, message), do: {path, payload_type(message)}

  defp payload_type(%{payload: payload}), do: payload_type(payload)
  defp payload_type(%_struct{} = value), do: value.__struct__
  defp payload_type(value) when is_map(value), do: :map
  defp payload_type(value), do: value

  # Prefer the wall_time carried on %BB.Message{} so timestamps in the
  # events panel reflect when the publisher fired, not when this process
  # observed the message. Plain-map payloads (e.g. ad-hoc `BB.publish/3`
  # without `BB.Message.new/2`) fall back to `DateTime.utc_now/0` and
  # therefore look fresh on every reconnect — use BB.Message.new/2 to
  # preserve causality across distribution.
  defp event_timestamp(%BB.Message{wall_time: wall_time}) when is_integer(wall_time) do
    DateTime.from_unix!(wall_time, :nanosecond)
  end

  defp event_timestamp(_message), do: DateTime.utc_now()

  @doc """
  Scrolls the event panel down (newer events).

  ## Examples

      iex> list = [{~U[2026-01-01 00:00:00Z], [:test], %{}}]
      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{list: list, scroll_offset: 0}}
      iex> BB.TUI.State.scroll_down(state).events.scroll_offset
      0
  """
  @spec scroll_down(t()) :: t()
  def scroll_down(%__MODULE__{events: %{scroll_offset: offset, list: list} = events} = state) do
    max_offset = max(length(list) - 1, 0)
    %{state | events: %{events | scroll_offset: min(offset + 1, max_offset)}}
  end

  @doc """
  Scrolls the event panel up (older events).

  ## Examples

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{scroll_offset: 0}}
      iex> BB.TUI.State.scroll_up(state).events.scroll_offset
      0

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{scroll_offset: 5}}
      iex> BB.TUI.State.scroll_up(state).events.scroll_offset
      4
  """
  @spec scroll_up(t()) :: t()
  def scroll_up(%__MODULE__{events: %{scroll_offset: offset} = events} = state) do
    %{state | events: %{events | scroll_offset: max(offset - 1, 0)}}
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
  Flags that sensor-driven state changed and a coalesced re-render is due.

  The reducer returns `render?: false` for sensor messages and sets this
  flag; `BB.TUI.App`'s subscriptions callback then arms the one-shot
  `:sensor_flush` tick that performs the single batched render.

      iex> BB.TUI.State.mark_render_pending(%BB.TUI.State{}).throttle.render_pending?
      true
  """
  @spec mark_render_pending(t()) :: t()
  def mark_render_pending(%__MODULE__{} = state), do: put_in(state.throttle.render_pending?, true)

  @doc """
  Clears the pending-render flag once the coalesced frame has been rendered.

      iex> state = %BB.TUI.State{throttle: %BB.TUI.State.Throttle{render_pending?: true}}
      iex> BB.TUI.State.clear_render_pending(state).throttle.render_pending?
      false
  """
  @spec clear_render_pending(t()) :: t()
  def clear_render_pending(%__MODULE__{} = state),
    do: put_in(state.throttle.render_pending?, false)

  @doc """
  Toggles the event stream pause state.

  ## Examples

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{paused?: false}}
      iex> BB.TUI.State.toggle_events_pause(state).events.paused?
      true

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{paused?: true}}
      iex> BB.TUI.State.toggle_events_pause(state).events.paused?
      false
  """
  @spec toggle_events_pause(t()) :: t()
  def toggle_events_pause(%__MODULE__{events: events} = state) do
    %{state | events: %{events | paused?: !events.paused?}}
  end

  @doc """
  Clears all events and resets scroll offset.

  ## Examples

      iex> list = [{~U[2026-01-01 00:00:00Z], [:test], %{}}]
      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{list: list, scroll_offset: 5}}
      iex> new_state = BB.TUI.State.clear_events(state)
      iex> {new_state.events.list, new_state.events.scroll_offset}
      {[], 0}
  """
  @spec clear_events(t()) :: t()
  def clear_events(%__MODULE__{events: events} = state) do
    %{
      state
      | events: %{events | list: [], scroll_offset: 0},
        throttle: %{state.throttle | last_seen: %{}}
    }
  end

  @doc """
  Toggles the event detail popup for the currently selected event.

  ## Examples

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{show_detail?: false}}
      iex> BB.TUI.State.toggle_event_detail(state).events.show_detail?
      true
  """
  @spec toggle_event_detail(t()) :: t()
  def toggle_event_detail(%__MODULE__{events: events} = state) do
    %{state | events: %{events | show_detail?: !events.show_detail?}}
  end

  @doc """
  Dismisses the event detail popup.

  ## Examples

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{show_detail?: true}}
      iex> BB.TUI.State.dismiss_event_detail(state).events.show_detail?
      false
  """
  @spec dismiss_event_detail(t()) :: t()
  def dismiss_event_detail(%__MODULE__{events: events} = state) do
    %{state | events: %{events | show_detail?: false}}
  end

  @doc """
  Returns the currently selected event, or nil if no events.

  ## Examples

      iex> list = [{~U[2026-01-01 00:00:00Z], [:test], %{payload: :ok}}]
      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{list: list, scroll_offset: 0}}
      iex> {_, [:test], _} = BB.TUI.State.selected_event(state)

      iex> state = %BB.TUI.State{events: %BB.TUI.State.Events{list: [], scroll_offset: 0}}
      iex> BB.TUI.State.selected_event(state)
      nil
  """
  @spec selected_event(t()) :: {DateTime.t(), list(), term()} | nil
  def selected_event(%__MODULE__{events: %{list: list, scroll_offset: offset}}) do
    Enum.at(list, offset)
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
  Returns the currently selected command map, or `nil`.

  ## Examples

      iex> state = %BB.TUI.State{commands: [%{name: :a}, %{name: :b}], command_selected: 1}
      iex> BB.TUI.State.selected_command(state)
      %{name: :b}

      iex> BB.TUI.State.selected_command(%BB.TUI.State{commands: []})
      nil
  """
  @spec selected_command(t()) :: map() | nil
  def selected_command(%__MODULE__{commands: cmds, command_selected: idx}) do
    Enum.at(cmds, idx)
  end

  @doc """
  Enters argument-edit mode for the selected command, if it has arguments.

  No-op when the selected command has no arguments — argument-less
  commands execute directly on Enter.

  ## Examples

      iex> cmd = %{name: :move, arguments: [%{name: :angle, type: "float", default: 0.0}]}
      iex> state = %BB.TUI.State{commands: [cmd], command_selected: 0}
      iex> BB.TUI.State.enter_command_edit_mode(state).command_edit_mode
      true

      iex> cmd = %{name: :home, arguments: []}
      iex> state = %BB.TUI.State{commands: [cmd], command_selected: 0}
      iex> BB.TUI.State.enter_command_edit_mode(state).command_edit_mode
      false
  """
  @spec enter_command_edit_mode(t()) :: t()
  def enter_command_edit_mode(%__MODULE__{} = state) do
    case selected_command(state) do
      %{arguments: [_ | _]} -> %{state | command_edit_mode: true, command_focused_arg: 0}
      _ -> state
    end
  end

  @doc """
  Exits argument-edit mode. Keeps `command_form_values` intact.
  """
  @spec exit_command_edit_mode(t()) :: t()
  def exit_command_edit_mode(%__MODULE__{} = state) do
    %{state | command_edit_mode: false}
  end

  @doc """
  Focuses the next argument field, wrapping at the end.
  """
  @spec focus_next_arg(t()) :: t()
  def focus_next_arg(%__MODULE__{command_focused_arg: idx} = state) do
    case selected_command(state) do
      %{arguments: args} when args != [] ->
        %{state | command_focused_arg: rem(idx + 1, length(args))}

      _ ->
        state
    end
  end

  @doc """
  Focuses the previous argument field, wrapping at the start.
  """
  @spec focus_prev_arg(t()) :: t()
  def focus_prev_arg(%__MODULE__{command_focused_arg: idx} = state) do
    case selected_command(state) do
      %{arguments: args} when args != [] ->
        count = length(args)
        %{state | command_focused_arg: rem(idx - 1 + count, count)}

      _ ->
        state
    end
  end

  @doc """
  Returns the current string value for an argument, falling back to the
  argument's `:default` (rendered as a string).
  """
  @spec arg_value(t(), atom(), map()) :: String.t()
  def arg_value(%__MODULE__{command_form_values: form}, cmd_name, %{name: name, default: default}) do
    case form |> Map.get(cmd_name, %{}) |> Map.fetch(name) do
      {:ok, value} -> value
      :error -> default_to_string(default)
    end
  end

  @doc """
  Appends a character to the focused argument's value.
  """
  @spec append_to_focused_arg(t(), String.t()) :: t()
  def append_to_focused_arg(%__MODULE__{command_edit_mode: false} = state, _char), do: state

  def append_to_focused_arg(%__MODULE__{} = state, char) do
    update_focused_arg(state, fn current -> current <> char end)
  end

  @doc """
  Deletes the last character from the focused argument's value.
  """
  @spec backspace_focused_arg(t()) :: t()
  def backspace_focused_arg(%__MODULE__{command_edit_mode: false} = state), do: state

  def backspace_focused_arg(%__MODULE__{} = state) do
    update_focused_arg(state, fn
      "" -> ""
      str -> String.slice(str, 0, String.length(str) - 1)
    end)
  end

  @doc """
  Returns the currently-focused command argument map, or `nil` when the
  selected command has no arguments.

  ## Examples

      iex> cmd = %{name: :move, arguments: [%{name: :angle}, %{name: :side}]}
      iex> state = %BB.TUI.State{commands: [cmd], command_selected: 0, command_focused_arg: 1}
      iex> BB.TUI.State.focused_arg(state)
      %{name: :side}

      iex> BB.TUI.State.focused_arg(%BB.TUI.State{commands: []})
      nil
  """
  @spec focused_arg(t()) :: map() | nil
  def focused_arg(%__MODULE__{command_focused_arg: idx} = state) do
    case selected_command(state) do
      %{arguments: [_ | _] = args} -> Enum.at(args, idx)
      _ -> nil
    end
  end

  @doc """
  Returns the enum-value list for the focused argument when the arg is
  enum-typed (`{:in, [...]}` in the underlying Spark schema), otherwise
  `nil`.

  ## Examples

      iex> cmd = %{name: :move, arguments: [%{name: :side, enum_values: [:left, :right]}]}
      iex> state = %BB.TUI.State{commands: [cmd], command_selected: 0, command_focused_arg: 0}
      iex> BB.TUI.State.focused_arg_enum_values(state)
      [:left, :right]

      iex> cmd = %{name: :move, arguments: [%{name: :angle, enum_values: nil}]}
      iex> state = %BB.TUI.State{commands: [cmd], command_selected: 0, command_focused_arg: 0}
      iex> BB.TUI.State.focused_arg_enum_values(state)
      nil
  """
  @spec focused_arg_enum_values(t()) :: [atom()] | nil
  def focused_arg_enum_values(%__MODULE__{} = state) do
    case focused_arg(state) do
      %{enum_values: [_ | _] = values} -> values
      _ -> nil
    end
  end

  @doc """
  Cycles the focused argument to the next (or previous) value in its
  enum list. A no-op when not in edit mode or when the focused arg
  isn't enum-typed.

  Stores the chosen value as the leading-colon atom literal (`":foo"`)
  so `parsed_args_for_selected/1` decodes it back to `:foo` when the
  command executes.
  """
  @spec cycle_focused_enum(t(), :next | :prev) :: t()
  def cycle_focused_enum(%__MODULE__{command_edit_mode: false} = state, _direction), do: state

  def cycle_focused_enum(%__MODULE__{} = state, direction) do
    case focused_arg(state) do
      %{enum_values: [_ | _] = values} = arg ->
        cmd_name = selected_command(state).name
        current = parse_value(arg_value(state, cmd_name, arg))
        next_value = cycle_enum_value(values, current, direction)
        update_focused_arg(state, fn _ -> ":" <> Atom.to_string(next_value) end)

      _ ->
        state
    end
  end

  defp cycle_enum_value(values, current, direction) do
    count = length(values)
    idx = Enum.find_index(values, &(&1 == current)) || 0
    shift = if direction == :next, do: 1, else: -1
    Enum.at(values, rem(idx + shift + count, count))
  end

  defp update_focused_arg(
         %__MODULE__{command_focused_arg: idx, command_form_values: form} = state,
         fun
       ) do
    case selected_command(state) do
      %{name: cmd_name, arguments: args} when args != [] ->
        arg = Enum.at(args, idx)
        current = arg_value(state, cmd_name, arg)
        per_command = form |> Map.get(cmd_name, %{}) |> Map.put(arg.name, fun.(current))
        %{state | command_form_values: Map.put(form, cmd_name, per_command)}

      _ ->
        state
    end
  end

  defp default_to_string(nil), do: ""
  defp default_to_string(value) when is_binary(value), do: value
  defp default_to_string(value) when is_atom(value), do: ":" <> Atom.to_string(value)
  defp default_to_string(value), do: to_string(value)

  @doc """
  Returns the form values for the selected command, parsed by type.

  Mirrors `BB.LiveView.Components.Command`'s `parse_value/1`:
  `"true"`/`"false"` → boolean, `":foo"` → atom, numeric → number,
  else string.

  Falls back to `arg.default` for arguments the user has not touched.

  ## Examples

      iex> cmd = %{
      ...>   name: :move,
      ...>   arguments: [
      ...>     %{name: :angle, type: "float", default: 1.5},
      ...>     %{name: :side, type: "atom", default: :left}
      ...>   ]
      ...> }
      iex> state = %BB.TUI.State{
      ...>   commands: [cmd],
      ...>   command_selected: 0,
      ...>   command_form_values: %{move: %{angle: "2.5"}}
      ...> }
      iex> BB.TUI.State.parsed_args_for_selected(state)
      %{angle: 2.5, side: :left}
  """
  @spec parsed_args_for_selected(t()) :: map()
  def parsed_args_for_selected(%__MODULE__{} = state) do
    case selected_command(state) do
      %{name: cmd_name, arguments: args} ->
        Map.new(args, fn arg ->
          {arg.name, parse_value(arg_value(state, cmd_name, arg))}
        end)

      _ ->
        %{}
    end
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(":" <> rest = value) when byte_size(rest) > 0 do
    String.to_existing_atom(rest)
  rescue
    ArgumentError -> value
  end

  defp parse_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> value
        end
    end
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
  @spec start_command(t(), term()) :: t()
  def start_command(%__MODULE__{} = state, marker) do
    %{state | executing_command: marker, command_result: nil}
  end

  # ── Joint control ──────────────────────────────────────────

  @doc """
  Returns sorted joint names, matching the render order of the joints panel.

  ## Examples

      iex> entries = %{elbow: %{joint: %{}, position: 0.0}, shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries}}
      iex> BB.TUI.State.sorted_joint_names(state)
      [:elbow, :shoulder]
  """
  @spec sorted_joint_names(t()) :: [atom()]
  def sorted_joint_names(%__MODULE__{joints: %{entries: entries}}) do
    entries |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns the name of the currently selected joint, or nil if no joints exist.

  ## Examples

      iex> entries = %{elbow: %{joint: %{}, position: 0.0}, shoulder: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries, selected: 1}}
      iex> BB.TUI.State.selected_joint_name(state)
      :shoulder

      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: %{}, selected: 0}}
      iex> BB.TUI.State.selected_joint_name(state)
      nil
  """
  @spec selected_joint_name(t()) :: atom() | nil
  def selected_joint_name(%__MODULE__{} = state) do
    Enum.at(sorted_joint_names(state), state.joints.selected)
  end

  @doc """
  Selects the next joint in the sorted list.

  ## Examples

      iex> entries = %{a: %{joint: %{}, position: 0.0}, b: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries, selected: 0}}
      iex> BB.TUI.State.select_next_joint(state).joints.selected
      1

      iex> entries = %{a: %{joint: %{}, position: 0.0}, b: %{joint: %{}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries, selected: 1}}
      iex> BB.TUI.State.select_next_joint(state).joints.selected
      1
  """
  @spec select_next_joint(t()) :: t()
  def select_next_joint(%__MODULE__{joints: %{entries: entries, selected: idx}} = state) do
    max_idx = max(map_size(entries) - 1, 0)
    %{state | joints: %{state.joints | selected: min(idx + 1, max_idx)}}
  end

  @doc """
  Selects the previous joint in the sorted list.

  ## Examples

      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: %{a: %{joint: %{}, position: 0.0}}, selected: 1}}
      iex> BB.TUI.State.select_prev_joint(state).joints.selected
      0

      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: %{a: %{joint: %{}, position: 0.0}}, selected: 0}}
      iex> BB.TUI.State.select_prev_joint(state).joints.selected
      0
  """
  @spec select_prev_joint(t()) :: t()
  def select_prev_joint(%__MODULE__{joints: %{selected: idx}} = state) do
    %{state | joints: %{state.joints | selected: max(idx - 1, 0)}}
  end

  @doc """
  Updates the position of a specific joint in state.

  ## Examples

      iex> entries = %{shoulder: %{joint: %{}, position: 0.0, target: nil}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries}}
      iex> BB.TUI.State.set_joint_position(state, :shoulder, 1.5).joints.entries.shoulder.position
      1.5
  """
  @spec set_joint_position(t(), atom(), float()) :: t()
  def set_joint_position(%__MODULE__{joints: %{entries: entries}} = state, name, position) do
    case Map.fetch(entries, name) do
      {:ok, joint_data} ->
        %{
          state
          | joints: %{
              state.joints
              | entries: Map.put(entries, name, %{joint_data | position: position})
            }
        }

      :error ->
        state
    end
  end

  @doc """
  Records the last-commanded target position for a joint. The panel
  renders it as a secondary marker on the position bar so the operator
  can see what the joint is moving toward. Pass `nil` to clear the
  target (e.g. when the joint has reached it).

  ## Examples

      iex> entries = %{shoulder: %{joint: %{}, position: 0.0, target: nil}}
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: entries}}
      iex> BB.TUI.State.set_joint_target(state, :shoulder, 1.5).joints.entries.shoulder.target
      1.5

      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: %{}}}
      iex> BB.TUI.State.set_joint_target(state, :missing, 1.5).joints.entries
      %{}
  """
  @spec set_joint_target(t(), atom(), float() | nil) :: t()
  def set_joint_target(%__MODULE__{joints: %{entries: entries}} = state, name, target) do
    case Map.fetch(entries, name) do
      {:ok, joint_data} ->
        %{
          state
          | joints: %{
              state.joints
              | entries: Map.put(entries, name, Map.put(joint_data, :target, target))
            }
        }

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

  @doc """
  Replaces the discovered parameter tabs and resets the selected tab.

  Always keeps `:local` at the head, so cycling never lands in a state
  where no local-parameter view is reachable.

  ## Examples

      iex> state = %BB.TUI.State{}
      iex> next = BB.TUI.State.set_parameter_tabs(state, [%{name: :mavlink}])
      iex> next.parameter_tabs
      [:local, {:bridge, :mavlink}]
      iex> next.parameter_tab_selected
      0
  """
  @spec set_parameter_tabs(t(), [map()]) :: t()
  def set_parameter_tabs(%__MODULE__{} = state, bridges) do
    tabs = [:local | Enum.map(bridges, fn %{name: name} -> {:bridge, name} end)]
    %{state | parameter_tabs: tabs, parameter_tab_selected: 0, param_selected: 0}
  end

  @doc """
  Returns the currently selected parameter tab.

  ## Examples

      iex> state = %BB.TUI.State{parameter_tabs: [:local, {:bridge, :mavlink}], parameter_tab_selected: 1}
      iex> BB.TUI.State.selected_parameter_tab(state)
      {:bridge, :mavlink}

      iex> state = %BB.TUI.State{parameter_tabs: [:local], parameter_tab_selected: 0}
      iex> BB.TUI.State.selected_parameter_tab(state)
      :local
  """
  @spec selected_parameter_tab(t()) :: :local | {:bridge, atom()}
  def selected_parameter_tab(%__MODULE__{
        parameter_tabs: tabs,
        parameter_tab_selected: idx
      }) do
    Enum.at(tabs, idx, :local)
  end

  @doc """
  Cycles to the next parameter tab, wrapping back to `:local`.

  Resets `param_selected` so the new tab starts at the first row.

  ## Examples

      iex> state = %BB.TUI.State{parameter_tabs: [:local, {:bridge, :mavlink}], parameter_tab_selected: 0, param_selected: 3}
      iex> next = BB.TUI.State.cycle_parameter_tab(state)
      iex> next.parameter_tab_selected
      1
      iex> next.param_selected
      0

      iex> state = %BB.TUI.State{parameter_tabs: [:local, {:bridge, :mavlink}], parameter_tab_selected: 1}
      iex> BB.TUI.State.cycle_parameter_tab(state).parameter_tab_selected
      0

      iex> state = %BB.TUI.State{parameter_tabs: [:local], parameter_tab_selected: 0}
      iex> BB.TUI.State.cycle_parameter_tab(state).parameter_tab_selected
      0
  """
  @spec cycle_parameter_tab(t()) :: t()
  def cycle_parameter_tab(%__MODULE__{parameter_tabs: tabs} = state)
      when length(tabs) <= 1 do
    %{state | parameter_tab_selected: 0, param_selected: 0}
  end

  def cycle_parameter_tab(%__MODULE__{} = state) do
    next = rem(state.parameter_tab_selected + 1, length(state.parameter_tabs))
    %{state | parameter_tab_selected: next, param_selected: 0}
  end

  @doc """
  Stores the latest remote-parameter snapshot for a bridge.

  ## Examples

      iex> state = %BB.TUI.State{remote_parameters: %{}}
      iex> next = BB.TUI.State.put_remote_parameters(state, :mavlink, [%{id: "PITCH_P", value: 0.1}])
      iex> next.remote_parameters
      %{mavlink: [%{id: "PITCH_P", value: 0.1}]}
  """
  @spec put_remote_parameters(t(), atom(), [map()] | {:error, term()}) :: t()
  def put_remote_parameters(
        %__MODULE__{remote_parameters: existing} = state,
        bridge_name,
        payload
      ) do
    %{state | remote_parameters: Map.put(existing, bridge_name, payload)}
  end

  @doc """
  Returns the sort key used when rendering a remote parameter row.

  Bridges typically use string ids (`"PITCH_P"`), but some (`BB.Bridge`
  implementations are free to use atoms) return atom ids. Both
  normalize to a binary so the panel and the navigation index agree on
  ordering.

  ## Examples

      iex> BB.TUI.State.remote_param_id(%{id: "PITCH_P"})
      "PITCH_P"

      iex> BB.TUI.State.remote_param_id(%{id: :gain})
      "gain"

      iex> BB.TUI.State.remote_param_id(%{})
      ""
  """
  @spec remote_param_id(map()) :: String.t()
  def remote_param_id(%{id: id}) when is_binary(id), do: id
  def remote_param_id(%{id: id}), do: to_string(id)
  def remote_param_id(_), do: ""

  @doc """
  Returns the currently-focused remote parameter for the selected
  bridge tab, or `nil` when the active tab is `:local`, the bridge has
  no fetched list yet, or the fetch errored.

  Sort order matches the panel's render (`Enum.sort_by(remote_param_id/1)`).

  ## Examples

      iex> remote = [%{id: "ROLL_P", value: 0.0}, %{id: "PITCH_P", value: 0.1}]
      iex> state = %BB.TUI.State{
      ...>   parameter_tabs: [:local, {:bridge, :mavlink}],
      ...>   parameter_tab_selected: 1,
      ...>   remote_parameters: %{mavlink: remote},
      ...>   param_selected: 0
      ...> }
      iex> BB.TUI.State.selected_remote_param(state)
      %{id: "PITCH_P", value: 0.1}

      iex> state = %BB.TUI.State{parameter_tabs: [:local], parameter_tab_selected: 0}
      iex> BB.TUI.State.selected_remote_param(state)
      nil

      iex> state = %BB.TUI.State{
      ...>   parameter_tabs: [:local, {:bridge, :mavlink}],
      ...>   parameter_tab_selected: 1,
      ...>   remote_parameters: %{mavlink: {:error, :nodedown}}
      ...> }
      iex> BB.TUI.State.selected_remote_param(state)
      nil
  """
  @spec selected_remote_param(t()) :: map() | nil
  def selected_remote_param(%__MODULE__{} = state) do
    case selected_parameter_tab(state) do
      {:bridge, name} ->
        case Map.get(state.remote_parameters, name) do
          list when is_list(list) ->
            list
            |> Enum.sort_by(&remote_param_id/1)
            |> Enum.at(state.param_selected)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Returns `{min, max}` bounds for a remote parameter when the bridge
  carries them as flat `:min` / `:max` keys (matching `bb_liveview`'s
  shape), otherwise `nil`. Either bound may be `nil` to leave that side
  open.

  ## Examples

      iex> BB.TUI.State.remote_param_bounds(%{id: "X", value: 1, min: 0, max: 100})
      {0, 100}

      iex> BB.TUI.State.remote_param_bounds(%{id: "X", value: 1, min: 0})
      {0, nil}

      iex> BB.TUI.State.remote_param_bounds(%{id: "X", value: 1})
      nil
  """
  @spec remote_param_bounds(map()) :: {number() | nil, number() | nil} | nil
  def remote_param_bounds(%{} = param) do
    case {Map.get(param, :min), Map.get(param, :max)} do
      {nil, nil} -> nil
      bounds -> bounds
    end
  end

  @doc """
  Returns `{min, max}` bounds for the parameter at `path` when the
  Spark-style metadata declares them, otherwise `nil`.

  Looks at `state.parameter_metadata[path].type` for the standard
  `{head, opts}` shape used by `Spark.Options` and extracts the
  `:min` / `:max` keyword values. Either bound may be absent (returned
  as `nil`); both absent collapses to `nil` (no bounds).

  ## Examples

      iex> state = %BB.TUI.State{parameter_metadata: %{[:speed] => %{type: {:integer, [min: 0, max: 100]}}}}
      iex> BB.TUI.State.parameter_bounds(state, [:speed])
      {0, 100}

      iex> state = %BB.TUI.State{parameter_metadata: %{[:gain] => %{type: {:float, [min: 0.0]}}}}
      iex> BB.TUI.State.parameter_bounds(state, [:gain])
      {0.0, nil}

      iex> state = %BB.TUI.State{parameter_metadata: %{[:speed] => %{type: :integer}}}
      iex> BB.TUI.State.parameter_bounds(state, [:speed])
      nil

      iex> state = %BB.TUI.State{parameter_metadata: %{[:speed] => %{type: {:integer, [doc: "rpm"]}}}}
      iex> BB.TUI.State.parameter_bounds(state, [:speed])
      nil

      iex> state = %BB.TUI.State{parameter_metadata: %{}}
      iex> BB.TUI.State.parameter_bounds(state, [:unknown])
      nil
  """
  @spec parameter_bounds(t(), list()) :: {number() | nil, number() | nil} | nil
  def parameter_bounds(%__MODULE__{parameter_metadata: meta}, path) do
    case meta[path] do
      %{type: {head, opts}} when is_atom(head) and is_list(opts) ->
        case {Keyword.get(opts, :min), Keyword.get(opts, :max)} do
          {nil, nil} -> nil
          bounds -> bounds
        end

      _ ->
        nil
    end
  end

  @doc """
  Clamps a numeric value into `{min, max}` bounds. Either bound may be
  `nil` to leave that side open. A `nil` bounds tuple returns `value`
  unchanged.

  ## Examples

      iex> BB.TUI.State.clamp_to_bounds(5, {0, 10})
      5

      iex> BB.TUI.State.clamp_to_bounds(-3, {0, 10})
      0

      iex> BB.TUI.State.clamp_to_bounds(99, {0, 10})
      10

      iex> BB.TUI.State.clamp_to_bounds(99, {nil, 10})
      10

      iex> BB.TUI.State.clamp_to_bounds(-3, {0, nil})
      0

      iex> BB.TUI.State.clamp_to_bounds(7, nil)
      7
  """
  @spec clamp_to_bounds(number(), {number() | nil, number() | nil} | nil) :: number()
  def clamp_to_bounds(value, nil), do: value

  def clamp_to_bounds(value, {min, max}) do
    value
    |> apply_lower(min)
    |> apply_upper(max)
  end

  defp apply_lower(value, nil), do: value
  defp apply_lower(value, min) when value < min, do: min
  defp apply_lower(value, _min), do: value

  defp apply_upper(value, nil), do: value
  defp apply_upper(value, max) when value > max, do: max
  defp apply_upper(value, _max), do: value

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
