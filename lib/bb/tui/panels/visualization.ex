defmodule BB.TUI.Panels.Visualization do
  @moduledoc """
  Visualization tab — renders the live robot in 3D. Pure function: takes state and
  the main `Rect`, returns `[{widget, rect}]`.

  This is a placeholder pane; the 3D viewport is wired in a later step.
  """

  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @spec render_panes(struct(), struct()) :: [{struct(), struct()}]
  def render_panes(_state, area) do
    widget = %Paragraph{
      text: "3D visualization - coming soon",
      style: %Style{fg: Theme.dim_text()},
      block: %Block{
        title: "Visualization",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(true)
      }
    }

    [{widget, area}]
  end
end
