defmodule BB.TUI.Panels.Help do
  @moduledoc """
  Help popup — overlay showing all available keyboard shortcuts.

  Renders the keyboard reference as a list of `%ExRatatui.Text.Line{}`
  rows, with cornflower-bold section headers and the same key-pill
  vocabulary used in the status bar (`BB.TUI.Theme.key_pill/2`,
  `dim_span/1`). Scrollable with `j` / `k` via the Paragraph's
  `:scroll` field.

  Pure function — returns a Popup widget struct.
  """

  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Popup

  @doc """
  Renders the help popup as a Popup widget with optional scroll offset.

  ## Examples

      iex> %ExRatatui.Widgets.Popup{} = BB.TUI.Panels.Help.render(0)

      iex> %ExRatatui.Widgets.Popup{content: %ExRatatui.Widgets.Paragraph{text: lines}} =
      ...>   BB.TUI.Panels.Help.render(0)
      iex> Enum.any?(lines, fn %ExRatatui.Text.Line{spans: spans} ->
      ...>   Enum.any?(spans, &(&1.content == "Global"))
      ...> end)
      true
  """
  @spec render(non_neg_integer()) :: struct()
  def render(scroll_offset \\ 0) do
    content = %Paragraph{
      text: lines(),
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

  defp title_line do
    %Line{
      spans: [
        %Span{content: " 🤖 ", style: %Style{}},
        %Span{content: "Help ", style: %Style{fg: :white, modifiers: [:bold]}}
      ]
    }
  end

  defp lines do
    [
      blank(),
      section("Global"),
      row("q", "Quit", :quit),
      row("Tab", "Cycle active panel"),
      row("?", "Toggle this help"),
      row("a", "Arm robot"),
      row("d", "Disarm robot"),
      row("f", "Force disarm (error state only)"),
      blank(),
      section("Events panel"),
      row("j / ↓", "Scroll down"),
      row("k / ↑", "Scroll up"),
      row("⏎", "Show event details"),
      row("p", "Pause / resume stream"),
      row("c", "Clear all events"),
      blank(),
      section("Commands panel"),
      row("j / ↓", "Select next command"),
      row("k / ↑", "Select previous command"),
      row("⏎", "Execute selected command"),
      blank(),
      section("Joints panel"),
      row("j / ↓", "Select next joint"),
      row("k / ↑", "Select previous joint"),
      row("l / →", "Increase position (1% step)"),
      row("h / ←", "Decrease position (1% step)"),
      row("L", "Increase position (10% step)"),
      row("H", "Decrease position (10% step)"),
      blank(),
      section("Parameters panel"),
      row("j / ↓", "Select next parameter"),
      row("k / ↑", "Select previous parameter"),
      row("l / →", "Increase value (+1 int, +0.1 float)"),
      row("h / ←", "Decrease value (-1 int, -0.1 float)"),
      row("L", "Increase value × 10"),
      row("H", "Decrease value × 10"),
      row("⏎", "Toggle boolean parameter"),
      blank(),
      footer_line()
    ]
  end

  defp section(label) do
    %Line{
      spans: [
        %Span{content: "  ── ", style: %Style{fg: Theme.dim_text()}},
        %Span{content: label, style: %Style{fg: :cyan, modifiers: [:bold]}},
        %Span{content: " ──", style: %Style{fg: Theme.dim_text()}}
      ]
    }
  end

  defp row(keys, description, kind \\ :default) do
    %Line{
      spans: [
        %Span{content: "    ", style: %Style{}},
        Theme.key_pill(keys, kind),
        %Span{content: "  ", style: %Style{}},
        %Span{content: description, style: %Style{fg: :white}}
      ]
    }
  end

  defp blank, do: %Line{spans: [%Span{content: "", style: %Style{}}]}

  defp footer_line do
    %Line{
      spans: [
        %Span{content: "  ", style: %Style{}},
        Theme.key_pill("j/k"),
        %Span{content: "  ", style: %Style{}},
        %Span{content: "scroll", style: %Style{fg: Theme.dim_text()}},
        %Span{content: "    ", style: %Style{}},
        Theme.key_pill("any other"),
        %Span{content: "  ", style: %Style{}},
        %Span{content: "close", style: %Style{fg: Theme.dim_text()}}
      ]
    }
  end
end
