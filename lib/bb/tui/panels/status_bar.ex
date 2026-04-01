defmodule BB.TUI.Panels.StatusBar do
  @moduledoc """
  Status bar — single-line bar with robot name, safety indicator, runtime
  state, and context-sensitive key hints.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the status bar as a Paragraph widget showing robot name,
  safety state, runtime state, and keybindings for the active panel.

  ## Examples

      iex> state = %BB.TUI.State{robot: MyApp.Robot, safety_state: :armed, runtime_state: :idle, active_panel: :safety}
      iex> widget = BB.TUI.Panels.StatusBar.render(state)
      iex> widget.text =~ "MyApp.Robot"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{} = state) do
    robot_name = inspect(state.robot)
    safety = format_safety(state.safety_state)
    runtime = to_string(state.runtime_state)
    panel_hints = panel_keys(state.active_panel, state.safety_state)

    text =
      " #{robot_name} | #{safety} | #{runtime} | [q]Quit [Tab]Panel [?]Help #{panel_hints}"

    %Paragraph{
      text: text,
      style: %Style{fg: :white, bg: :dark_gray}
    }
  end

  defp format_safety(:armed), do: "\u{25CF} Armed"
  defp format_safety(:disarmed), do: "\u{25CB} Disarmed"
  defp format_safety(:disarming), do: "\u{25CF} Disarming"
  defp format_safety(:error), do: "\u{2716} Error"
  defp format_safety(other), do: to_string(other)

  defp panel_keys(:safety, _safety), do: "[a]Arm [d]Disarm"
  defp panel_keys(:commands, _safety), do: "[Up/Down]Select [Enter]Execute"
  defp panel_keys(:events, _safety), do: "[j/k]Scroll [Enter]Detail [p]Pause [c]Clear"

  defp panel_keys(:joints, safety) when safety in [:armed, :disarming],
    do: "[j/k]Select [h/l]Adj [H/L]Adj10x"

  defp panel_keys(:joints, _safety), do: "[j/k]Select"
  defp panel_keys(:parameters, _safety), do: ""
  defp panel_keys(_, _safety), do: ""
end
