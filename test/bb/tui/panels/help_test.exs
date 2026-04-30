defmodule BB.TUI.Panels.HelpTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Help

  alias BB.TUI.Panels.Help
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Popup

  defp text(lines) when is_list(lines) do
    lines
    |> Enum.flat_map(fn %Line{spans: spans} -> spans end)
    |> Enum.map_join("", & &1.content)
  end

  describe "render/0" do
    test "returns a Popup widget" do
      assert %Popup{} = Help.render()
    end

    test "contains keyboard shortcut labels and descriptions" do
      widget = Help.render()
      txt = text(widget.content.text)

      assert txt =~ "Tab"
      assert txt =~ "Quit"
      assert txt =~ "Arm"
      assert txt =~ "Disarm"
      assert txt =~ "Force disarm"
    end

    test "title is a rich-text Line containing 'Help'" do
      widget = Help.render()
      assert %Line{spans: title_spans} = widget.block.title
      assert Enum.any?(title_spans, &(&1.content =~ "Help"))
    end

    test "accepts scroll offset" do
      widget = Help.render(5)
      assert %Popup{} = widget
      assert widget.content.scroll == {5, 0}
    end

    test "has cornflower-bold section headers" do
      widget = Help.render()
      lines = widget.content.text

      assert Enum.any?(lines, fn %Line{spans: spans} ->
               Enum.any?(spans, fn span ->
                 span.content == "Global" and :bold in span.style.modifiers
               end)
             end)
    end
  end
end
