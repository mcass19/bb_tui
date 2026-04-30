defmodule BB.TUI.Theme do
  @moduledoc """
  Color, style, and rich-text constants for the BB TUI dashboard.

  Provides a consistent visual palette for the robot dashboard.
  All functions are pure and return a color atom, an
  `%ExRatatui.Style{}`, an `%ExRatatui.Text.Span{}`, or an
  `%ExRatatui.Text.Line{}` — never a side effect.

  ## Rich text

    * `brand_title/2` - branded title-bar `%Line{}`
      ("🤖 BB.TUI · MyApp.Robot @ remote@host")
    * `safety_badge/1` - color-coded safety pill (`armed` green-bg,
      `disarmed` dim, `disarming` yellow-bg, `error` red-bg)
    * `key_pill/2` - colored "key" pill `%Span{}` for status / help hints
    * `dim_span/1` - dim-text descriptor span between pills
    * `footer_line/1` - assembles a `%Line{}` from a list of `{keys,
      label}` pairs
    * `proximity_color/1` - foreground color for joint position bars
      based on `BB.TUI.State.limit_proximity/2`
  """

  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}

  # ── Colors ──────────────────────────────────────────────────

  @doc """
  Green for armed/safe states.

  ## Examples

      iex> BB.TUI.Theme.green()
      :green
  """
  @spec green() :: ExRatatui.Style.color()
  def green, do: :green

  @doc """
  Red for error states.

  ## Examples

      iex> BB.TUI.Theme.red()
      :red
  """
  @spec red() :: ExRatatui.Style.color()
  def red, do: :red

  @doc """
  Yellow for transitional states (disarming).

  ## Examples

      iex> BB.TUI.Theme.yellow()
      :yellow
  """
  @spec yellow() :: ExRatatui.Style.color()
  def yellow, do: :yellow

  @doc """
  Cyan for timestamps and active panel borders.

  ## Examples

      iex> BB.TUI.Theme.cyan()
      :cyan
  """
  @spec cyan() :: ExRatatui.Style.color()
  def cyan, do: :cyan

  @doc """
  Blue for interactive elements and paths.

  ## Examples

      iex> BB.TUI.Theme.blue()
      :blue
  """
  @spec blue() :: ExRatatui.Style.color()
  def blue, do: :blue

  @doc """
  Magenta for parameter values and accents.

  ## Examples

      iex> BB.TUI.Theme.magenta()
      :magenta
  """
  @spec magenta() :: ExRatatui.Style.color()
  def magenta, do: :magenta

  @doc """
  Muted border color for inactive panels.

  ## Examples

      iex> BB.TUI.Theme.dim_border()
      :dark_gray
  """
  @spec dim_border() :: ExRatatui.Style.color()
  def dim_border, do: :dark_gray

  @doc """
  Muted text for secondary information.

  ## Examples

      iex> BB.TUI.Theme.dim_text()
      :dark_gray
  """
  @spec dim_text() :: ExRatatui.Style.color()
  def dim_text, do: :dark_gray

  # ── Composite Styles ───────────────────────────────────────

  @doc """
  Bold green style for armed state.

  ## Examples

      iex> style = BB.TUI.Theme.armed_style()
      iex> style.fg
      :green
      iex> style.modifiers
      [:bold]
  """
  @spec armed_style() :: Style.t()
  def armed_style, do: %Style{fg: green(), modifiers: [:bold]}

  @doc """
  Dim style for disarmed state.

  ## Examples

      iex> style = BB.TUI.Theme.disarmed_style()
      iex> style.fg
      :dark_gray
  """
  @spec disarmed_style() :: Style.t()
  def disarmed_style, do: %Style{fg: dim_text()}

  @doc """
  Bold yellow style for disarming state.

  ## Examples

      iex> style = BB.TUI.Theme.disarming_style()
      iex> style.fg
      :yellow
      iex> style.modifiers
      [:bold]
  """
  @spec disarming_style() :: Style.t()
  def disarming_style, do: %Style{fg: yellow(), modifiers: [:bold]}

  @doc """
  Bold red style for error state.

  ## Examples

      iex> style = BB.TUI.Theme.error_style()
      iex> style.fg
      :red
      iex> style.modifiers
      [:bold]
  """
  @spec error_style() :: Style.t()
  def error_style, do: %Style{fg: red(), modifiers: [:bold]}

  @doc """
  Highlight style for selected items.

  ## Examples

      iex> style = BB.TUI.Theme.highlight_style()
      iex> style.fg
      :cyan
      iex> style.modifiers
      [:bold]
  """
  @spec highlight_style() :: Style.t()
  def highlight_style, do: %Style{fg: cyan(), modifiers: [:bold]}

  @doc """
  Cyan border style for the active/focused panel.

  ## Examples

      iex> BB.TUI.Theme.focused_border_style().fg
      :cyan
  """
  @spec focused_border_style() :: Style.t()
  def focused_border_style, do: %Style{fg: cyan()}

  @doc """
  Dim border style for inactive panels.

  ## Examples

      iex> BB.TUI.Theme.unfocused_border_style().fg
      :dark_gray
  """
  @spec unfocused_border_style() :: Style.t()
  def unfocused_border_style, do: %Style{fg: dim_border()}

  @doc """
  Returns focused or unfocused border style based on boolean.

  ## Examples

      iex> BB.TUI.Theme.border_style(true) == BB.TUI.Theme.focused_border_style()
      true

      iex> BB.TUI.Theme.border_style(false) == BB.TUI.Theme.unfocused_border_style()
      true
  """
  @spec border_style(boolean()) :: Style.t()
  def border_style(true), do: focused_border_style()
  def border_style(false), do: unfocused_border_style()

  @doc """
  Style for the gauge filled portion — green.

  ## Examples

      iex> BB.TUI.Theme.gauge_filled_style().fg
      :green
  """
  @spec gauge_filled_style() :: Style.t()
  def gauge_filled_style, do: %Style{fg: green()}

  @doc """
  Style for the gauge unfilled portion — dark gray.

  ## Examples

      iex> BB.TUI.Theme.gauge_unfilled_style().fg
      :dark_gray
  """
  @spec gauge_unfilled_style() :: Style.t()
  def gauge_unfilled_style, do: %Style{fg: dim_border()}

  @doc """
  Style for simulated joint indicators — yellow.

  ## Examples

      iex> BB.TUI.Theme.sim_style().fg
      :yellow
  """
  @spec sim_style() :: Style.t()
  def sim_style, do: %Style{fg: yellow()}

  @doc """
  Style for event path labels — blue.

  ## Examples

      iex> BB.TUI.Theme.path_style().fg
      :blue
  """
  @spec path_style() :: Style.t()
  def path_style, do: %Style{fg: blue()}

  @doc """
  Bold style for ready commands — green.

  ## Examples

      iex> BB.TUI.Theme.ready_style().fg
      :green
  """
  @spec ready_style() :: Style.t()
  def ready_style, do: %Style{fg: green(), modifiers: [:bold]}

  @doc """
  Style for blocked commands — dark gray.

  ## Examples

      iex> BB.TUI.Theme.blocked_style().fg
      :dark_gray
  """
  @spec blocked_style() :: Style.t()
  def blocked_style, do: %Style{fg: dim_text()}

  @doc """
  Deep Elixir/BB violet used as the title bar background.

  The hue is inspired by the Elixir logo and the Beam Bots
  hexdocs "purple" badge.

  ## Examples

      iex> BB.TUI.Theme.title_bg()
      {:rgb, 78, 42, 90}
  """
  @spec title_bg() :: ExRatatui.Style.color()
  def title_bg, do: {:rgb, 78, 42, 90}

  @doc """
  Light lavender foreground used on top of the title bar background.

  ## Examples

      iex> BB.TUI.Theme.title_fg()
      {:rgb, 230, 210, 245}
  """
  @spec title_fg() :: ExRatatui.Style.color()
  def title_fg, do: {:rgb, 230, 210, 245}

  # ── Rich Text ──────────────────────────────────────────────

  @doc ~S"""
  Branded title-bar line — `🤖 BB.TUI · MyApp.Robot[ @ node]`.

  `BB.TUI` renders bold over `title_fg/0`; the robot module renders
  bold cyan; the optional `@ node` segment trails in dim text.

  ## Examples

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Theme.brand_title(MyApp.Robot, nil)
      iex> Enum.map(spans, & &1.content)
      [" 🤖 ", "BB.TUI", " · ", "MyApp.Robot"]

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Theme.brand_title(MyApp.Robot, :"robot@host")
      iex> Enum.map_join(spans, "", & &1.content)
      " 🤖 BB.TUI · MyApp.Robot @ robot@host"
  """
  @spec brand_title(module(), node() | nil) :: Line.t()
  def brand_title(robot, node) when is_atom(robot) do
    base = [
      %Span{content: " 🤖 ", style: %Style{}},
      %Span{content: "BB.TUI", style: %Style{fg: title_fg(), modifiers: [:bold]}},
      %Span{content: " · ", style: %Style{fg: dim_text()}},
      %Span{content: inspect(robot), style: %Style{fg: cyan(), modifiers: [:bold]}}
    ]

    spans =
      case node do
        nil ->
          base

        n when is_atom(n) ->
          base ++
            [
              %Span{content: " @ ", style: %Style{fg: dim_text()}},
              %Span{content: Atom.to_string(n), style: %Style{fg: dim_text()}}
            ]
      end

    %Line{spans: spans}
  end

  @doc ~S"""
  Color-coded safety badge — a single `%Span{}` pill that reads the
  current safety state at a glance.

  | state        | bg     | fg     |
  | ------------ | ------ | ------ |
  | `:armed`     | green  | black  |
  | `:disarmed`  | none   | dim    |
  | `:disarming` | yellow | black  |
  | `:error`     | red    | white  |

  ## Examples

      iex> badge = BB.TUI.Theme.safety_badge(:armed)
      iex> badge.content
      " ● ARMED "
      iex> badge.style.bg
      :green

      iex> badge = BB.TUI.Theme.safety_badge(:error)
      iex> badge.content
      " ✖ ERROR "
      iex> badge.style.bg
      :red

      iex> BB.TUI.Theme.safety_badge(:disarmed).style.bg
      nil
  """
  @spec safety_badge(atom()) :: Span.t()
  def safety_badge(:armed) do
    %Span{content: " ● ARMED ", style: %Style{bg: green(), fg: :black, modifiers: [:bold]}}
  end

  def safety_badge(:disarming) do
    %Span{
      content: " ● DISARMING ",
      style: %Style{bg: yellow(), fg: :black, modifiers: [:bold]}
    }
  end

  def safety_badge(:error) do
    %Span{content: " ✖ ERROR ", style: %Style{bg: red(), fg: :white, modifiers: [:bold]}}
  end

  def safety_badge(:disarmed) do
    %Span{content: " ○ Disarmed ", style: %Style{fg: dim_text()}}
  end

  def safety_badge(other) do
    %Span{content: " #{other} ", style: %Style{fg: dim_text()}}
  end

  @doc ~S"""
  Colored "key" pill — keys render bold over a colored background,
  used in the status bar and help hints.

  Pass `:quit` for the warning red pill (used for `q`); any other
  atom uses the calm cyan pill.

  ## Examples

      iex> pill = BB.TUI.Theme.key_pill("Tab")
      iex> pill.content
      " Tab "
      iex> pill.style.bg
      :cyan

      iex> pill = BB.TUI.Theme.key_pill("q", :quit)
      iex> pill.style.bg
      :red
      iex> :bold in pill.style.modifiers
      true
  """
  @spec key_pill(String.t(), :default | :quit) :: Span.t()
  def key_pill(label, kind \\ :default) when is_binary(label) do
    style =
      case kind do
        :quit -> %Style{bg: red(), fg: :white, modifiers: [:bold]}
        _ -> %Style{bg: cyan(), fg: :black, modifiers: [:bold]}
      end

    %Span{content: " #{label} ", style: style}
  end

  @doc ~S"""
  Dim span used between key pills.

  ## Examples

      iex> span = BB.TUI.Theme.dim_span(" panels")
      iex> span.content
      " panels"
      iex> span.style.fg == BB.TUI.Theme.dim_text()
      true
  """
  @spec dim_span(String.t()) :: Span.t()
  def dim_span(text) when is_binary(text) do
    %Span{content: text, style: %Style{fg: dim_text()}}
  end

  @doc ~S"""
  Builds a `%Line{}` of `key_pill/2` + `dim_span/1` pairs from a list
  of `{label, description}` entries. Pass a `{label, description,
  :quit}` triple for the warning-red pill.

  ## Examples

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Theme.footer_line([{"Tab", "panel"}, {"q", "quit", :quit}])
      iex> Enum.map_join(spans, "", & &1.content)
      " Tab  panel  q  quit "
  """
  @spec footer_line([{String.t(), String.t()} | {String.t(), String.t(), atom()}]) :: Line.t()
  def footer_line(entries) when is_list(entries) do
    spans =
      Enum.flat_map(entries, fn
        {label, description} ->
          [key_pill(label), dim_span(" #{description} ")]

        {label, description, kind} ->
          [key_pill(label, kind), dim_span(" #{description} ")]
      end)

    %Line{spans: spans}
  end

  @doc ~S"""
  Foreground color for a joint position bar based on its limit
  proximity (the value returned by `BB.TUI.State.limit_proximity/2`).

  | proximity  | color  |
  | ---------- | ------ |
  | `:normal`  | green  |
  | `:warning` | yellow |
  | `:danger`  | red    |

  ## Examples

      iex> BB.TUI.Theme.proximity_color(:normal)
      :green
      iex> BB.TUI.Theme.proximity_color(:warning)
      :yellow
      iex> BB.TUI.Theme.proximity_color(:danger)
      :red
  """
  @spec proximity_color(atom()) :: ExRatatui.Style.color()
  def proximity_color(:normal), do: green()
  def proximity_color(:warning), do: yellow()
  def proximity_color(:danger), do: red()
  def proximity_color(_), do: dim_text()
end
