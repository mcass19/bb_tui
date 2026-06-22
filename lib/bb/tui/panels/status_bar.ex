defmodule BB.TUI.Panels.StatusBar do
  @moduledoc """
  Status bar — single-line bar at the bottom of the dashboard.

  Carries (in order) the robot module, a colored safety badge, a
  runtime-state pill, a battery / power segment (only when the robot has
  published electrical telemetry), the global key hints (`Tab` / `q` /
  `?`), and a set of context-sensitive key pills for the active panel.

  Every segment is a `%ExRatatui.Text.Span{}` so each piece can carry
  its own color: the safety badge changes color with the safety
  state (green / yellow / red / dim), the battery readout colors by
  remaining charge (`BB.TUI.Theme.battery_color/1`), key labels render
  as cyan pills (red for `q`), descriptions render dim. See
  `BB.TUI.Theme.brand_title/2`, `safety_badge/1`, `key_pill/2` for
  the underlying primitives.

  The battery segment prefers `BB.Message.Sensor.BatteryState` (charge
  percentage, or voltage when percentage is unmeasured) and falls back
  to `BB.Message.Sensor.PowerState` (bus voltage) when only the latter
  is available — making the charge level visible at a glance over SSH.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.Message.Sensor.BatteryState
  alias BB.Message.Sensor.PowerState
  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the status bar as a Paragraph widget.

  ## Examples

      iex> state = %BB.TUI.State{
      ...>   robot: MyApp.Robot, ui: %BB.TUI.State.UI{active_panel: :safety},
      ...>   safety: %BB.TUI.State.Safety{state: :armed, runtime: :idle}
      ...> }
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.StatusBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "MyApp.Robot"
      true

      iex> state = %BB.TUI.State{
      ...>   robot: MyApp.Robot, ui: %BB.TUI.State.UI{active_panel: :safety},
      ...>   safety: %BB.TUI.State.Safety{state: :armed, runtime: :idle}
      ...> }
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.StatusBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "ARMED"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{} = state) do
    # No bg on the paragraph itself — `dim_span/1` paints `:dark_gray`
    # text, so a `bg: :dark_gray` strip would make every label
    # disappear. The pills carry the visual identity instead.
    %Paragraph{text: line(state)}
  end

  defp line(%State{} = state) do
    spans =
      [
        %Span{
          content: " #{inspect(state.robot)} ",
          style: %Style{fg: :white, modifiers: [:bold]}
        },
        Theme.dim_span("│"),
        %Span{content: " ", style: %Style{}},
        Theme.safety_badge(state.safety.state),
        %Span{content: " ", style: %Style{}},
        Theme.dim_span("│"),
        %Span{content: " ", style: %Style{}},
        runtime_pill(state.safety.runtime)
      ] ++
        power_spans(state) ++
        observed_spans(state) ++
        [%Span{content: "  ", style: %Style{}}] ++
        key_hints(state)

    %Line{spans: spans}
  end

  # Consumer-renderer readout: the freshest observed entry (max `meta.seq`),
  # rendered as an at-a-glance segment so a renderer-fed dashboard surfaces a
  # live value even when its data never reaches the joints/sensor panels.
  # Returns `[]` (no segment, no separator) until a renderer populates
  # `state.observed`. Stale entries (`meta.freshness == :stale`) dim. The bar
  # reads only the generic `display`/`meta` the renderer produced — no struct
  # knowledge.
  defp observed_spans(%State{observed: observed}) when map_size(observed) > 0 do
    {_slot, entry} =
      Enum.max_by(observed, fn {_slot, %{meta: meta}} -> Map.get(meta, :seq, 0) end)

    [
      %Span{content: " ", style: %Style{}},
      Theme.dim_span("│"),
      %Span{content: " ", style: %Style{}},
      observed_span(entry)
    ]
  end

  defp observed_spans(_state), do: []

  defp observed_span(%{display: display, meta: meta}) do
    fresh? = Map.get(meta, :freshness) != :stale

    style =
      if fresh? do
        %Style{fg: Theme.cyan(), modifiers: [:bold]}
      else
        %Style{fg: Theme.dim_text()}
      end

    mark = if fresh?, do: "\u{1F441}", else: "\u{26A0}"
    %Span{content: "#{mark} #{observed_label(display)}", style: style}
  end

  defp observed_label(%{label: label}) when is_binary(label), do: label
  defp observed_label(display), do: inspect(display)

  defp runtime_pill(runtime_state) do
    %Span{
      content: " #{runtime_state} ",
      style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
    }
  end

  # Battery wins over a bare power reading when both are present — charge
  # percentage is the more actionable number. Returns `[]` (no segment, no
  # separator) until the robot publishes electrical telemetry.
  defp power_spans(%State{power: %{battery: %BatteryState{} = battery}}) do
    power_segment(battery_span(battery))
  end

  defp power_spans(%State{power: %{power: %PowerState{} = reading}}) do
    power_segment(power_span(reading))
  end

  defp power_spans(_state), do: []

  defp power_segment(content_span) do
    [
      %Span{content: " ", style: %Style{}},
      Theme.dim_span("│"),
      %Span{content: " ", style: %Style{}},
      content_span
    ]
  end

  defp battery_span(%BatteryState{percentage: percentage} = battery) when is_number(percentage) do
    level = round(percentage * 100)

    %Span{
      content: "🔋 #{level}%#{charging_suffix(battery.power_supply_status)}",
      style: %Style{fg: Theme.battery_color(level), modifiers: [:bold]}
    }
  end

  defp battery_span(%BatteryState{voltage: voltage}) do
    %Span{
      content: "🔋 #{format_voltage(voltage)}",
      style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
    }
  end

  defp power_span(%PowerState{voltage: voltage}) do
    %Span{
      content: "⚡ #{format_voltage(voltage)}",
      style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
    }
  end

  defp charging_suffix(:charging), do: " ⚡"
  defp charging_suffix(_status), do: ""

  defp format_voltage(voltage) when is_number(voltage) do
    "#{:erlang.float_to_binary(voltage / 1, decimals: 1)}V"
  end

  defp key_hints(%State{ui: %{active_panel: panel}, safety: %{state: safety}} = state) do
    base =
      [
        Theme.key_pill("Tab"),
        Theme.dim_span(" panel "),
        Theme.key_pill("?"),
        Theme.dim_span(" help "),
        Theme.key_pill("q", :quit),
        Theme.dim_span(" quit ")
      ]

    extras =
      case panel do
        :parameters -> parameters_keys(state)
        _ -> panel_keys(panel, safety)
      end

    case extras do
      [] -> base
      _ -> base ++ [Theme.dim_span("  ") | extras]
    end
  end

  defp panel_keys(:safety, _safety) do
    [
      Theme.key_pill("a"),
      Theme.dim_span(" arm "),
      Theme.key_pill("d"),
      Theme.dim_span(" disarm ")
    ]
  end

  defp panel_keys(:commands, _safety) do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" execute ")
    ]
  end

  defp panel_keys(:events, _safety) do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" scroll "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" detail "),
      Theme.key_pill("p"),
      Theme.dim_span(" pause "),
      Theme.key_pill("c"),
      Theme.dim_span(" clear ")
    ]
  end

  defp panel_keys(:joints, safety) when safety in [:armed, :disarming] do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("h/l"),
      Theme.dim_span(" adjust "),
      Theme.key_pill("H/L"),
      Theme.dim_span(" 10× ")
    ]
  end

  defp panel_keys(:joints, _safety) do
    [Theme.key_pill("j/k"), Theme.dim_span(" select ")]
  end

  defp panel_keys(_, _), do: []

  defp parameters_keys(%State{parameters: %{tabs: tabs}}) do
    base = [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("h/l"),
      Theme.dim_span(" adjust "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" toggle ")
    ]

    if length(tabs) > 1 do
      base ++ [Theme.key_pill("t"), Theme.dim_span(" tab ")]
    else
      base
    end
  end
end
