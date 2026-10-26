defmodule BB.TUI.Panels.Drive do
  @moduledoc """
  The Drive tab: the drive pad on the left — arrows lit while held, the
  throttle and turn being published, the hold mode and the tick rate — and
  the extensions' `tab :drive` panels beside it.

  Pure function — takes state and the current monotonic time, returns
  `{widget, rect}` pairs.
  """

  alias BB.TUI.Panels.Extension
  alias BB.TUI.State
  alias BB.TUI.State.Drive
  alias BB.TUI.Theme
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph

  @pad_width 34
  @bar_width 10

  @doc """
  Renders the Drive tab over `area`.

  ## Examples

      iex> drive = %{publish: {M, :f}, stop: {M, :g}, throttle_scale: 1.0, turn_scale: 1.0, rate: 20}
      iex> state = %BB.TUI.State{extensions: %BB.TUI.State.Extensions{drive: drive}}
      iex> [{%ExRatatui.Widgets.Paragraph{block: %{title: " Drive "}}, _rect}] =
      ...>   BB.TUI.Panels.Drive.render(state, %ExRatatui.Layout.Rect{x: 0, y: 0, width: 80, height: 20}, 0)
  """
  @spec render(State.t(), Rect.t(), integer()) :: [{struct(), Rect.t()}]
  def render(%State{} = state, %Rect{} = area, now) do
    case State.Extensions.panels_on(state.extensions, :drive) do
      [] ->
        [{pad(state), area}]

      _panels ->
        [pad_area, panels_area] =
          Layout.split(area, :horizontal, [{:length, @pad_width}, {:min, 0}])

        [{pad(state), pad_area} | Extension.render_tab(state, :drive, panels_area, now)]
    end
  end

  defp pad(%State{drive: drive} = state) do
    {throttle, turn} = directions(drive)
    {throttle_value, turn_value} = State.Extensions.drive_command(state, throttle, turn)

    lines = [
      %Line{spans: []},
      centered([arrow(drive, "up", "▲")]),
      %Line{spans: []},
      centered([arrow(drive, "left", "◀"), plain("     "), arrow(drive, "right", "▶")]),
      %Line{spans: []},
      centered([arrow(drive, "down", "▼")]),
      %Line{spans: []},
      bar_line("throttle", throttle, throttle_value),
      # Left turns are positive; the bar follows the arrow, so it fills right
      # for a right turn.
      bar_line("turn    ", -turn, turn_value),
      %Line{spans: []},
      %Line{spans: [dim(" mode  "), mode(drive.mode)]},
      %Line{spans: [dim(" rate  "), plain("#{state.extensions.drive.rate} Hz")]},
      %Line{spans: []},
      %Line{spans: [dim(" hold the arrows to drive")]}
    ]

    %Paragraph{
      text: lines,
      block: %Block{
        title: " Drive ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(drive.driving?)
      }
    }
  end

  defp directions(%Drive{held: held}) do
    {direction(held, :throttle), direction(held, :turn)}
  end

  defp direction(held, axis) do
    case held do
      %{^axis => %{direction: direction}} -> direction
      _ -> 0
    end
  end

  defp arrow(%Drive{held: held}, key, glyph) do
    lit? = Enum.any?(held, fn {_axis, entry} -> entry.key == key end)

    style =
      if lit?,
        do: %Style{fg: Theme.green(), modifiers: [:bold]},
        else: %Style{fg: Theme.dim_text()}

    %Span{content: glyph, style: style}
  end

  # A signed bar: half the cells for each direction, filled from the middle.
  defp bar_line(label, direction, value) do
    half = div(@bar_width, 2)
    {left, right} = {if(direction < 0, do: half, else: 0), if(direction > 0, do: half, else: 0)}

    bar =
      String.duplicate("·", half - left) <>
        String.duplicate("█", left) <>
        "│" <> String.duplicate("█", right) <> String.duplicate("·", half - right)

    %Line{
      spans: [
        dim(" #{label} "),
        %Span{
          content: bar,
          style: %Style{fg: if(direction == 0, do: Theme.dim_text(), else: Theme.green())}
        },
        plain(" " <> :erlang.float_to_binary(value, decimals: 2))
      ]
    }
  end

  defp mode(:release), do: %Span{content: "release", style: %Style{fg: Theme.green()}}

  defp mode(:inference),
    do: %Span{content: "repeat (no key releases)", style: %Style{fg: Theme.yellow()}}

  defp centered(spans), do: %Line{spans: [plain(String.duplicate(" ", 14)) | spans]}

  defp plain(text), do: %Span{content: text}
  defp dim(text), do: %Span{content: text, style: %Style{fg: Theme.dim_text()}}
end
