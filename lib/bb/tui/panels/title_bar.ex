defmodule BB.TUI.Panels.TitleBar do
  @moduledoc """
  Title bar — single-line branded header at the top of the dashboard.

  Renders a rich-text `%Line{}` via `BB.TUI.Theme.brand_title/2`, so
  the bot icon, `BB.TUI` brand, robot module, and optional `@ node`
  segment each carry their own color and modifier. The whole line
  sits over `Theme.title_bg/0` for visual separation from the panels
  beneath it.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the title bar as a Paragraph widget. The text is the rich
  `%Line{}` returned by `BB.TUI.Theme.brand_title/2`; the paragraph
  background is `Theme.title_bg/0`.

  ## Examples

      iex> state = %BB.TUI.State{robot: MyApp.Robot, node: nil}
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.TitleBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content)
      " 🤖 BB.TUI · MyApp.Robot"

      iex> state = %BB.TUI.State{robot: MyApp.Robot, node: :"robot@host"}
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.TitleBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "@ robot@host"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{robot: robot, node: node}) do
    %Paragraph{
      text: Theme.brand_title(robot, node),
      style: %Style{bg: Theme.title_bg()}
    }
  end
end
