defmodule BB.TUI.Panels.Commands do
  @moduledoc """
  Commands panel — displays available robot commands with execution state.

  Shows each command name with a Ready/Blocked indicator based on the
  current runtime state. Selected command is highlighted.

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

      iex> state = %BB.TUI.State{commands: [%{name: :home, allowed_states: [:idle]}], runtime_state: :idle, command_selected: 0, command_result: nil, executing_command: nil}
      iex> widget = BB.TUI.Panels.Commands.render(state, false)
      iex> widget.items
      ["home  \u{25CF} Ready"]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{} = state, focused?) do
    items = format_commands(state)

    result_line =
      case state.command_result do
        {:ok, result} -> ["\u{2714} #{inspect(result, limit: 50)}"]
        {:error, reason} -> ["\u{2716} #{inspect(reason, limit: 50)}"]
        nil -> []
      end

    executing_line =
      if state.executing_command do
        ["\u{23F3} Executing..."]
      else
        []
      end

    all_items = items ++ executing_line ++ result_line

    %WidgetList{
      items: all_items,
      selected: if(state.commands != [], do: state.command_selected),
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: title(state),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Returns the title string for the commands panel.

  ## Examples

      iex> state = %BB.TUI.State{commands: [%{name: :a}, %{name: :b}]}
      iex> BB.TUI.Panels.Commands.title(state)
      " Commands (2) "

      iex> state = %BB.TUI.State{commands: []}
      iex> BB.TUI.Panels.Commands.title(state)
      " Commands "
  """
  @spec title(State.t()) :: String.t()
  def title(%State{commands: []}), do: " Commands "
  def title(%State{commands: cmds}), do: " Commands (#{length(cmds)}) "

  @doc """
  Checks whether a command can execute in the current runtime state.

  ## Examples

      iex> BB.TUI.Panels.Commands.command_ready?(%{allowed_states: [:idle, :executing]}, :idle)
      true

      iex> BB.TUI.Panels.Commands.command_ready?(%{allowed_states: [:idle]}, :executing)
      false

      iex> BB.TUI.Panels.Commands.command_ready?(%{}, :idle)
      true
  """
  @spec command_ready?(map(), atom()) :: boolean()
  def command_ready?(%{allowed_states: allowed}, runtime_state) do
    runtime_state in allowed
  end

  def command_ready?(_cmd, _runtime_state), do: true

  defp format_commands(%State{commands: commands, runtime_state: runtime_state}) do
    Enum.map(commands, fn cmd ->
      name = to_string(Map.get(cmd, :name, inspect(cmd)))

      if command_ready?(cmd, runtime_state) do
        "#{name}  \u{25CF} Ready"
      else
        "#{name}  \u{25CB} Blocked"
      end
    end)
  end
end
