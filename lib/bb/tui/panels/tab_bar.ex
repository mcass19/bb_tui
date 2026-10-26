defmodule BB.TUI.Panels.TabBar do
  @moduledoc """
  Top-level tab bar — `Control Panel`, `Visualization` and any extension
  tabs, highlighting the active one. Pure function — takes the labelled
  tabs and the active tab, returns a widget struct.
  """

  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the tab bar as a Paragraph whose rich `%Line{}` highlights `active_tab`.

  ## Examples

      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: [first | _]}} =
      ...>   BB.TUI.Panels.TabBar.render([control: "Control Panel", visualization: "Visualization"], :control)
      iex> first.content
      " Control Panel "
  """
  @spec render([{term(), String.t()}], term()) :: struct()
  def render(tabs, active_tab) do
    spans =
      tabs
      |> Enum.map(fn {tab, label} -> tab_span(label, tab == active_tab) end)
      |> Enum.intersperse(%Span{content: " ", style: %Style{bg: Theme.title_bg()}})

    %Paragraph{text: %Line{spans: spans}, style: %Style{bg: Theme.title_bg()}}
  end

  @doc """
  The columns the tab bar needs: each label padded by a space on either
  side, and a space between tabs.

  ## Examples

      iex> BB.TUI.Panels.TabBar.width([control: "Control Panel", visualization: "Visualization"])
      32
  """
  @spec width([{term(), String.t()}]) :: non_neg_integer()
  def width(tabs) do
    labels = Enum.map(tabs, &elem(&1, 1))
    Enum.sum_by(labels, &(String.length(&1) + 2)) + max(length(labels) - 1, 0)
  end

  defp tab_span(label, true), do: %Span{content: " #{label} ", style: Theme.tab_active_style()}
  defp tab_span(label, false), do: %Span{content: " #{label} ", style: Theme.tab_inactive_style()}
end
