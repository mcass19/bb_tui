defmodule BB.TUI.Panels.Extension do
  @moduledoc """
  An extension tab: its panels laid out in rows of up to three, each a
  bordered table of readouts and plots in the order they were declared.

  A readout shows its label and its formatted value (see
  `BB.TUI.Extension.Format`); a plot, for now, the latest value of each of
  its sources.

  Pure function — takes state, returns `{widget, rect}` pairs.
  """

  alias BB.TUI.Extension.Format
  alias BB.TUI.Extension.Panel
  alias BB.TUI.Extension.Plot
  alias BB.TUI.Extension.Readout
  alias BB.TUI.State
  alias BB.TUI.State.Extensions
  alias BB.TUI.Theme
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @per_row 3

  @doc """
  Lays out the panels of extension tab `tab` over `area`.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Readout, Source}
      iex> panel = %Panel{name: :yaw, items: [%Readout{label: "heading", source: Source.joint(:yaw)}]}
      iex> state = %BB.TUI.State{extensions: %BB.TUI.State.Extensions{panels: [panel]}}
      iex> [{%ExRatatui.Widgets.Table{}, _rect}] =
      ...>   BB.TUI.Panels.Extension.render_tab(state, :yaw, %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 10})
  """
  @spec render_tab(State.t(), atom(), Rect.t()) :: [{struct(), Rect.t()}]
  def render_tab(%State{} = state, tab, %Rect{} = area) do
    rows = state.extensions |> Extensions.panels_on(tab) |> Enum.chunk_every(@per_row)
    row_areas = Layout.split(area, :vertical, Enum.map(rows, fn _ -> {:fill, 1} end))

    for {panels, row_area} <- Enum.zip(rows, row_areas),
        {panel, panel_area} <-
          Enum.zip(
            panels,
            Layout.split(row_area, :horizontal, Enum.map(panels, fn _ -> {:fill, 1} end))
          ),
        do: {render(state, panel), panel_area}
  end

  @doc """
  Renders one panel as a two-column table: labels, then values.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Readout, Source}
      iex> panel = %Panel{name: :yaw, title: "Yaw", items: [%Readout{label: "heading", source: Source.joint(:yaw)}]}
      iex> %ExRatatui.Widgets.Table{rows: [[label, value]]} =
      ...>   BB.TUI.Panels.Extension.render(%BB.TUI.State{}, panel)
      iex> {label.content, value.content}
      {" heading", "-"}
  """
  @spec render(State.t(), Panel.t()) :: Table.t()
  def render(%State{} = state, %Panel{} = panel) do
    %Table{
      rows: Enum.map(panel.items, &row(state, &1)),
      # The label column fits the longest label, so values line up beside them.
      widths: [{:length, label_width(panel.items)}, {:min, 0}],
      block: %Block{
        title: " #{Extensions.panel_title(panel)} ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.unfocused_border_style()
      }
    }
  end

  defp row(state, %Readout{} = readout) do
    [label(readout.label), value(Format.readout(Extensions.read(state, readout.source), readout))]
  end

  defp row(state, %Plot{} = plot) do
    values =
      Enum.map_join(plot.sources, " · ", fn source ->
        Format.readout(Extensions.read(state, source), %Readout{label: plot.label, source: source})
      end)

    [label(plot.label), value(values)]
  end

  defp label(text), do: %Span{content: " " <> text, style: %Style{fg: Theme.dim_text()}}

  defp label_width([]), do: 1
  defp label_width(items), do: (items |> Enum.map(&String.length(&1.label)) |> Enum.max()) + 3

  defp value("-"), do: %Span{content: "-", style: %Style{fg: Theme.dim_text()}}
  defp value(text), do: %Span{content: text, style: %Style{fg: :white, modifiers: [:bold]}}
end
