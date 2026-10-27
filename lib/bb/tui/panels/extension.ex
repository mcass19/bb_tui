defmodule BB.TUI.Panels.Extension do
  @moduledoc """
  An extension tab: its panels laid out in rows of up to three, each a
  bordered box of its readouts and plots in the order they were declared.

  A readout takes a line: its label, its formatted value (see
  `BB.TUI.Extension.Format`) and, with `spark: true`, a sparkline of the
  last 10 seconds. Plots share the rest of the panel's height, each a
  braille line chart with one coloured line per source over its `window`,
  the x axis in seconds before now — or before the moment the charts were
  frozen. Attitude indicators share that height too: a braille horizon and
  pitch ladder behind a fixed aircraft symbol, the angles underneath.

  Pure function — takes state and the current monotonic time, returns
  `{widget, rect}` pairs.
  """

  alias BB.TUI.Extension.Attitude
  alias BB.TUI.Extension.Format
  alias BB.TUI.Extension.Panel
  alias BB.TUI.Extension.Plot
  alias BB.TUI.Extension.Readout
  alias BB.TUI.Extension.Source
  alias BB.TUI.State
  alias BB.TUI.State.Extensions
  alias BB.TUI.State.Series
  alias BB.TUI.Theme
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Canvas
  alias ExRatatui.Widgets.Chart
  alias ExRatatui.Widgets.Chart.Axis
  alias ExRatatui.Widgets.Chart.Dataset
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Sparkline

  @per_row 3
  @value_width 14
  @line_colors [:cyan, :yellow, :magenta, :green, :blue, :red]

  @doc """
  Lays out the panels of extension tab `tab` over `area`, with charts
  ending at `now` (a monotonic time in milliseconds) unless frozen.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Readout, Source}
      iex> panel = %Panel{name: :yaw, items: [%Readout{label: "heading", source: Source.joint(:yaw)}]}
      iex> state = %BB.TUI.State{extensions: %BB.TUI.State.Extensions{panels: [panel]}}
      iex> area = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 10}
      iex> [{%ExRatatui.Widgets.Block{title: " Yaw "}, ^area} | rows] =
      ...>   BB.TUI.Panels.Extension.render_tab(state, :yaw, area, 0)
      iex> for {%ExRatatui.Widgets.Paragraph{text: text}, _rect} <- rows, do: text
      [" heading", "-"]
  """
  @spec render_tab(State.t(), atom(), Rect.t(), integer()) :: [{struct(), Rect.t()}]
  def render_tab(%State{} = state, tab, %Rect{} = area, now) do
    rows = state.extensions |> Extensions.panels_on(tab) |> Enum.chunk_every(@per_row)

    for {panels, row_area} <- Enum.zip(rows, split(area, :vertical, length(rows))),
        {panel, panel_area} <- Enum.zip(panels, split(row_area, :horizontal, length(panels))),
        widget <- render_panel(state, panel, panel_area, now),
        do: widget
  end

  defp split(area, direction, count),
    do: Layout.split(area, direction, List.duplicate({:fill, 1}, count))

  @doc """
  Renders one panel over `area`: its border, then each item in order.
  """
  @spec render_panel(State.t(), Panel.t(), Rect.t(), integer()) :: [{struct(), Rect.t()}]
  def render_panel(%State{} = state, %Panel{} = panel, %Rect{} = area, now) do
    block = %Block{
      title: " #{Extensions.panel_title(panel)} ",
      borders: [:all],
      border_type: :rounded,
      border_style: Theme.unfocused_border_style()
    }

    items = Enum.with_index(panel.items)
    constraints = Enum.map(items, fn {item, _index} -> constraint(item) end)
    item_areas = Layout.split(inner(area), :vertical, constraints)
    label_width = label_width(panel.items)

    [{block, area}] ++
      Enum.flat_map(Enum.zip(items, item_areas), fn {{item, index}, item_area} ->
        render_item(state, panel, {item, index}, item_area, label_width, now)
      end)
  end

  defp constraint(%Readout{}), do: {:length, 1}
  defp constraint(%Plot{}), do: {:fill, 1}
  defp constraint(%Attitude{}), do: {:fill, 1}

  defp inner(%Rect{x: x, y: y, width: w, height: h}),
    do: %Rect{x: x + 1, y: y + 1, width: max(w - 2, 0), height: max(h - 2, 0)}

  defp render_item(state, panel, {%Readout{} = readout, index}, area, label_width, _now) do
    [label_area, value_area, spark_area] =
      Layout.split(area, :horizontal, [{:length, label_width}, {:length, @value_width}, {:min, 0}])

    text = Format.readout(Extensions.read(state, readout.source), readout)

    [
      {%Paragraph{text: " " <> readout.label, style: %Style{fg: Theme.dim_text()}}, label_area},
      {%Paragraph{text: text, style: value_style(text)}, value_area}
    ] ++ sparkline(state, panel, index, readout, spark_area)
  end

  defp render_item(state, panel, {%Plot{} = plot, index}, area, _label_width, now) do
    [{chart(state, panel, index, plot, now), area}]
  end

  defp render_item(state, _panel, {%Attitude{} = attitude, _index}, area, _label_width, _now) do
    [canvas_area, angles_area] = Layout.split(area, :vertical, [{:fill, 1}, {:length, 1}])
    pitch = angle(state, attitude.pitch, attitude.scale)
    roll = angle(state, attitude.roll, attitude.scale)

    [
      {horizon(attitude, pitch, roll, canvas_area), canvas_area},
      {%Paragraph{text: angles_text(attitude, pitch, roll), style: %Style{fg: :white}},
       angles_area}
    ]
  end

  defp value_style("-"), do: %Style{fg: Theme.dim_text()}
  defp value_style(_text), do: %Style{fg: :white, modifiers: [:bold]}

  defp sparkline(_state, _panel, _index, %Readout{spark: false}, _area), do: []

  defp sparkline(state, panel, index, %Readout{}, %Rect{width: width} = area) do
    values =
      state.extensions.series
      |> Map.fetch!({panel.name, index, 0})
      |> Series.values()
      |> Enum.take(-width)

    [{%Sparkline{data: levels(values), style: %Style{fg: Theme.cyan()}}, area}]
  end

  # Sparkline bars are non-negative integers: spread the window's values
  # over 0..100.
  defp levels([]), do: []

  defp levels(values) do
    {low, high} = Enum.min_max(values)
    span = if high == low, do: 1.0, else: high - low
    Enum.map(values, &round((&1 - low) / span * 100))
  end

  defp chart(state, panel, index, %Plot{} = plot, now) do
    at = Extensions.chart_time(state.extensions, now)
    window_s = plot.window / 1000

    datasets =
      plot.sources
      |> Enum.with_index()
      |> Enum.map(fn {source, line} ->
        %Dataset{
          name: Source.name(source),
          data:
            state.extensions.series |> Map.fetch!({panel.name, index, line}) |> Series.points(at),
          marker: :braille,
          graph_type: :line,
          style: %Style{fg: Enum.at(@line_colors, rem(line, length(@line_colors)))}
        }
      end)

    {low, high} = y_bounds(plot.y_range, datasets)
    frozen? = state.extensions.frozen_at != nil

    %Chart{
      datasets: datasets,
      x_axis: %Axis{
        bounds: {-window_s, 0.0},
        labels: ["-#{format_seconds(window_s)}s", if(frozen?, do: "frozen", else: "now")],
        style: %Style{fg: Theme.dim_text()}
      },
      y_axis: %Axis{
        bounds: {low, high},
        labels: [format_bound(low), format_bound(high)],
        style: %Style{fg: Theme.dim_text()}
      },
      legend_position: :top_right,
      block: %Block{
        title: chart_title(plot.label, frozen?),
        borders: [:top],
        border_style: Theme.unfocused_border_style()
      }
    }
  end

  defp chart_title(label, false), do: " #{label} "
  defp chart_title(label, true), do: " #{label} ❚❚ frozen, space resumes "

  # A fixed range wins; otherwise fit every line, with a little room above
  # and below, and a unit's room for a flat line.
  defp y_bounds({low, high}, _datasets), do: {low * 1.0, high * 1.0}

  defp y_bounds(nil, datasets) do
    case for(%Dataset{data: data} <- datasets, {_x, y} <- data, do: y) do
      [] ->
        {0.0, 1.0}

      ys ->
        {low, high} = Enum.min_max(ys)
        pad = if high == low, do: 1.0, else: (high - low) * 0.1
        {low - pad, high + pad}
    end
  end

  defp format_bound(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp format_seconds(seconds) when seconds == trunc(seconds),
    do: Integer.to_string(trunc(seconds))

  defp format_seconds(seconds), do: :erlang.float_to_binary(seconds, decimals: 1)

  # An angle in radians, scaled; `0.0` for an angle the indicator doesn't
  # read, `nil` for one not seen yet.
  defp angle(_state, nil, _scale), do: 0.0

  defp angle(state, %Source{} = source, scale) do
    case Extensions.read(state, source) do
      value when is_number(value) -> value * (scale || 1)
      _not_yet -> nil
    end
  end

  # Canvas units are the same size both ways: braille gives a cell 2×4 dots
  # and a cell is about twice as tall as it is wide, so x spans 2 units a
  # cell and y 4. The horizon and ladder are drawn in a frame turned by the
  # roll and moved down by the pitch; the canvas clips what falls outside.
  defp horizon(attitude, pitch, roll, %Rect{width: width, height: height}) do
    x_half = max(width, 1) * 1.0
    y_half = max(height - 1, 1) * 2.0
    per_degree = y_half / attitude.range

    shapes =
      if pitch && roll,
        do: ladder(pitch, roll, per_degree, x_half, attitude.range),
        else: []

    %Canvas{
      x_bounds: {-x_half, x_half},
      y_bounds: {-y_half, y_half},
      shapes: shapes ++ aircraft(x_half),
      block: %Block{
        title: " #{attitude.label} ",
        borders: [:top],
        border_style: Theme.unfocused_border_style()
      }
    }
  end

  # A rung every 10° within `range` of the current pitch, unlabelled: the
  # angles line underneath gives the numbers.
  defp ladder(pitch, roll, per_degree, x_half, range) do
    {sin, cos} = {:math.sin(roll), :math.cos(roll)}
    pitch_degrees = pitch * 180 / :math.pi()
    at = fn along, up -> {along * cos - up * sin, along * sin + up * cos} end
    horizon_up = -pitch_degrees * per_degree

    rungs =
      for step <- -9..9,
          step != 0,
          abs(step * 10 - pitch_degrees) < range do
        up = horizon_up + step * 10 * per_degree
        {x1, y1} = at.(-x_half * 0.15, up)
        {x2, y2} = at.(x_half * 0.15, up)
        %Canvas.Line{x1: x1, y1: y1, x2: x2, y2: y2, color: Theme.dim_text()}
      end

    {x1, y1} = at.(-x_half * 3, horizon_up)
    {x2, y2} = at.(x_half * 3, horizon_up)
    [%Canvas.Line{x1: x1, y1: y1, x2: x2, y2: y2, color: Theme.cyan()} | rungs]
  end

  defp aircraft(x_half) do
    [
      %Canvas.Line{
        x1: -x_half * 0.45,
        y1: 0.0,
        x2: -x_half * 0.12,
        y2: 0.0,
        color: Theme.yellow()
      },
      %Canvas.Line{x1: x_half * 0.12, y1: 0.0, x2: x_half * 0.45, y2: 0.0, color: Theme.yellow()},
      %Canvas.Points{coords: [{0.0, 0.0}], color: Theme.yellow()}
    ]
  end

  defp angles_text(attitude, pitch, roll) do
    [pitch: {attitude.pitch, pitch}, roll: {attitude.roll, roll}]
    |> Enum.reject(fn {_name, {source, _value}} -> source == nil end)
    |> Enum.map_join("  ", fn {name, {_source, value}} -> " #{name} #{degrees(value)}" end)
  end

  defp degrees(nil), do: "-"

  defp degrees(radians),
    do: :erlang.float_to_binary(radians * 180 / :math.pi(), decimals: 1) <> "\u{00B0}"

  defp label_width([]), do: 1
  defp label_width(items), do: (items |> Enum.map(&String.length(&1.label)) |> Enum.max()) + 3
end
