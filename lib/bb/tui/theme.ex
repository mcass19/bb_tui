defmodule BB.TUI.Theme do
  @moduledoc """
  Color and style constants for the BB TUI dashboard.

  Provides a consistent visual palette for the robot dashboard.
  All functions are pure and return either a color atom or an
  `%ExRatatui.Style{}` struct.
  """

  alias ExRatatui.Style

  # ── Colors ──────────────────────────────────────────────────

  @doc """
  Green for armed/safe states.

  ## Examples

      iex> BB.TUI.Theme.green()
      :green
  """
  @spec green() :: ExRatatui.Style.color()
  def green, do: :green

  @doc """
  Red for error states.

  ## Examples

      iex> BB.TUI.Theme.red()
      :red
  """
  @spec red() :: ExRatatui.Style.color()
  def red, do: :red

  @doc """
  Yellow for transitional states (disarming).

  ## Examples

      iex> BB.TUI.Theme.yellow()
      :yellow
  """
  @spec yellow() :: ExRatatui.Style.color()
  def yellow, do: :yellow

  @doc """
  Cyan for timestamps and active panel borders.

  ## Examples

      iex> BB.TUI.Theme.cyan()
      :cyan
  """
  @spec cyan() :: ExRatatui.Style.color()
  def cyan, do: :cyan

  @doc """
  Blue for interactive elements and paths.

  ## Examples

      iex> BB.TUI.Theme.blue()
      :blue
  """
  @spec blue() :: ExRatatui.Style.color()
  def blue, do: :blue

  @doc """
  Magenta for parameter values and accents.

  ## Examples

      iex> BB.TUI.Theme.magenta()
      :magenta
  """
  @spec magenta() :: ExRatatui.Style.color()
  def magenta, do: :magenta

  @doc """
  Muted border color for inactive panels.

  ## Examples

      iex> BB.TUI.Theme.dim_border()
      :dark_gray
  """
  @spec dim_border() :: ExRatatui.Style.color()
  def dim_border, do: :dark_gray

  @doc """
  Muted text for secondary information.

  ## Examples

      iex> BB.TUI.Theme.dim_text()
      :dark_gray
  """
  @spec dim_text() :: ExRatatui.Style.color()
  def dim_text, do: :dark_gray

  # ── Composite Styles ───────────────────────────────────────

  @doc """
  Bold green style for armed state.

  ## Examples

      iex> style = BB.TUI.Theme.armed_style()
      iex> style.fg
      :green
      iex> style.modifiers
      [:bold]
  """
  @spec armed_style() :: Style.t()
  def armed_style, do: %Style{fg: green(), modifiers: [:bold]}

  @doc """
  Dim style for disarmed state.

  ## Examples

      iex> style = BB.TUI.Theme.disarmed_style()
      iex> style.fg
      :dark_gray
  """
  @spec disarmed_style() :: Style.t()
  def disarmed_style, do: %Style{fg: dim_text()}

  @doc """
  Bold yellow style for disarming state.

  ## Examples

      iex> style = BB.TUI.Theme.disarming_style()
      iex> style.fg
      :yellow
      iex> style.modifiers
      [:bold]
  """
  @spec disarming_style() :: Style.t()
  def disarming_style, do: %Style{fg: yellow(), modifiers: [:bold]}

  @doc """
  Bold red style for error state.

  ## Examples

      iex> style = BB.TUI.Theme.error_style()
      iex> style.fg
      :red
      iex> style.modifiers
      [:bold]
  """
  @spec error_style() :: Style.t()
  def error_style, do: %Style{fg: red(), modifiers: [:bold]}

  @doc """
  Highlight style for selected items.

  ## Examples

      iex> style = BB.TUI.Theme.highlight_style()
      iex> style.fg
      :cyan
      iex> style.modifiers
      [:bold]
  """
  @spec highlight_style() :: Style.t()
  def highlight_style, do: %Style{fg: cyan(), modifiers: [:bold]}

  @doc """
  Cyan border style for the active/focused panel.

  ## Examples

      iex> BB.TUI.Theme.focused_border_style().fg
      :cyan
  """
  @spec focused_border_style() :: Style.t()
  def focused_border_style, do: %Style{fg: cyan()}

  @doc """
  Dim border style for inactive panels.

  ## Examples

      iex> BB.TUI.Theme.unfocused_border_style().fg
      :dark_gray
  """
  @spec unfocused_border_style() :: Style.t()
  def unfocused_border_style, do: %Style{fg: dim_border()}

  @doc """
  Returns focused or unfocused border style based on boolean.

  ## Examples

      iex> BB.TUI.Theme.border_style(true) == BB.TUI.Theme.focused_border_style()
      true

      iex> BB.TUI.Theme.border_style(false) == BB.TUI.Theme.unfocused_border_style()
      true
  """
  @spec border_style(boolean()) :: Style.t()
  def border_style(true), do: focused_border_style()
  def border_style(false), do: unfocused_border_style()

  @doc """
  Style for the gauge filled portion — green.

  ## Examples

      iex> BB.TUI.Theme.gauge_filled_style().fg
      :green
  """
  @spec gauge_filled_style() :: Style.t()
  def gauge_filled_style, do: %Style{fg: green()}

  @doc """
  Style for the gauge unfilled portion — dark gray.

  ## Examples

      iex> BB.TUI.Theme.gauge_unfilled_style().fg
      :dark_gray
  """
  @spec gauge_unfilled_style() :: Style.t()
  def gauge_unfilled_style, do: %Style{fg: dim_border()}

  @doc """
  Style for simulated joint indicators — yellow.

  ## Examples

      iex> BB.TUI.Theme.sim_style().fg
      :yellow
  """
  @spec sim_style() :: Style.t()
  def sim_style, do: %Style{fg: yellow()}

  @doc """
  Style for event path labels — blue.

  ## Examples

      iex> BB.TUI.Theme.path_style().fg
      :blue
  """
  @spec path_style() :: Style.t()
  def path_style, do: %Style{fg: blue()}

  @doc """
  Bold style for ready commands — green.

  ## Examples

      iex> BB.TUI.Theme.ready_style().fg
      :green
  """
  @spec ready_style() :: Style.t()
  def ready_style, do: %Style{fg: green(), modifiers: [:bold]}

  @doc """
  Style for blocked commands — dark gray.

  ## Examples

      iex> BB.TUI.Theme.blocked_style().fg
      :dark_gray
  """
  @spec blocked_style() :: Style.t()
  def blocked_style, do: %Style{fg: dim_text()}

  @doc """
  Style for parameter values — magenta.

  ## Examples

      iex> BB.TUI.Theme.param_value_style().fg
      :magenta
  """
  @spec param_value_style() :: Style.t()
  def param_value_style, do: %Style{fg: magenta()}
end
