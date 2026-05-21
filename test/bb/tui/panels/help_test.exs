defmodule BB.TUI.Panels.HelpTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Help

  alias BB.TUI.Panels.Help
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Markdown
  alias ExRatatui.Widgets.Popup

  describe "render/0" do
    test "returns a Popup wrapping a Markdown widget" do
      assert %Popup{content: %Markdown{}} = Help.render()
    end

    test "markdown content carries every section heading" do
      md = Help.markdown()

      for heading <- [
            "## Global",
            "## Events panel",
            "## Commands panel",
            "## Command edit mode",
            "## Joints panel",
            "## Parameters panel"
          ] do
        assert md =~ heading
      end
    end

    test "markdown content lists every documented keybinding" do
      md = Help.markdown()

      assert md =~ "`q` — Quit"
      assert md =~ "Cycle to the next panel"
      assert md =~ "Cycle to the previous panel"
      assert md =~ "Jump directly to the panel"
      assert md =~ "Arm robot"
      assert md =~ "Disarm robot"
      assert md =~ "Force disarm (error state only)"
      assert md =~ "`t`"
      assert md =~ "Cycle enum value"
    end

    test "title is a rich-text Line containing 'Help'" do
      widget = Help.render()
      assert %Line{spans: title_spans} = widget.block.title
      assert Enum.any?(title_spans, &(&1.content =~ "Help"))
    end

    test "scroll offset flows through to the Markdown widget" do
      widget = Help.render(5)
      assert %Popup{content: %Markdown{scroll: {5, 0}}} = widget
    end
  end
end
