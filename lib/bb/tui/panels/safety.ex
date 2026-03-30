defmodule BB.TUI.Panels.Safety do
  @moduledoc """
  Safety panel — displays the robot's safety state with visual indicators
  and keyboard hints for arm/disarm controls.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Throbber

  @doc """
  Renders the safety panel as a Paragraph widget.

  When the robot is in the `:disarming` state, returns a Throbber widget
  instead to show the animated transition indicator.
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{safety_state: :disarming} = state, focused?) do
    %Throbber{
      label: "DISARMING",
      step: state.throbber_step,
      throbber_set: :dots,
      style: Theme.disarming_style(),
      throbber_style: Theme.disarming_style(),
      block: block(focused?)
    }
  end

  def render(%State{safety_state: safety_state}, focused?) do
    {symbol, label, style} = state_display(safety_state)

    text = """
    #{symbol} #{label}

    [a] Arm
    [d] Disarm
    [f] Force Disarm\
    """

    %Paragraph{
      text: text,
      style: style,
      block: block(focused?)
    }
  end

  defp state_display(:armed), do: {"\u{25CF}", "ARMED", Theme.armed_style()}
  defp state_display(:disarmed), do: {"\u{25CB}", "DISARMED", Theme.disarmed_style()}
  defp state_display(:error), do: {"\u{2716}", "ERROR", Theme.error_style()}
  defp state_display(_other), do: {"\u{25CB}", "UNKNOWN", Theme.disarmed_style()}

  defp block(focused?) do
    %Block{
      title: " Safety ",
      borders: [:all],
      border_type: :rounded,
      border_style: Theme.border_style(focused?)
    }
  end
end
