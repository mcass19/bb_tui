defmodule BB.TUI.Panels.StatusBarTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.StatusBar

  alias BB.TUI.Panels.StatusBar
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Paragraph

  # Flatten the rich-text Line back to a single string for substring
  # assertions. Each pill / dim segment carries its own color, but the
  # text content is what users actually read.
  defp text(%Paragraph{text: %Line{spans: spans}}) do
    Enum.map_join(spans, "", & &1.content)
  end

  describe "render/1" do
    test "shows robot module name" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot})
      widget = StatusBar.render(state)

      assert %Paragraph{} = widget
      assert text(widget) =~ "MyApp.Robot"
    end

    test "shows safety badge for armed state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      assert text(StatusBar.render(state)) =~ "ARMED"
    end

    test "shows runtime state pill" do
      state = Fixtures.sample_state(%{runtime_state: :idle})
      assert text(StatusBar.render(state)) =~ "idle"
    end

    test "shows global key pills (Tab / ? / q)" do
      state = Fixtures.sample_state()
      txt = text(StatusBar.render(state))

      assert txt =~ " Tab "
      assert txt =~ " panel"
      assert txt =~ " ? "
      assert txt =~ " help"
      assert txt =~ " q "
      assert txt =~ " quit"
    end

    test "shows safety panel hints (arm / disarm)" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      txt = text(StatusBar.render(state))

      assert txt =~ " a "
      assert txt =~ " arm "
      assert txt =~ " d "
      assert txt =~ " disarm "
    end

    test "shows events panel hints (scroll / pause / clear / detail)" do
      state = Fixtures.sample_state(%{active_panel: :events})
      txt = text(StatusBar.render(state))

      assert txt =~ "scroll"
      assert txt =~ "pause"
      assert txt =~ "clear"
      assert txt =~ "detail"
    end

    test "shows commands panel hints (select / execute)" do
      state = Fixtures.sample_state(%{active_panel: :commands})
      txt = text(StatusBar.render(state))

      assert txt =~ "select"
      assert txt =~ "execute"
    end

    test "uses no paragraph background — pills carry the visual identity" do
      widget = StatusBar.render(Fixtures.sample_state())
      # A `bg: :dark_gray` strip would clash with the dim-gray descriptor
      # spans next to each pill (dark-on-dark renders blank). Each pill
      # sets its own bg, so the paragraph stays unstyled.
      assert widget.style == %ExRatatui.Style{}
    end

    test "shows DISARMING safety badge" do
      state = Fixtures.sample_state(%{safety_state: :disarming})
      assert text(StatusBar.render(state)) =~ "DISARMING"
    end

    test "shows ERROR safety badge" do
      state = Fixtures.sample_state(%{safety_state: :error})
      assert text(StatusBar.render(state)) =~ "ERROR"
    end

    test "renders unknown safety state as plain text" do
      state = Fixtures.sample_state(%{safety_state: :custom_state})
      assert text(StatusBar.render(state)) =~ "custom_state"
    end

    test "shows joints panel hints when not armed (select only)" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :disarmed})
      txt = text(StatusBar.render(state))

      assert txt =~ "j/k"
      assert txt =~ "select"
      refute txt =~ "adjust"
    end

    test "shows joints adjustment hints when armed" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :armed})
      txt = text(StatusBar.render(state))

      assert txt =~ "h/l"
      assert txt =~ "adjust"
      assert txt =~ "H/L"
      assert txt =~ "10×"
    end

    test "shows joints adjustment hints when disarming" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :disarming})
      txt = text(StatusBar.render(state))

      assert txt =~ "h/l"
      assert txt =~ "adjust"
    end

    test "shows parameters panel hints (select / adjust / toggle)" do
      state = Fixtures.sample_state(%{active_panel: :parameters})
      txt = text(StatusBar.render(state))

      assert txt =~ "select"
      assert txt =~ "adjust"
      assert txt =~ "toggle"
    end

    test "shows Disarmed dim badge" do
      state = Fixtures.sample_state(%{safety_state: :disarmed})
      assert text(StatusBar.render(state)) =~ "Disarmed"
    end

    test "still shows global pills for an unknown panel" do
      state = Fixtures.sample_state(%{active_panel: :unknown_panel})
      assert text(StatusBar.render(state)) =~ " q "
    end
  end
end
