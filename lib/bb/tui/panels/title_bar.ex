defmodule BB.TUI.Panels.TitleBar do
  @moduledoc """
  Title bar — single-line branded header at the top of the dashboard.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the title bar as a centered Paragraph widget with the
  Beam Bots branding and the current robot module name.

  ## Examples

      iex> state = %BB.TUI.State{robot: MyApp.Robot}
      iex> widget = BB.TUI.Panels.TitleBar.render(state)
      iex> widget.text =~ "Beam Bots"
      true

      iex> state = %BB.TUI.State{robot: MyApp.Robot}
      iex> widget = BB.TUI.Panels.TitleBar.render(state)
      iex> widget.text =~ "MyApp.Robot"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{robot: robot}) do
    text = " Beam Bots TUI \u2014 #{inspect(robot)} "

    %Paragraph{
      text: text,
      style: %Style{
        fg: Theme.title_fg(),
        bg: Theme.title_bg(),
        modifiers: [:bold]
      }
    }
  end
end
