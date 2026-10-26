defmodule BB.TUI.Panels.Extension do
  @moduledoc """
  An extension tab: its panels laid out in rows of up to three, each a
  bordered box of its readouts and plots in the order they were declared.

  A readout takes a line: its label, its formatted value (see
  `BB.TUI.Extension.Format`) and, with `spark: true`, a sparkline of the
  last 10 seconds. Plots share the rest of the panel's height, each a
  braille line chart with one coloured line per source over its `window`,
  the x axis in seconds before now — or before the moment the charts were
  frozen.

  Pure function — takes state and the current monotonic time, returns
  `{widget, rect}` pairs.
  """

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

  defp label_width([]), do: 1
  defp label_width(items), do: (items |> Enum.map(&String.length(&1.label)) |> Enum.max()) + 3
end
