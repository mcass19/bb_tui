defmodule BB.TUI.Panels.StatusBar do
  @moduledoc """
  Status bar — single-line bar with robot name, runtime state, and key hints.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the status bar as a Paragraph widget.

  ## Examples

      iex> state = %BB.TUI.State{robot: MyApp.Robot, runtime_state: :idle}
      iex> widget = BB.TUI.Panels.StatusBar.render(state)
      iex> widget.text =~ "MyApp.Robot"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{robot: robot, runtime_state: runtime_state}) do
    robot_name = inspect(robot)

    %Paragraph{
      text:
        " #{robot_name} | #{runtime_state} | [q] Quit  [Tab] Panel  [?] Help  [a] Arm  [d] Disarm",
      style: %Style{fg: :white, bg: :dark_gray}
    }
  end
end
