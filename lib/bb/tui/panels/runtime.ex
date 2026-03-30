defmodule BB.TUI.Panels.Runtime do
  @moduledoc """
  Runtime state panel — displays the robot's current runtime state.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the runtime state panel as a Paragraph widget.
  """
  @spec render(State.t()) :: struct()
  def render(%State{runtime_state: runtime_state}) do
    {label, style} = state_display(runtime_state)

    %Paragraph{
      text: label,
      style: style,
      block: %Block{
        title: " Runtime ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.unfocused_border_style()
      }
    }
  end

  defp state_display(:idle), do: {"Idle", %Style{fg: Theme.green()}}

  defp state_display(:executing),
    do: {"Executing...", %Style{fg: Theme.yellow(), modifiers: [:bold]}}

  defp state_display(:disarmed), do: {"Disarmed", %Style{fg: Theme.dim_text()}}
  defp state_display(:error), do: {"Error", Theme.error_style()}
  defp state_display(other), do: {to_string(other), %Style{fg: Theme.dim_text()}}
end
