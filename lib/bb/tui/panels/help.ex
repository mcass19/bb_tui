defmodule BB.TUI.Panels.Help do
  @moduledoc """
  Help popup — overlay showing all available keyboard shortcuts.

  Pure function — returns a Popup widget struct.
  """

  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Popup

  @help_text """
  BB TUI Dashboard - Keyboard Shortcuts

  Global:
    q           Quit
    Tab         Cycle active panel
    ?           Toggle this help
    a           Arm robot
    d           Disarm robot
    f           Force disarm (error state only)

  Events panel:
    j / Down    Scroll down
    k / Up      Scroll up
    p           Pause / resume stream
    c           Clear all events

  Commands panel:
    j / Down    Select next command
    k / Up      Select previous command
    Enter       Execute selected command

  Joints panel:
    j / Down    Scroll down
    k / Up      Scroll up

  Press any key to close\
  """

  @doc """
  Renders the help popup as a Popup widget.

  ## Examples

      iex> %ExRatatui.Widgets.Popup{} = BB.TUI.Panels.Help.render()
  """
  @spec render() :: struct()
  def render do
    content = %Paragraph{
      text: @help_text,
      style: %Style{fg: :white}
    }

    %Popup{
      content: content,
      percent_width: 60,
      percent_height: 70,
      block: %Block{
        title: " Help ",
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :cyan}
      }
    }
  end
end
