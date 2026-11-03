defmodule BB.TUI.Panels.ExtensionTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Panels.Extension
  doctest BB.TUI.Panels.Hint

  alias BB.TUI.Extension.{Attitude, Panel, Plot, Readout, Source}
  alias BB.TUI.Panels.Extension
  alias BB.TUI.State
  alias BB.TUI.State.Series
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Canvas, Chart, Paragraph, Sparkline}

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
               %{name: "lean", data: [{-3.0, +0.0}, {-1.0, 1.0}]},
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

      assert [%{data: [{-1.0, +0.0}]}, _] = chart.datasets
      assert chart.x_axis.labels == ["-5s", "frozen"]
      assert chart.block.title =~ "frozen"
    end

    test "a window that isn't whole seconds keeps its fraction", %{plot: plot} do
      panel = %Panel{name: :p, items: [%{plot | window: 2_500}]}
      [{chart, _}] = for({%Chart{}, _} = w <- widgets(state([panel]), panel), do: w)
      assert chart.x_axis.labels == ["-2.5s", "now"]
    end
  end

  describe "attitude indicators" do
    setup do
      attitude = %Attitude{
        label: "attitude",
        pitch: Source.joint(:lean),
        roll: Source.topic([:sensor, :imu], :roll)
      }

      %{attitude: attitude, panel: %Panel{name: :horizon, items: [attitude]}}
    end

    defp horizon(state, panel) do
      [{%Block{}, _}, {%Canvas{} = canvas, _}, {%Paragraph{text: text}, _}] =
        widgets(state, panel)

      lines = for %Canvas.Line{color: :cyan} = line <- canvas.shapes, do: line
      {lines, canvas, text}
    end

    defp tilt(panel, pitch, roll) do
      state = state([panel], %{{:topic, [:sensor, :imu]} => %{roll: roll}})
      put_in(state.joints.entries.lean.position, pitch)
    end

    test "a level robot has the horizon through the centre", %{panel: panel} do
      {[horizon], canvas, text} = horizon(tilt(panel, 0.0, 0.0), panel)

      assert {horizon.y1, horizon.y2} == {0.0, 0.0}
      assert canvas.block.title == " attitude "
      assert text == " pitch 0.0°   roll 0.0°"

      # The aircraft symbol stays put, in yellow.
      assert [_, _] = for(%Canvas.Line{color: :yellow} <- canvas.shapes, do: :wing)

      assert [[{+0.0, +0.0}]] = for(%Canvas.Points{coords: coords} <- canvas.shapes, do: coords)
    end

    # bb's frame: positive pitch, about +Y, tips the nose down — a
    # balancing robot leaning forward.
    test "positive pitch tips the nose down: the horizon rises", %{panel: panel} do
      {[horizon], canvas, text} = horizon(tilt(panel, 10 * :math.pi() / 180, 0.0), panel)

      assert horizon.y1 > 0 and horizon.y1 == horizon.y2
      assert text =~ "pitch 10.0°"

      # Rungs every 10° within the range: one above the horizon, the one
      # 10° below it on the centre, and two more below.
      rungs = for %Canvas.Line{color: :dark_gray, y1: y} <- canvas.shapes, do: y
      assert length(rungs) == 4
      assert Enum.count(rungs, &(&1 > horizon.y1)) == 1
      assert Enum.count(rungs, &(&1 < -0.1)) == 2
    end

    test "negative pitch lifts the nose: the horizon sinks", %{panel: panel} do
      {[horizon], _canvas, _text} = horizon(tilt(panel, -0.2, 0.0), panel)
      assert horizon.y1 < 0
    end

    test "right side down lifts the horizon's right end", %{panel: panel} do
      {[horizon], _canvas, text} = horizon(tilt(panel, 0.0, 0.3), panel)

      assert horizon.x2 > horizon.x1
      assert horizon.y2 > horizon.y1
      assert text =~ "roll 17.2°"
    end

    test "scale flips the angles", %{attitude: attitude} do
      panel = %Panel{name: :horizon, items: [%{attitude | scale: -1}]}
      {[horizon], _canvas, text} = horizon(tilt(panel, 0.0, 0.3), panel)

      assert horizon.y2 < horizon.y1
      assert text =~ "roll -17.2°"
    end

    test "draws only the aircraft until both angles are known", %{panel: panel} do
      {[], canvas, text} = horizon(state([panel]), panel)

      assert Enum.all?(canvas.shapes, &(&1.color == :yellow))
      assert text == " pitch 45.0°   roll -"
    end

    test "an indicator reading only the pitch shows only the pitch", %{attitude: attitude} do
      panel = %Panel{name: :horizon, items: [%{attitude | roll: nil}]}
      {[horizon], _canvas, text} = horizon(state([panel]), panel)

      assert horizon.y1 == horizon.y2
      assert text == " pitch 45.0°"
    end

    test "draws at any angle without leaving its area", %{panel: panel} do
      terminal = ExRatatui.init_test_terminal(40, 12)
      area = %Rect{x: 0, y: 0, width: 40, height: 12}

      for pitch <- [-3.0, -0.5, 0.0, 0.5, 3.0], roll <- [-3.0, 0.0, 1.0, 3.0] do
        state = tilt(panel, pitch, roll)
        assert :ok = ExRatatui.draw(terminal, Extension.render_panel(state, panel, area, 0))
      end

      assert ExRatatui.get_buffer_content(terminal) =~ "attitude"
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
