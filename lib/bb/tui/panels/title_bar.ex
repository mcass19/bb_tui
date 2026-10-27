defmodule BB.TUI.Panels.TitleBar do
  @moduledoc """
  Title bar — single-line branded header at the top of the dashboard.

  Renders a rich-text `%Line{}` via `BB.TUI.Theme.brand_title/2`, so
  the bot icon, `BB.TUI` brand, robot module, and optional `@ node`
  segment each carry their own color and modifier. Under `node:` the
  link's last round trip follows, coloured by how slow it is, or what
  went wrong with it. The whole line sits over `Theme.title_bg/0` for
  visual separation from the panels beneath it.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the title bar as a Paragraph widget. The text is the rich
  `%Line{}` returned by `BB.TUI.Theme.brand_title/2`; the paragraph
  background is `Theme.title_bg/0`.

  ## Examples

      iex> state = %BB.TUI.State{robot: MyApp.Robot, node: nil}
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.TitleBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content)
      " 🤖 BB.TUI · MyApp.Robot"

      iex> state = %BB.TUI.State{robot: MyApp.Robot, node: :"robot@host"}
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.TitleBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "@ robot@host"
      true

      iex> state = %BB.TUI.State{robot: MyApp.Robot, node: :"robot@host", link: {:ok, 800}}
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.TitleBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) |> String.ends_with?("@ robot@host · 0.8 ms")
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{robot: robot, node: node, link: link}) do
    %Line{spans: spans} = Theme.brand_title(robot, node)

    %Paragraph{
      text: %Line{spans: spans ++ link_spans(node, link)},
      style: %Style{bg: Theme.title_bg()}
    }
  end

  @doc """
  The link segment: the last round trip to the robot's node, or what went
  wrong with it. Nothing for a local session, or before the first check.

  ## Examples

      iex> alias BB.TUI.Panels.TitleBar
      iex> TitleBar.link_spans(:"robot@host", {:ok, 4_200}) |> Enum.map_join(& &1.content)
      " · 4.2 ms"
      iex> TitleBar.link_spans(:"robot@host", {:ok, 120_000}) |> Enum.map_join(& &1.content)
      " · 120 ms"
      iex> for rtt <- [20_000, 120_000, 400_000], do: List.last(TitleBar.link_spans(:"robot@host", {:ok, rtt})).style.fg
      [:green, :yellow, :red]
      iex> TitleBar.link_spans(:"robot@host", {:error, :nodedown}) |> Enum.map_join(& &1.content)
      " · link down"
      iex> TitleBar.link_spans(:"robot@host", {:error, :timeout}) |> Enum.map_join(& &1.content)
      " · no reply"
      iex> TitleBar.link_spans(nil, nil)
      []
  """
  @spec link_spans(node() | nil, State.link()) :: [Span.t()]
  def link_spans(nil, _link), do: []
  def link_spans(_node, nil), do: []

  def link_spans(_node, link) do
    {text, color} = link_text(link)

    [
      %Span{content: " · ", style: %Style{fg: Theme.dim_text()}},
      %Span{content: text, style: %Style{fg: color}}
    ]
  end

  defp link_text({:ok, micros}) when micros < 10_000,
    do: {:erlang.float_to_binary(micros / 1000, decimals: 1) <> " ms", Theme.green()}

  defp link_text({:ok, micros}), do: {"#{div(micros, 1000)} ms", rtt_color(micros)}
  defp link_text({:error, :nodedown}), do: {"link down", Theme.red()}
  defp link_text({:error, _reason}), do: {"no reply", Theme.red()}

  defp rtt_color(micros) when micros < 50_000, do: Theme.green()
  defp rtt_color(micros) when micros < 250_000, do: Theme.yellow()
  defp rtt_color(_micros), do: Theme.red()
end
