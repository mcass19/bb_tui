defmodule BB.TUI.Panels.Commands do
  @moduledoc """
  Commands panel — displays available robot commands with execution state.

  Shows each command name with a Ready / Blocked badge based on the
  current runtime state. Each row is a `%ExRatatui.Text.Line{}` so
  the badge can render in its own color (green for Ready, dim for
  Blocked) without affecting the surrounding text. The trailing
  result / executing rows render as colored badges too — green ✔ for
  success, red ✖ for failure, yellow ⏳ while a command is in flight.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.List, as: WidgetList

  @doc """
  Renders the commands panel as a List widget. Arrow keys select,
  Enter executes when focused.

  ## Examples

      iex> state = %BB.TUI.State{
      ...>   commands: [%{name: :home, allowed_states: [:idle]}],
      ...>   runtime_state: :idle, command_selected: 0,
      ...>   command_result: nil, executing_command: nil
      ...> }
      iex> %ExRatatui.Widgets.List{items: [%ExRatatui.Text.Line{spans: spans}]} =
      ...>   BB.TUI.Panels.Commands.render(state, false)
      iex> Enum.map_join(spans, "", & &1.content)
      "home  ● Ready"
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{} = state, focused?) do
    items = format_commands(state)

    result_line =
      case state.command_result do
        {:ok, result} -> [result_line(:ok, "✔ #{inspect(result, limit: 50)}")]
        {:error, reason} -> [result_line(:error, "✖ #{inspect(reason, limit: 50)}")]
        nil -> []
      end

    executing_line =
      if state.executing_command do
        [executing_line()]
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
        title: title_line(state),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Returns the title string for the commands panel (legacy, plain string).

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

  @doc ~S"""
  Returns the rich-text panel title — the count renders bold-cyan.

  ## Examples

      iex> state = %BB.TUI.State{commands: [%{name: :a}]}
      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Panels.Commands.title_line(state)
      iex> Enum.map_join(spans, "", & &1.content)
      " Commands (1) "

      iex> state = %BB.TUI.State{commands: []}
      iex> %ExRatatui.Text.Line{spans: [%{content: only}]} =
      ...>   BB.TUI.Panels.Commands.title_line(state)
      iex> only
      " Commands "
  """
  @spec title_line(State.t()) :: Line.t()
  def title_line(%State{commands: []}) do
    %Line{spans: [%Span{content: " Commands ", style: %Style{}}]}
  end

  def title_line(%State{commands: cmds}) do
    %Line{
      spans: [
        %Span{content: " Commands (", style: %Style{}},
        %Span{
          content: Integer.to_string(length(cmds)),
          style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
        },
        %Span{content: ") ", style: %Style{}}
      ]
    }
  end

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

  # ── Private: rich-text rows ─────────────────────────────────

  defp format_commands(%State{commands: commands, runtime_state: runtime_state}) do
    Enum.map(commands, fn cmd ->
      name = to_string(Map.get(cmd, :name, inspect(cmd)))

      if command_ready?(cmd, runtime_state) do
        ready_row(name)
      else
        blocked_row(name)
      end
    end)
  end

  defp ready_row(name) do
    %Line{
      spans: [
        %Span{content: name, style: %Style{fg: :white}},
        %Span{content: "  ", style: %Style{}},
        %Span{content: "● Ready", style: Theme.ready_style()}
      ]
    }
  end

  defp blocked_row(name) do
    %Line{
      spans: [
        %Span{content: name, style: %Style{fg: Theme.dim_text()}},
        %Span{content: "  ", style: %Style{}},
        %Span{content: "○ Blocked", style: Theme.blocked_style()}
      ]
    }
  end

  defp executing_line do
    %Line{
      spans: [
        %Span{content: "⏳ Executing…", style: %Style{fg: Theme.yellow(), modifiers: [:bold]}}
      ]
    }
  end

  defp result_line(:ok, text) do
    %Line{spans: [%Span{content: text, style: %Style{fg: Theme.green(), modifiers: [:bold]}}]}
  end

  defp result_line(:error, text) do
    %Line{spans: [%Span{content: text, style: %Style{fg: Theme.red(), modifiers: [:bold]}}]}
  end
end
