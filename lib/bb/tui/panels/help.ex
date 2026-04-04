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
    Enter       Show event details
    p           Pause / resume stream
    c           Clear all events

  Commands panel:
    j / Down    Select next command
    k / Up      Select previous command
    Enter       Execute selected command

  Joints panel:
    j / Down    Select next joint
    k / Up      Select previous joint
    l / Right   Increase position (1% step)
    h / Left    Decrease position (1% step)
    L           Increase position (10% step)
    H           Decrease position (10% step)

  Parameters panel:
    j / Down    Select next parameter
    k / Up      Select previous parameter
    l / Right   Increase value (+1 int, +0.1 float)
    h / Left    Decrease value (-1 int, -0.1 float)
    L           Increase value x10
    H           Decrease value x10
    Enter       Toggle boolean parameter

  [j/k] Scroll   [any other key] Close\
  """

  @doc """
  Renders the help popup as a Popup widget with optional scroll offset.

  ## Examples

      iex> %ExRatatui.Widgets.Popup{} = BB.TUI.Panels.Help.render(0)
  """
  @spec render(non_neg_integer()) :: struct()
  def render(scroll_offset \\ 0) do
    content = %Paragraph{
      text: @help_text,
      style: %Style{fg: :white},
      wrap: true,
      scroll: {scroll_offset, 0}
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
