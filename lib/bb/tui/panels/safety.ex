defmodule BB.TUI.Panels.Safety do
  @moduledoc """
  Safety panel — displays safety state, runtime state, and control hints.

  Combines safety status indicator, runtime state, and keyboard shortcuts
  in a single left-sidebar panel. When the robot is disarming, shows a
  throbber animation.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Throbber

  @doc """
  Renders the safety panel with status indicator, runtime state, and key hints.

  When the robot is in the `:disarming` state, returns a Throbber widget
  instead to show the animated transition indicator.

  ## Examples

      iex> state = %BB.TUI.State{safety: %BB.TUI.State.Safety{state: :armed, runtime: :idle}}
      iex> %ExRatatui.Widgets.Paragraph{} = BB.TUI.Panels.Safety.render(state, true)

      iex> state = %BB.TUI.State{ui: %BB.TUI.State.UI{throbber_step: 0}, safety: %BB.TUI.State.Safety{state: :disarming, runtime: :disarming}}
      iex> %ExRatatui.Widgets.Throbber{} = BB.TUI.Panels.Safety.render(state, false)
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{safety: %{state: :disarming}} = state, focused?) do
    %Throbber{
      label: "DISARMING",
      step: state.ui.throbber_step,
      throbber_set: :dots,
      style: Theme.disarming_style(),
      throbber_style: Theme.disarming_style(),
      block: block(focused?)
    }
  end

  def render(%State{} = state, focused?) do
    {symbol, label, style} = state_display(state.safety.state)
    runtime_label = format_runtime(state.safety.runtime)

    text = """
    #{symbol} #{label}

    Runtime: #{runtime_label}

    [a] Arm
    [d] Disarm\
    """

    text =
      if state.safety.state == :error do
        text <> "\n[f] Force Disarm"
      else
        text
      end

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

  defp format_runtime(:idle), do: "Idle"
  defp format_runtime(:executing), do: "Executing..."
  defp format_runtime(:disarmed), do: "Disarmed"
  defp format_runtime(:error), do: "Error"
  defp format_runtime(other), do: to_string(other)

  defp block(focused?) do
    %Block{
      title: title_line(),
      borders: [:all],
      border_type: :rounded,
      border_style: Theme.border_style(focused?)
    }
  end

  defp title_line do
    spans =
      Theme.panel_badge_spans(State.panel_number(:safety)) ++
        [%Span{content: "Safety ", style: Theme.panel_title_style()}]

    %Line{spans: spans}
  end
end
