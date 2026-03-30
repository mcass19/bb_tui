defmodule BB.TUI.Panels.Commands do
  @moduledoc """
  Commands panel — displays available robot commands from the topology.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.List, as: WidgetList

  @doc """
  Renders the commands panel as a List widget.
  Arrow keys select, Enter executes when focused.

  ## Examples

      iex> state = %BB.TUI.State{commands: [%{name: :home}]}
      iex> widget = BB.TUI.Panels.Commands.render(state, false)
      iex> widget.items
      ["home"]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{commands: commands}, focused?) do
    items =
      Enum.map(commands, fn cmd ->
        name = Map.get(cmd, :name, inspect(cmd))
        to_string(name)
      end)

    %WidgetList{
      items: items,
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: " Commands ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end
end
