defmodule BB.TUI.Panels.DriveTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Panels.Drive

  alias BB.TUI.Extension.{Panel, Readout, Source}
  alias BB.TUI.Panels.Drive
  alias BB.TUI.State
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.{Block, Paragraph}

  @area %Rect{x: 0, y: 0, width: 100, height: 24}
  @drive %{publish: {M, :f}, stop: {M, :g}, throttle_scale: 0.5, turn_scale: 2.0, rate: 25}

  defp state(drive_state, panels \\ []) do
    %State{
      drive: drive_state,
      extensions: %State.Extensions{drive: @drive, panels: panels}
    }
  end

  defp pad_text(widgets) do
    [{%Paragraph{text: lines}, _} | _] = widgets

    Enum.map_join(lines, "\n", fn %Line{spans: spans} ->
      Enum.map_join(spans, "", & &1.content)
    end)
  end

  test "lights the held arrows and shows the scaled command" do
    drive = State.Drive.press(%State.Drive{}, "down", 0) |> State.Drive.press("right", 0)
    text = state(drive) |> Drive.render(@area, 0) |> pad_text()

    assert text =~ "█████│····· -0.50"
    assert text =~ "·····│█████ -2.00"
    assert text =~ "25 Hz"
    assert text =~ "repeat (no key releases)"
  end

  test "says when it has seen key releases" do
    text = state(%State.Drive{mode: :release}) |> Drive.render(@area, 0) |> pad_text()
    assert text =~ "release"
    refute text =~ "no key releases"
  end

  test "puts the extensions' drive panels beside the pad" do
    panel = %Panel{
      name: :arm,
      tab: :drive,
      items: [%Readout{label: "lean", source: Source.joint(:lean)}]
    }

    widgets = state(%State.Drive{}, [panel]) |> Drive.render(@area, 0)

    assert [{%Paragraph{}, %{width: 34}}, {%Block{title: " Arm "}, %{x: 34}} | _] = widgets
  end
end
