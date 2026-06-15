defmodule BB.TUI.Panels.TabBarTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Panels.TabBar
  alias BB.TUI.Theme
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Paragraph

  test "renders both tab labels" do
    %Paragraph{text: %Line{spans: spans}} = TabBar.render(:control)
    text = Enum.map_join(spans, "", & &1.content)
    assert text =~ "Control Panel"
    assert text =~ "Visualization"
  end

  test "styles the active tab and dims the inactive one" do
    %Paragraph{text: %Line{spans: spans}} = TabBar.render(:visualization)

    active = Enum.find(spans, &(&1.content =~ "Visualization"))
    inactive = Enum.find(spans, &(&1.content =~ "Control Panel"))

    assert active.style == Theme.tab_active_style()
    assert inactive.style == Theme.tab_inactive_style()
  end
end
