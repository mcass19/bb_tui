defmodule BB.TUI.Panels.TabBarTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.TabBar
  alias BB.TUI.Theme
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Paragraph

  @tabs [control: "Control Panel", visualization: "Visualization", extension: "Balance"]

  test "renders every tab label" do
    %Paragraph{text: %Line{spans: spans}} = TabBar.render(@tabs, :control)
    text = Enum.map_join(spans, "", & &1.content)
    assert text =~ "Control Panel"
    assert text =~ "Visualization"
    assert text =~ "Balance"
  end

  test "styles the active tab and dims the inactive one" do
    %Paragraph{text: %Line{spans: spans}} = TabBar.render(@tabs, :visualization)

    active = Enum.find(spans, &(&1.content =~ "Visualization"))
    inactive = Enum.find(spans, &(&1.content =~ "Control Panel"))

    assert active.style == Theme.tab_active_style()
    assert inactive.style == Theme.tab_inactive_style()
  end

  test "is as wide as its labels" do
    assert TabBar.width(@tabs) == String.length(" Control Panel   Visualization   Balance ")
    assert TabBar.width([]) == 0
  end
end
