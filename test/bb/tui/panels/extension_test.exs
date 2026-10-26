defmodule BB.TUI.Panels.ExtensionTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Panels.Extension
  doctest BB.TUI.Panels.Hint

  alias BB.TUI.Extension.{Panel, Plot, Readout, Source}
  alias BB.TUI.Panels.Extension
  alias BB.TUI.State
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Table

  @area %Rect{x: 0, y: 0, width: 120, height: 30}

  defp state(panels, values \\ %{}) do
    %State{
      joints: %State.Joints{entries: %{lean: %{position: :math.pi() / 4}}},
      extensions: %State.Extensions{panels: panels, values: values}
    }
  end

  test "a readout shows its formatted value, bold; a missing one a dim dash" do
    panel = %Panel{
      name: :balance,
      items: [
        %Readout{label: "lean", source: Source.joint(:lean), unit: :degree, decimals: 1},
        %Readout{label: "target", source: Source.controller(:balancer, :target)}
      ]
    }

    %Table{rows: [[_, lean], [_, target]], block: block} = Extension.render(state([panel]), panel)

    assert %Span{content: "45.0°", style: %{modifiers: [:bold]}} = lean
    assert %Span{content: "-"} = target
    assert block.title == " Balance "
  end

  test "a plot shows the latest value of each of its sources" do
    plot = %Plot{
      label: "lean vs target",
      sources: [Source.joint(:lean), Source.controller(:balancer, :target)]
    }

    panel = %Panel{name: :balance, items: [plot]}
    values = %{{:controller, :balancer} => %{target: 0.5}}

    %Table{rows: [[_, value]]} = Extension.render(state([panel], values), panel)
    assert value.content == "0.79 · 0.50"
  end

  test "lays out up to three panels a row" do
    panels = for name <- [:a, :b, :c, :d], do: %Panel{name: name, tab: :t}
    rects = state(panels) |> Extension.render_tab(:t, @area) |> Enum.map(&elem(&1, 1))

    assert [%{y: 0}, %{y: 0}, %{y: 0}, %{y: 15, width: 120}] = rects
  end
end
