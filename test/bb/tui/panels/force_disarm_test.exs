defmodule BB.TUI.Panels.ForceDisarmTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.ForceDisarm
  alias ExRatatui.Widgets.Popup

  describe "render/0" do
    test "returns a Popup widget" do
      widget = ForceDisarm.render()
      assert %Popup{} = widget
    end

    test "contains confirmation text" do
      widget = ForceDisarm.render()

      assert widget.content.text =~ "Force disarm"
      assert widget.content.text =~ "[y] Confirm"
      assert widget.content.text =~ "[n] Cancel"
    end

    test "has red border" do
      widget = ForceDisarm.render()
      assert widget.block.border_style.fg == :red
    end
  end
end
