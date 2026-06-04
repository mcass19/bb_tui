defmodule BB.TUI.Panels.CommandEdit do
  @moduledoc """
  Argument-edit popup for the commands panel.

  Floats above the dashboard while the user edits the arguments of the
  selected command. Each declared argument renders as a row showing
  the current value (string buffer) and type hint; the focused row
  gets a `›` prefix and a `▏` cursor. A hint footer describes the
  edit-mode keys.

  Pure function — takes state, returns a Popup widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Popup

  @doc """
  Renders the edit popup for the selected command, or `nil` when the
  selected command has no arguments. The caller should only invoke
  this when `state.commands.edit_mode?` is true.

  ## Examples

      iex> cmd = %{name: :move, arguments: [%{name: :angle, type: "float", default: 0.0}]}
      iex> state = %BB.TUI.State{
      ...>   commands: %BB.TUI.State.Commands{
      ...>     available: [cmd],
      ...>     selected: 0,
      ...>     edit_mode?: true,
      ...>     focused_arg: 0
      ...>   }
      ...> }
      iex> %ExRatatui.Widgets.Popup{} = BB.TUI.Panels.CommandEdit.render(state)

      iex> state = %BB.TUI.State{commands: %BB.TUI.State.Commands{available: [], selected: 0}}
      iex> BB.TUI.Panels.CommandEdit.render(state)
      nil
  """
  @spec render(State.t()) :: struct() | nil
  def render(%State{} = state) do
    case State.selected_command(state) do
      %{name: cmd_name, arguments: [_ | _] = args} ->
        build_popup(state, cmd_name, args)

      _ ->
        nil
    end
  end

  defp build_popup(state, cmd_name, args) do
    line_groups =
      args
      |> Enum.with_index()
      |> Enum.flat_map(fn {arg, i} ->
        arg_lines(state, cmd_name, arg, i == state.commands.focused_arg)
      end)

    text = line_groups ++ [%Line{spans: []}, hint_line(args)]

    content = %Paragraph{text: text, style: %Style{fg: :white}}

    %Popup{
      content: content,
      percent_width: 60,
      percent_height: 40,
      block: %Block{
        title: title_line(cmd_name),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
      }
    }
  end

  defp title_line(cmd_name) do
    %Line{
      spans: [
        %Span{content: " Edit ", style: %Style{}},
        %Span{
          content: to_string(cmd_name),
          style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
        },
        %Span{content: " ", style: %Style{}}
      ]
    }
  end

  defp arg_lines(state, cmd_name, arg, focused?) do
    [field_line(state, cmd_name, arg, focused?) | doc_line(arg)]
  end

  defp field_line(state, cmd_name, %{enum_values: [_ | _]} = arg, focused?) do
    name = to_string(arg.name)
    type = arg.type
    value = State.arg_value(state, cmd_name, arg)
    prefix = if focused?, do: " › ", else: "   "
    required_marker = if Map.get(arg, :required, false), do: "*", else: ""

    %Line{
      spans: [
        %Span{content: prefix, style: %Style{fg: Theme.cyan()}},
        %Span{content: name, style: %Style{fg: :white, modifiers: [:bold]}},
        %Span{content: required_marker, style: %Style{fg: Theme.red(), modifiers: [:bold]}},
        %Span{content: " (#{type})", style: %Style{fg: Theme.dim_text()}},
        %Span{content: ": ", style: %Style{fg: Theme.dim_text()}},
        %Span{content: "‹ ", style: %Style{fg: Theme.cyan()}},
        %Span{content: enum_display(value), style: value_style(focused?)},
        %Span{content: " ›", style: %Style{fg: Theme.cyan()}}
      ]
    }
  end

  defp field_line(state, cmd_name, arg, focused?) do
    name = to_string(arg.name)
    type = arg.type
    value = State.arg_value(state, cmd_name, arg)
    prefix = if focused?, do: " › ", else: "   "
    cursor = if focused?, do: "▏", else: ""
    required_marker = if Map.get(arg, :required, false), do: "*", else: ""

    %Line{
      spans: [
        %Span{content: prefix, style: %Style{fg: Theme.cyan()}},
        %Span{content: name, style: %Style{fg: :white, modifiers: [:bold]}},
        %Span{content: required_marker, style: %Style{fg: Theme.red(), modifiers: [:bold]}},
        %Span{content: " (#{type})", style: %Style{fg: Theme.dim_text()}},
        %Span{content: ": ", style: %Style{fg: Theme.dim_text()}},
        %Span{content: value, style: value_style(focused?)},
        %Span{content: cursor, style: %Style{fg: Theme.cyan(), modifiers: [:bold]}}
      ]
    }
  end

  defp enum_display(":" <> rest) when byte_size(rest) > 0, do: rest
  defp enum_display(value), do: value

  defp doc_line(arg) do
    case Map.get(arg, :doc) do
      doc when is_binary(doc) and byte_size(doc) > 0 ->
        [%Line{spans: [%Span{content: "     " <> doc, style: %Style{fg: Theme.dim_text()}}]}]

      _ ->
        []
    end
  end

  defp value_style(true), do: %Style{fg: :white, modifiers: [:bold]}
  defp value_style(false), do: %Style{fg: Theme.dim_text()}

  defp hint_line(args) do
    base = " [Tab] next  [⇧Tab] prev  [⏎] execute  [Esc] cancel"

    extra =
      if Enum.any?(args, &match?(%{enum_values: [_ | _]}, &1)), do: "  [←/→] cycle", else: ""

    %Line{
      spans: [
        %Span{
          content: base <> extra,
          style: %Style{fg: Theme.dim_text()}
        }
      ]
    }
  end
end
