defmodule BB.TUI.ThemeTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Theme

  alias BB.TUI.Theme

  describe "colors" do
    test "returns named atom colors" do
      assert Theme.green() == :green
      assert Theme.red() == :red
      assert Theme.yellow() == :yellow
      assert Theme.cyan() == :cyan
      assert Theme.blue() == :blue
      assert Theme.magenta() == :magenta
      assert Theme.dim_border() == :dark_gray
      assert Theme.dim_text() == :dark_gray
    end
  end

  describe "composite styles" do
    test "armed_style is bold green" do
      style = Theme.armed_style()
      assert style.fg == :green
      assert :bold in style.modifiers
    end

    test "disarmed_style is dim" do
      style = Theme.disarmed_style()
      assert style.fg == :dark_gray
    end

    test "disarming_style is bold yellow" do
      style = Theme.disarming_style()
      assert style.fg == :yellow
      assert :bold in style.modifiers
    end

    test "error_style is bold red" do
      style = Theme.error_style()
      assert style.fg == :red
      assert :bold in style.modifiers
    end

    test "highlight_style is bold cyan" do
      style = Theme.highlight_style()
      assert style.fg == :cyan
      assert :bold in style.modifiers
    end

    test "gauge_filled_style is green" do
      assert Theme.gauge_filled_style().fg == :green
    end

    test "gauge_unfilled_style is dark gray" do
      assert Theme.gauge_unfilled_style().fg == :dark_gray
    end

    test "sim_style is yellow" do
      assert Theme.sim_style().fg == :yellow
    end

    test "path_style is blue" do
      assert Theme.path_style().fg == :blue
    end

    test "ready_style is bold green" do
      style = Theme.ready_style()
      assert style.fg == :green
      assert :bold in style.modifiers
    end

    test "blocked_style is dim" do
      assert Theme.blocked_style().fg == :dark_gray
    end
  end

  describe "border_style/1" do
    test "focused returns cyan" do
      style = Theme.border_style(true)
      assert style.fg == :cyan
    end

    test "unfocused returns dark_gray" do
      style = Theme.border_style(false)
      assert style.fg == :dark_gray
    end

    test "focused matches focused_border_style" do
      assert Theme.border_style(true) == Theme.focused_border_style()
    end

    test "unfocused matches unfocused_border_style" do
      assert Theme.border_style(false) == Theme.unfocused_border_style()
    end
  end

  describe "safety_badge/1" do
    test "renders an unknown safety state as a dim plain-text span" do
      span = Theme.safety_badge(:custom_state)
      assert span.content =~ "custom_state"
      assert span.style.fg == Theme.dim_text()
      assert span.style.bg == nil
    end
  end

  describe "proximity_color/1" do
    test "falls back to dim_text/0 for unknown proximity values" do
      assert Theme.proximity_color(:unexpected) == Theme.dim_text()
    end
  end
end
