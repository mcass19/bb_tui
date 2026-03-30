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
end
