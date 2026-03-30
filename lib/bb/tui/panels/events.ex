defmodule BB.TUI.Panels.Events do
  @moduledoc """
  Events panel — displays a scrollable list of recent robot messages.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.List, as: WidgetList

  @doc """
  Renders the events panel as a List widget with formatted event entries.
  Newest events appear first. Scrollable with j/k when focused.
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{events: events, scroll_offset: offset}, focused?) do
    items = Enum.map(events, &format_event/1)

    %WidgetList{
      items: items,
      selected: if(events != [], do: offset),
      highlight_style: Theme.highlight_style(),
      block: %Block{
        title: " Events (#{length(events)}) ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  defp format_event({timestamp, path, message}) do
    time = Calendar.strftime(timestamp, "%H:%M:%S")
    path_str = Enum.join(path, ".")
    payload = inspect(message, pretty: false, limit: 50)

    "#{time} [#{path_str}] #{payload}"
  end
end
