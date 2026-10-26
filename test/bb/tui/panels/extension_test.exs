defmodule BB.TUI.Panels.ExtensionTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Panels.Extension
  doctest BB.TUI.Panels.Hint

  alias BB.TUI.Extension.{Panel, Plot, Readout, Source}
  alias BB.TUI.Panels.Extension
  alias BB.TUI.State
  alias BB.TUI.State.Series
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Chart, Paragraph, Sparkline}

  @area %Rect{x: 0, y: 0, width: 120, height: 30}

  defp state(panels, values \\ %{}) do
    extensions = State.Extensions.reindex(%State.Extensions{panels: panels, values: values})

    %State{
      joints: %State.Joints{entries: %{lean: %{position: :math.pi() / 4}}},
      extensions: extensions
    }
  end

  defp widgets(state, panel, now \\ 0), do: Extension.render_panel(state, panel, @area, now)

  defp texts(widgets), do: for({%Paragraph{text: text}, _rect} <- widgets, do: text)

  defp push(state, key, samples) do
    series =
      Enum.reduce(samples, Map.fetch!(state.extensions.series, key), fn {t, v}, s ->
        Series.push(s, t, v)
      end)

    put_in(state.extensions.series[key], series)
  end

  describe "readouts" do
    test "show the formatted value, or a dim dash before there is one" do
      panel = %Panel{
        name: :balance,
        items: [
          %Readout{label: "lean", source: Source.joint(:lean), unit: :degree, decimals: 1},
          %Readout{label: "target", source: Source.controller(:balancer, :target)}
        ]
      }

      widgets = widgets(state([panel]), panel)

      assert [{%Block{title: " Balance "}, @area} | _] = widgets
      assert texts(widgets) == [" lean", "45.0°", " target", "-"]

      assert [_, {_, %{modifiers: [:bold]}}, _, {_, %{modifiers: []}}] =
               for({%Paragraph{text: t, style: s}, _} <- widgets, do: {t, s})
    end

    test "draw a sparkline of their recent values when asked" do
      readout = %Readout{label: "lean", source: Source.joint(:lean), spark: true}
      panel = %Panel{name: :p, items: [readout]}
      state = state([panel]) |> push({:p, 0, 0}, [{0, 1.0}, {10, 3.0}, {20, 2.0}])

      assert [{%Sparkline{data: [0, 100, 50]}, _rect}] =
               for({%Sparkline{}, _} = w <- widgets(state, panel), do: w)
    end

    test "a sparkline of a flat or empty history stays at the bottom" do
      readout = %Readout{label: "lean", source: Source.joint(:lean), spark: true}
      panel = %Panel{name: :p, items: [readout]}

      assert [{%Sparkline{data: []}, _}] =
               for({%Sparkline{}, _} = w <- widgets(state([panel]), panel), do: w)

      flat = state([panel]) |> push({:p, 0, 0}, [{0, 2.0}, {10, 2.0}])

      assert [{%Sparkline{data: [0, 0]}, _}] =
               for({%Sparkline{}, _} = w <- widgets(flat, panel), do: w)
    end
  end

  describe "plots" do
    setup do
      plot = %Plot{
        label: "lean vs target",
        sources: [Source.joint(:lean), Source.controller(:balancer, :target)],
        window: 5_000
      }

      %{plot: plot, panel: %Panel{name: :p, items: [plot]}}
    end

    test "chart each source's history over the window before now", %{panel: panel} do
      state =
        state([panel])
        |> push({:p, 0, 0}, [{1_000, 0.0}, {3_000, 1.0}])
        |> push({:p, 0, 1}, [{3_000, 2.0}])

      [{%Chart{} = chart, _rect}] = for({%Chart{}, _} = w <- widgets(state, panel, 4_000), do: w)

      assert [
               %{name: "lean", data: [{-3.0, 0.0}, {-1.0, 1.0}]},
               %{name: "target", data: [{-1.0, 2.0}]}
             ] =
               chart.datasets

      assert chart.x_axis.bounds == {-5.0, 0.0}
      assert chart.x_axis.labels == ["-5s", "now"]
      # Fitted to 0..2 with 10% room either side.
      assert chart.y_axis.bounds == {-0.2, 2.2}
      assert chart.block.title == " lean vs target "
    end

    test "a fixed y range wins, and a flat or empty chart still has a range", %{plot: plot} do
      fixed = %Panel{name: :p, items: [%{plot | y_range: {-1, 1}}]}
      [{chart, _}] = for({%Chart{}, _} = w <- widgets(state([fixed]), fixed), do: w)
      assert chart.y_axis.bounds == {-1.0, 1.0}

      panel = %Panel{name: :p, items: [plot]}
      [{empty, _}] = for({%Chart{}, _} = w <- widgets(state([panel]), panel), do: w)
      assert empty.y_axis.bounds == {0.0, 1.0}

      flat = state([panel]) |> push({:p, 0, 0}, [{0, 3.0}])
      [{flat_chart, _}] = for({%Chart{}, _} = w <- widgets(flat, panel, 100), do: w)
      assert flat_chart.y_axis.bounds == {2.0, 4.0}
    end

    test "a frozen chart ends where it was frozen and says so", %{panel: panel} do
      state = state([panel]) |> push({:p, 0, 0}, [{1_000, 0.0}])
      state = put_in(state.extensions.frozen_at, 2_000)

      [{chart, _}] = for({%Chart{}, _} = w <- widgets(state, panel, 60_000), do: w)

      assert [%{data: [{-1.0, 0.0}]}, _] = chart.datasets
      assert chart.x_axis.labels == ["-5s", "frozen"]
      assert chart.block.title =~ "frozen"
    end

    test "a window that isn't whole seconds keeps its fraction", %{plot: plot} do
      panel = %Panel{name: :p, items: [%{plot | window: 2_500}]}
      [{chart, _}] = for({%Chart{}, _} = w <- widgets(state([panel]), panel), do: w)
      assert chart.x_axis.labels == ["-2.5s", "now"]
    end
  end

  test "lays out up to three panels a row" do
    panels = for name <- [:a, :b, :c, :d], do: %Panel{name: name, tab: :t}

    rects =
      for {%Block{}, rect} <- Extension.render_tab(state(panels), :t, @area, 0), do: rect

    assert [%{y: 0}, %{y: 0}, %{y: 0}, %{y: 15, width: 120}] = rects
  end

  test "an empty panel is just its border" do
    panel = %Panel{name: :empty}
    assert [{%Block{}, _}] = widgets(state([panel]), panel)
  end
end
