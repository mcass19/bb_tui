defmodule BB.TUI.Panels.Hint do
  @moduledoc """
  The hint banner under the title bar: an extension's text for the robot's
  current runtime state (see `BB.TUI.Extension`'s `hints` section). Pure
  function — takes the text, returns a widget struct.
  """

  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders `text` as a one-line banner.

  ## Examples

      iex> %ExRatatui.Widgets.Paragraph{text: text} = BB.TUI.Panels.Hint.render("s to stand")
      iex> text
      " ▸ s to stand"
  """
  @spec render(String.t()) :: Paragraph.t()
  def render(text) do
    %Paragraph{text: " ▸ " <> text, style: %Style{fg: Theme.yellow(), modifiers: [:bold]}}
  end
end
