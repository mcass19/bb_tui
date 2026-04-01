defmodule BB.TUI.Panels.Events do
  @moduledoc """
  Events panel — displays a scrollable list of recent robot messages with
  formatted timestamps, color-coded paths, message types, and summaries.

  Press Enter on a selected event to open a detail popup showing the full
  message payload. Supports pause/resume (`p`) and clear (`c`) when focused.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.List, as: WidgetList

  @doc """
  Renders the events panel as a List widget with formatted event entries.
  Newest events appear first. Scrollable with j/k when focused.

  ## Examples

      iex> state = %BB.TUI.State{events: [], scroll_offset: 0, events_paused: false}
      iex> widget = BB.TUI.Panels.Events.render(state, false)
      iex> widget.items
      []
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{events: events, scroll_offset: offset, events_paused: paused}, focused?) do
    items = Enum.map(events, &format_event/1)

    %WidgetList{
      items: items,
      selected: if(events != [], do: offset),
      highlight_style: Theme.highlight_style(),
      block: %Block{
        title: title(length(events), paused),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Builds the panel title with event count and pause indicator.

  ## Examples

      iex> BB.TUI.Panels.Events.title(47, false)
      " Events (47) "

      iex> BB.TUI.Panels.Events.title(47, true)
      " Events (47) \u{23F8} PAUSED "

      iex> BB.TUI.Panels.Events.title(0, false)
      " Events "
  """
  @spec title(non_neg_integer(), boolean()) :: String.t()
  def title(0, false), do: " Events "
  def title(count, false), do: " Events (#{count}) "
  def title(0, true), do: " Events \u{23F8} PAUSED "
  def title(count, true), do: " Events (#{count}) \u{23F8} PAUSED "

  @doc """
  Formats a single event as a display string.

  Shows timestamp, path, and a short summary of the message payload.

  ## Examples

      iex> ts = ~U[2026-01-15 18:23:12.936Z]
      iex> BB.TUI.Panels.Events.format_event({ts, [:sensor, :simulated], %{payload: %{names: [:elbow], positions: [0.5]}}})
      "18:23:12 sensor.simulated   JointState 1 joint(s)"

      iex> ts = ~U[2026-01-15 18:23:12.000Z]
      iex> BB.TUI.Panels.Events.format_event({ts, [:state_machine], %{payload: %{from: :disarmed, to: :armed}}})
      "18:23:12 state_machine      disarmed \u{2192} armed"
  """
  @spec format_event({DateTime.t(), list(), term()}) :: String.t()
  def format_event({timestamp, path, message}) do
    time = Calendar.strftime(timestamp, "%H:%M:%S")
    path_str = path |> Enum.join(".") |> String.pad_trailing(18)
    summary = summarize(path, message)

    "#{time} #{path_str} #{summary}"
  end

  @doc """
  Formats the detail lines for an expanded event.

  Returns a list of indented strings showing the message type and payload fields.

  ## Examples

      iex> ts = ~U[2026-01-15 18:23:12.000Z]
      iex> event = {ts, [:sensor, :simulated], %{payload: %{names: [:elbow], positions: [0.5], velocities: [0.0], efforts: [0.0]}}}
      iex> details = BB.TUI.Panels.Events.format_event_details(event)
      iex> hd(details) =~ "efforts"
      true
  """
  @spec format_event_details({DateTime.t(), list(), term()}) :: [String.t()]
  def format_event_details({_timestamp, _path, message}) do
    payload = extract_payload(message)
    format_payload_lines(payload)
  end

  defp extract_payload(%{payload: %{__struct__: _} = payload}), do: payload
  defp extract_payload(%{payload: payload}) when is_map(payload), do: payload
  defp extract_payload(other), do: other

  defp format_payload_lines(%{__struct__: mod} = payload) do
    type_line = "  \u{250C} #{inspect(mod)}"

    fields =
      payload
      |> Map.from_struct()
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)

    field_lines =
      fields
      |> Enum.with_index()
      |> Enum.map(fn {{key, val}, idx} ->
        prefix = if idx == length(fields) - 1, do: "\u{2514}", else: "\u{2502}"
        label = to_string(key) |> String.pad_trailing(14)
        "  #{prefix} #{label}#{format_value(val)}"
      end)

    [type_line | field_lines]
  end

  defp format_payload_lines(payload) when is_map(payload) do
    fields = Enum.sort_by(payload, fn {k, _} -> to_string(k) end)

    fields
    |> Enum.with_index()
    |> Enum.map(fn {{key, val}, idx} ->
      prefix = if idx == length(fields) - 1, do: "\u{2514}", else: "\u{2502}"
      label = to_string(key) |> String.pad_trailing(14)
      "  #{prefix} #{label}#{format_value(val)}"
    end)
  end

  defp format_payload_lines(other) do
    ["  \u{2514} #{inspect(other, pretty: false, limit: 50)}"]
  end

  defp format_value(list) when is_list(list) do
    items =
      Enum.map(list, fn
        f when is_float(f) -> :erlang.float_to_binary(f, decimals: 3)
        other -> inspect(other)
      end)

    "[#{Enum.join(items, ", ")}]"
  end

  defp format_value(other), do: inspect(other)

  @doc """
  Produces a short summary string for an event based on its path and payload.

  ## Examples

      iex> BB.TUI.Panels.Events.summarize([:sensor, :sim], %{payload: %{names: [:a, :b], positions: [1.0, 2.0]}})
      "JointState 2 joint(s)"

      iex> BB.TUI.Panels.Events.summarize([:state_machine], %{payload: %{from: :armed, to: :idle}})
      "armed \u{2192} idle"

      iex> BB.TUI.Panels.Events.summarize([:param, :speed], %{payload: %{new_value: 42}})
      "speed = 42"

      iex> BB.TUI.Panels.Events.summarize([:unknown], %{payload: :something})
      ":something"
  """
  @spec summarize(list(), term()) :: String.t()
  def summarize([:sensor | _], %{payload: %{names: names, positions: _}}) do
    "JointState #{length(names)} joint(s)"
  end

  def summarize([:state_machine | _], %{payload: %{from: from, to: to}}) do
    "#{from} \u{2192} #{to}"
  end

  def summarize([:param | rest], %{payload: %{new_value: val}}) do
    param_name = rest |> Enum.map(&to_string/1) |> Enum.join(".")
    "#{param_name} = #{inspect(val)}"
  end

  def summarize(_path, %{payload: payload}) do
    inspect(payload, pretty: false, limit: 30)
  end

  def summarize(_path, message) do
    inspect(message, pretty: false, limit: 30)
  end
end
