defmodule BB.TUI.Panels.SafetyTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.Safety
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Throbber

  describe "render/2" do
    test "returns Paragraph for armed state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      widget = Safety.render(state, true)

      assert %Paragraph{} = widget
      assert widget.text =~ "ARMED"
      assert widget.block.title == " Safety "
    end

    test "returns Paragraph for disarmed state" do
      state = Fixtures.sample_state(%{safety_state: :disarmed})
      widget = Safety.render(state, false)

      assert %Paragraph{} = widget
      assert widget.text =~ "DISARMED"
    end

    test "returns Throbber for disarming state" do
      state = Fixtures.sample_state(%{safety_state: :disarming, throbber_step: 3})
      widget = Safety.render(state, true)

      assert %Throbber{} = widget
      assert widget.label == "DISARMING"
      assert widget.step == 3
    end

    test "returns Paragraph for error state" do
      state = Fixtures.sample_state(%{safety_state: :error})
      widget = Safety.render(state, true)

      assert %Paragraph{} = widget
      assert widget.text =~ "ERROR"
    end

    test "shows keyboard hints" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      widget = Safety.render(state, true)

      assert widget.text =~ "[a] Arm"
      assert widget.text =~ "[d] Disarm"
      assert widget.text =~ "[f] Force Disarm"
    end

    test "handles unknown safety state" do
      state = Fixtures.sample_state(%{safety_state: :something_new})
      widget = Safety.render(state, false)

      assert %Paragraph{} = widget
      assert widget.text =~ "UNKNOWN"
    end

    test "focused panel gets cyan border" do
      state = Fixtures.sample_state()
      widget = Safety.render(state, true)
      assert widget.block.border_style.fg == :cyan
    end

    test "unfocused panel gets dim border" do
      state = Fixtures.sample_state()
      widget = Safety.render(state, false)
      assert widget.block.border_style.fg == :dark_gray
    end
  end
end
