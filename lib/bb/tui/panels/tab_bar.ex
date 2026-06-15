defmodule BB.TUI.Panels.TabBar do
  @moduledoc """
  Top-level tab bar — shows `Control Panel` and `Visualization`, highlighting the
  active tab. Pure function — takes the active tab atom, returns a widget struct.
  """

  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @tabs [control: "Control Panel", visualization: "Visualization"]

  @doc """
  Renders the tab bar as a Paragraph whose rich `%Line{}` highlights `active_tab`.
  """
  @spec render(atom()) :: struct()
  def render(active_tab) do
    spans =
      @tabs
      |> Enum.map(fn {tab, label} -> tab_span(label, tab == active_tab) end)
      |> Enum.intersperse(%Span{content: " ", style: %Style{bg: Theme.title_bg()}})

    %Paragraph{text: %Line{spans: spans}, style: %Style{bg: Theme.title_bg()}}
  end

  defp tab_span(label, true), do: %Span{content: " #{label} ", style: Theme.tab_active_style()}
  defp tab_span(label, false), do: %Span{content: " #{label} ", style: Theme.tab_inactive_style()}
end
