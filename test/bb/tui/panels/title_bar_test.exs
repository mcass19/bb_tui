defmodule BB.TUI.Panels.TitleBarTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.TitleBar

  alias BB.TUI.Panels.TitleBar
  alias BB.TUI.Test.Fixtures
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Paragraph

  describe "render/1" do
    test "shows Beam Bots branding" do
      state = Fixtures.sample_state()
      widget = TitleBar.render(state)

      assert %Paragraph{} = widget
      assert widget.text =~ "Beam Bots"
    end

    test "shows robot module name" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot})
      widget = TitleBar.render(state)

      assert widget.text =~ "MyApp.Robot"
    end

    test "is centered and bold" do
      state = Fixtures.sample_state()
      widget = TitleBar.render(state)

      assert widget.alignment == :left
      assert :bold in widget.style.modifiers
    end

    test "uses the purple title palette" do
      state = Fixtures.sample_state()
      widget = TitleBar.render(state)

      assert widget.style.fg == Theme.title_fg()
      assert widget.style.bg == Theme.title_bg()
    end
  end
end
