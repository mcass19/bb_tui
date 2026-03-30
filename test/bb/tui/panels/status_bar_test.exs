defmodule BB.TUI.Panels.StatusBarTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.StatusBar
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Paragraph

  describe "render/1" do
    test "shows robot module name" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot})
      widget = StatusBar.render(state)

      assert %Paragraph{} = widget
      assert widget.text =~ "MyApp.Robot"
    end

    test "shows runtime state" do
      state = Fixtures.sample_state(%{runtime_state: :idle})
      widget = StatusBar.render(state)

      assert widget.text =~ "idle"
    end

    test "shows key hints" do
      state = Fixtures.sample_state()
      widget = StatusBar.render(state)

      assert widget.text =~ "[q] Quit"
      assert widget.text =~ "[Tab] Panel"
      assert widget.text =~ "[?] Help"
    end

    test "has inverted colors" do
      state = Fixtures.sample_state()
      widget = StatusBar.render(state)

      assert widget.style.fg == :white
      assert widget.style.bg == :dark_gray
    end
  end
end
