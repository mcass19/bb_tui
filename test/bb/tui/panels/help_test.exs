defmodule BB.TUI.Panels.HelpTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Help

  alias BB.TUI.Panels.Help
  alias ExRatatui.Widgets.Popup

  describe "render/0" do
    test "returns a Popup widget" do
      widget = Help.render()
      assert %Popup{} = widget
    end

    test "contains keyboard shortcuts" do
      widget = Help.render()
      content = widget.content

      assert content.text =~ "Tab"
      assert content.text =~ "Quit"
      assert content.text =~ "Arm"
      assert content.text =~ "Disarm"
      assert content.text =~ "Force disarm"
    end

    test "has Help title" do
      widget = Help.render()
      assert widget.block.title == " Help "
    end
  end
end
