defmodule BB.TUI.Panels.Help do
  @moduledoc """
  Help popup — overlay showing all available keyboard shortcuts.

  Renders the keyboard reference as a single `ExRatatui.Widgets.Markdown`
  widget so the content is a plain markdown string (`@help_markdown`)
  rather than 50+ hand-built `Text.Line` rows. Markdown handles section
  headings, bullet lists, inline code (used for keybindings), and
  scroll offsets natively.

  Pure function — returns a Popup widget struct.
  """

  alias ExRatatui.Style
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Markdown
  alias ExRatatui.Widgets.Popup

  @help_markdown """
  ## Global

  - `q` — Quit
  - `[` / `]` — Switch top-level tab (Control Panel / Visualization)
  - `Tab` — Cycle to the next panel
  - `Shift+Tab` — Cycle to the previous panel
  - `1` / `2` / `3` / `4` / `5` — Jump directly to the panel whose
    title shows the matching `[N]` badge
  - `?` — Toggle this help
  - `a` — Arm robot
  - `d` — Disarm robot
  - `f` — Force disarm (error state only)

  ## Visualization tab

  - `←` / `→` or `h` / `l` — Orbit the camera
  - `↑` / `↓` or `k` / `j` — Tilt the camera
  - `+` / `-` — Zoom in / out
  - `r` — Reset the camera
  - `m` — Cycle render mode (auto / kitty / sixel / iterm2 / half-block / braille / ascii)

  ## Events panel

  - `j` / `↓` — Scroll down
  - `k` / `↑` — Scroll up
  - `⏎` — Show event details
  - `p` — Pause / resume stream
  - `c` — Clear all events

  ## Commands panel

  - `j` / `↓` — Select next command
  - `k` / `↑` — Select previous command
  - `⏎` — Execute (or enter argument edit mode)

  ## Command edit mode

  - `Tab` / `↓` — Focus next argument
  - `Shift+Tab` / `↑` — Focus previous argument
  - `⏎` — Execute with current values
  - `Esc` — Exit edit mode (keeps values)
  - `Backspace` — Delete last char of focused arg
  - `←` / `→` — Cycle enum value (enum-typed args only)
  - `h` / `l` — Cycle enum, or append to non-enum buffer

  ## Joints panel

  - `j` / `↓` — Select next joint
  - `k` / `↑` — Select previous joint
  - `l` / `→` — Increase position (1% of range)
  - `h` / `←` — Decrease position (1% of range)
  - `L` — Increase position (10% of range)
  - `H` — Decrease position (10% of range)

  Commanded targets render as a hollow marker on the position bar.

  ## Parameters panel

  - `j` / `↓` — Select next parameter
  - `k` / `↑` — Select previous parameter
  - `l` / `→` — Increase value (1% of range, or +1 / +0.1 when unbounded)
  - `h` / `←` — Decrease value (1% of range, or -1 / -0.1 when unbounded)
  - `L` — 10× step
  - `H` — 10× step (down)
  - `⏎` — Toggle boolean parameter
  - `t` — Cycle to the next bridge tab

  Bridge-tab edits route through `BB.Parameter.set_remote`.

  ---

  `j` / `k` scroll this popup. Any other key closes it.
  """

  @doc """
  Renders the help popup as a Popup widget with optional scroll offset.

  ## Examples

      iex> %ExRatatui.Widgets.Popup{content: %ExRatatui.Widgets.Markdown{}} =
      ...>   BB.TUI.Panels.Help.render(0)

      iex> %ExRatatui.Widgets.Popup{content: %ExRatatui.Widgets.Markdown{content: md}} =
      ...>   BB.TUI.Panels.Help.render(5)
      iex> md =~ "## Global"
      true
  """
  @spec render(non_neg_integer()) :: struct()
  def render(scroll_offset \\ 0) do
    content = %Markdown{
      content: @help_markdown,
      wrap: true,
      scroll: {scroll_offset, 0}
    }

    %Popup{
      content: content,
      percent_width: 60,
      percent_height: 70,
      block: %Block{
        title: title_line(),
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  @doc """
  Returns the full markdown source rendered inside the popup. Exposed
  so callers (and tests) can introspect the help content without
  spinning up the widget tree.
  """
  @spec markdown() :: String.t()
  def markdown, do: @help_markdown

  defp title_line do
    %Line{
      spans: [
        %Span{content: " 🤖 ", style: %Style{}},
        %Span{content: "Help ", style: %Style{fg: :white, modifiers: [:bold]}}
      ]
    }
  end
end
