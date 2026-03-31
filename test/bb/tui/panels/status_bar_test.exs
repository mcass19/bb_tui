defmodule BB.TUI.Panels.StatusBarTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.StatusBar

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

    test "shows safety state indicator" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      widget = StatusBar.render(state)

      assert widget.text =~ "Armed"
    end

    test "shows runtime state" do
      state = Fixtures.sample_state(%{runtime_state: :idle})
      widget = StatusBar.render(state)

      assert widget.text =~ "idle"
    end

    test "shows global key hints" do
      state = Fixtures.sample_state()
      widget = StatusBar.render(state)

      assert widget.text =~ "[q]Quit"
      assert widget.text =~ "[Tab]Panel"
      assert widget.text =~ "[?]Help"
    end

    test "shows panel-specific hints for safety" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      widget = StatusBar.render(state)

      assert widget.text =~ "[a]Arm"
      assert widget.text =~ "[d]Disarm"
    end

    test "shows panel-specific hints for events" do
      state = Fixtures.sample_state(%{active_panel: :events})
      widget = StatusBar.render(state)

      assert widget.text =~ "[p]Pause"
      assert widget.text =~ "[c]Clear"
    end

    test "shows panel-specific hints for commands" do
      state = Fixtures.sample_state(%{active_panel: :commands})
      widget = StatusBar.render(state)

      assert widget.text =~ "[Enter]Execute"
    end

    test "has inverted colors" do
      state = Fixtures.sample_state()
      widget = StatusBar.render(state)

      assert widget.style.fg == :white
      assert widget.style.bg == :dark_gray
    end

    test "shows disarming safety state" do
      state = Fixtures.sample_state(%{safety_state: :disarming})
      widget = StatusBar.render(state)

      assert widget.text =~ "Disarming"
    end

    test "shows error safety state" do
      state = Fixtures.sample_state(%{safety_state: :error})
      widget = StatusBar.render(state)

      assert widget.text =~ "Error"
    end

    test "shows unknown safety state as string" do
      state = Fixtures.sample_state(%{safety_state: :custom_state})
      widget = StatusBar.render(state)

      assert widget.text =~ "custom_state"
    end

    test "shows panel-specific hints for joints" do
      state = Fixtures.sample_state(%{active_panel: :joints})
      widget = StatusBar.render(state)

      assert widget.text =~ "[j/k]Scroll"
    end

    test "shows no panel-specific hints for parameters" do
      state = Fixtures.sample_state(%{active_panel: :parameters})
      widget = StatusBar.render(state)

      # Just global hints, no panel-specific
      assert widget.text =~ "[q]Quit"
    end

    test "shows disarmed safety state" do
      state = Fixtures.sample_state(%{safety_state: :disarmed})
      widget = StatusBar.render(state)

      assert widget.text =~ "Disarmed"
    end

    test "shows no panel-specific hints for unknown panel" do
      state = Fixtures.sample_state(%{active_panel: :unknown_panel})
      widget = StatusBar.render(state)

      assert widget.text =~ "[q]Quit"
    end
  end
end
