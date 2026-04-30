defmodule BB.TUI.Panels.StatusBar do
  @moduledoc """
  Status bar — single-line bar at the bottom of the dashboard.

  Carries (in order) the robot module, a colored safety badge, a
  runtime-state pill, the global key hints (`Tab` / `q` / `?`), and a
  set of context-sensitive key pills for the active panel.

  Every segment is a `%ExRatatui.Text.Span{}` so each piece can carry
  its own color: the safety badge changes color with the safety
  state (green / yellow / red / dim), key labels render as cyan
  pills (red for `q`), descriptions render dim. See
  `BB.TUI.Theme.brand_title/2`, `safety_badge/1`, `key_pill/2` for
  the underlying primitives.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @doc """
  Renders the status bar as a Paragraph widget.

  ## Examples

      iex> state = %BB.TUI.State{
      ...>   robot: MyApp.Robot, safety_state: :armed,
      ...>   runtime_state: :idle, active_panel: :safety
      ...> }
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.StatusBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "MyApp.Robot"
      true

      iex> state = %BB.TUI.State{
      ...>   robot: MyApp.Robot, safety_state: :armed,
      ...>   runtime_state: :idle, active_panel: :safety
      ...> }
      iex> %ExRatatui.Widgets.Paragraph{text: %ExRatatui.Text.Line{spans: spans}} =
      ...>   BB.TUI.Panels.StatusBar.render(state)
      iex> Enum.map_join(spans, "", & &1.content) =~ "ARMED"
      true
  """
  @spec render(State.t()) :: struct()
  def render(%State{} = state) do
    %Paragraph{
      text: line(state),
      style: %Style{bg: :dark_gray, fg: :white}
    }
  end

  defp line(%State{} = state) do
    spans =
      [
        %Span{
          content: " #{inspect(state.robot)} ",
          style: %Style{fg: :white, modifiers: [:bold]}
        },
        Theme.dim_span("│"),
        %Span{content: " ", style: %Style{}},
        Theme.safety_badge(state.safety_state),
        %Span{content: " ", style: %Style{}},
        Theme.dim_span("│"),
        %Span{content: " ", style: %Style{}},
        runtime_pill(state.runtime_state),
        %Span{content: "  ", style: %Style{}}
      ] ++ key_hints(state)

    %Line{spans: spans}
  end

  defp runtime_pill(runtime_state) do
    %Span{
      content: " #{runtime_state} ",
      style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
    }
  end

  defp key_hints(%State{active_panel: panel, safety_state: safety}) do
    base =
      [
        Theme.key_pill("Tab"),
        Theme.dim_span(" panel "),
        Theme.key_pill("?"),
        Theme.dim_span(" help "),
        Theme.key_pill("q", :quit),
        Theme.dim_span(" quit ")
      ]

    case panel_keys(panel, safety) do
      [] -> base
      extras -> base ++ [Theme.dim_span("  ") | extras]
    end
  end

  defp panel_keys(:safety, _safety) do
    [
      Theme.key_pill("a"),
      Theme.dim_span(" arm "),
      Theme.key_pill("d"),
      Theme.dim_span(" disarm ")
    ]
  end

  defp panel_keys(:commands, _safety) do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" execute ")
    ]
  end

  defp panel_keys(:events, _safety) do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" scroll "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" detail "),
      Theme.key_pill("p"),
      Theme.dim_span(" pause "),
      Theme.key_pill("c"),
      Theme.dim_span(" clear ")
    ]
  end

  defp panel_keys(:joints, safety) when safety in [:armed, :disarming] do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("h/l"),
      Theme.dim_span(" adjust "),
      Theme.key_pill("H/L"),
      Theme.dim_span(" 10× ")
    ]
  end

  defp panel_keys(:joints, _safety) do
    [Theme.key_pill("j/k"), Theme.dim_span(" select ")]
  end

  defp panel_keys(:parameters, _safety) do
    [
      Theme.key_pill("j/k"),
      Theme.dim_span(" select "),
      Theme.key_pill("h/l"),
      Theme.dim_span(" adjust "),
      Theme.key_pill("⏎"),
      Theme.dim_span(" toggle ")
    ]
  end

  defp panel_keys(_, _), do: []
end
