defmodule BB.TUI.Panels.ForceDisarm do
  @moduledoc """
  Force disarm confirmation popup.

  Asks the user to confirm force disarming from an error state.
  """

  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Popup

  @doc """
  Renders the force disarm confirmation popup.
  """
  @spec render() :: struct()
  def render do
    content = %Paragraph{
      text: "Force disarm from error state?\n\n[y] Confirm    [n] Cancel",
      style: %Style{fg: :white},
      alignment: :center
    }

    %Popup{
      content: content,
      percent_width: 40,
      percent_height: 30,
      block: %Block{
        title: " Confirm Force Disarm ",
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :red}
      }
    }
  end
end
