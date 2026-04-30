defmodule BB.TUI.Panels.TitleBarTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.TitleBar

  alias BB.TUI.Panels.TitleBar
  alias BB.TUI.Test.Fixtures
  alias BB.TUI.Theme
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Paragraph

  defp text(%Paragraph{text: %Line{spans: spans}}) do
    Enum.map_join(spans, "", & &1.content)
  end

  describe "render/1" do
    test "shows BB.TUI brand" do
      widget = TitleBar.render(Fixtures.sample_state())
      assert %Paragraph{} = widget
      assert text(widget) =~ "BB.TUI"
    end

    test "shows robot module name" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot})
      assert text(TitleBar.render(state)) =~ "MyApp.Robot"
    end

    test "appends @ node when remote" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot, node: :robot@host})
      assert text(TitleBar.render(state)) =~ "@ robot@host"
    end

    test "no @ node segment when local" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot, node: nil})
      refute text(TitleBar.render(state)) =~ "@"
    end

    test "uses the purple title bar background" do
      widget = TitleBar.render(Fixtures.sample_state())
      assert widget.style.bg == Theme.title_bg()
    end

    test "BB.TUI brand renders bold" do
      %Paragraph{text: %Line{spans: spans}} = TitleBar.render(Fixtures.sample_state())
      brand = Enum.find(spans, &(&1.content == "BB.TUI"))
      assert brand
      assert :bold in brand.style.modifiers
    end
  end
end
