defmodule BB.TUI.Panels.SafetyTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Safety

  alias BB.TUI.Panels.Safety
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Throbber

  describe "render/2" do
    test "returns Paragraph for armed state with runtime info" do
      state = Fixtures.sample_state(%{safety_state: :armed, runtime_state: :idle})
      widget = Safety.render(state, true)

      assert %Paragraph{} = widget
      assert widget.text =~ "ARMED"
      assert widget.text =~ "Runtime: Idle"
      assert widget.block.title == " Safety "
    end

    test "returns Paragraph for disarmed state" do
      state = Fixtures.sample_state(%{safety_state: :disarmed, runtime_state: :disarmed})
      widget = Safety.render(state, false)

      assert %Paragraph{} = widget
      assert widget.text =~ "DISARMED"
      assert widget.text =~ "Runtime: Disarmed"
    end

    test "returns Throbber for disarming state" do
      state =
        Fixtures.sample_state(%{
          safety_state: :disarming,
          runtime_state: :disarming,
          throbber_step: 3
        })

      widget = Safety.render(state, true)

      assert %Throbber{} = widget
      assert widget.label == "DISARMING"
      assert widget.step == 3
    end

    test "returns Paragraph for error state with force disarm hint" do
      state = Fixtures.sample_state(%{safety_state: :error, runtime_state: :error})
      widget = Safety.render(state, true)

      assert %Paragraph{} = widget
      assert widget.text =~ "ERROR"
      assert widget.text =~ "Runtime: Error"
      assert widget.text =~ "[f] Force Disarm"
    end

    test "hides force disarm hint when not in error state" do
      state = Fixtures.sample_state(%{safety_state: :armed, runtime_state: :idle})
      widget = Safety.render(state, true)

      refute widget.text =~ "[f] Force Disarm"
    end

    test "shows keyboard hints" do
      state = Fixtures.sample_state(%{safety_state: :armed, runtime_state: :idle})
      widget = Safety.render(state, true)

      assert widget.text =~ "[a] Arm"
      assert widget.text =~ "[d] Disarm"
    end

    test "handles unknown safety state" do
      state = Fixtures.sample_state(%{safety_state: :something_new, runtime_state: :something})
      widget = Safety.render(state, false)

      assert %Paragraph{} = widget
      assert widget.text =~ "UNKNOWN"
      assert widget.text =~ "Runtime: something"
    end

    test "shows runtime executing state" do
      state = Fixtures.sample_state(%{safety_state: :armed, runtime_state: :executing})
      widget = Safety.render(state, false)

      assert widget.text =~ "Runtime: Executing..."
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
