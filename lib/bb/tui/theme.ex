defmodule BB.TUI.Theme do
  @moduledoc """
  Color and style constants for the BB TUI dashboard.

  Provides a consistent visual palette for the robot dashboard.
  All functions are pure and return either a color tuple or an
  `%ExRatatui.Style{}` struct.
  """

  alias ExRatatui.Style

  # ── Colors ──────────────────────────────────────────────────

  @doc "Green for armed/safe states."
  @spec green() :: ExRatatui.Style.color()
  def green, do: :green

  @doc "Red for error states."
  @spec red() :: ExRatatui.Style.color()
  def red, do: :red

  @doc "Yellow for transitional states (disarming)."
  @spec yellow() :: ExRatatui.Style.color()
  def yellow, do: :yellow

  @doc "Cyan for timestamps and active panel borders."
  @spec cyan() :: ExRatatui.Style.color()
  def cyan, do: :cyan

  @doc "Muted border color for inactive panels."
  @spec dim_border() :: ExRatatui.Style.color()
  def dim_border, do: :dark_gray

  @doc "Muted text for secondary information."
  @spec dim_text() :: ExRatatui.Style.color()
  def dim_text, do: :dark_gray

  # ── Composite Styles ───────────────────────────────────────

  @doc "Bold green style for armed state."
  @spec armed_style() :: Style.t()
  def armed_style, do: %Style{fg: green(), modifiers: [:bold]}

  @doc "Dim style for disarmed state."
  @spec disarmed_style() :: Style.t()
  def disarmed_style, do: %Style{fg: dim_text()}

  @doc "Bold yellow style for disarming state."
  @spec disarming_style() :: Style.t()
  def disarming_style, do: %Style{fg: yellow(), modifiers: [:bold]}

  @doc "Bold red style for error state."
  @spec error_style() :: Style.t()
  def error_style, do: %Style{fg: red(), modifiers: [:bold]}

  @doc "Highlight style for selected items."
  @spec highlight_style() :: Style.t()
  def highlight_style, do: %Style{fg: cyan(), modifiers: [:bold]}

  @doc "Cyan border style for the active/focused panel."
  @spec focused_border_style() :: Style.t()
  def focused_border_style, do: %Style{fg: cyan()}

  @doc "Dim border style for inactive panels."
  @spec unfocused_border_style() :: Style.t()
  def unfocused_border_style, do: %Style{fg: dim_border()}

  @doc """
  Returns focused or unfocused border style based on boolean.
  """
  @spec border_style(boolean()) :: Style.t()
  def border_style(true), do: focused_border_style()
  def border_style(false), do: unfocused_border_style()
end
