defmodule BB.TUI.Panels.EventDetail do
  @moduledoc """
  Event detail popup — overlay showing the full payload of the selected event.

  Pure function — takes an event tuple, returns a Popup widget struct.
  """

  alias BB.TUI.Panels.Events
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Popup

  @doc """
  Renders the event detail popup for the given event.

  ## Examples

      iex> event = {~U[2026-01-15 18:23:12.000Z], [:sensor, :sim], %{payload: %{names: [:a], positions: [1.0]}}}
      iex> %ExRatatui.Widgets.Popup{} = BB.TUI.Panels.EventDetail.render(event)
  """
  @spec render({DateTime.t(), list(), term()}) :: struct()
  def render({_ts, _path, _msg} = event) do
    summary = Events.format_event(event)
    detail_lines = Events.format_event_details(event)
    text = Enum.join([summary, "" | detail_lines], "\n")

    content = %Paragraph{
      text: text,
      style: %Style{fg: :white},
      wrap: true
    }

    %Popup{
      content: content,
      percent_width: 60,
      percent_height: 50,
      block: %Block{
        title: " Event Detail ",
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :cyan}
      }
    }
  end
end
