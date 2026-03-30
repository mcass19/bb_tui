defmodule BB.TUI.Panels.RuntimeTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Runtime

  alias BB.TUI.Panels.Runtime
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.Paragraph

  describe "render/1" do
    test "shows idle state" do
      state = Fixtures.sample_state(%{runtime_state: :idle})
      widget = Runtime.render(state)

      assert %Paragraph{} = widget
      assert widget.text == "Idle"
    end

    test "shows executing state" do
      state = Fixtures.sample_state(%{runtime_state: :executing})
      widget = Runtime.render(state)

      assert widget.text == "Executing..."
      assert :bold in widget.style.modifiers
    end

    test "shows disarmed state" do
      state = Fixtures.sample_state(%{runtime_state: :disarmed})
      widget = Runtime.render(state)

      assert widget.text == "Disarmed"
    end

    test "shows error state" do
      state = Fixtures.sample_state(%{runtime_state: :error})
      widget = Runtime.render(state)

      assert widget.text == "Error"
    end

    test "shows custom atom state" do
      state = Fixtures.sample_state(%{runtime_state: :calibrating})
      widget = Runtime.render(state)

      assert widget.text == "calibrating"
    end

    test "has Runtime title" do
      state = Fixtures.sample_state()
      widget = Runtime.render(state)

      assert widget.block.title == " Runtime "
    end
  end
end
