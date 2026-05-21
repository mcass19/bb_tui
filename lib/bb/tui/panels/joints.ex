defmodule BB.TUI.Panels.Joints do
  @moduledoc """
  Joint control panel — displays joint positions with type, units, and
  visual position bars.

  Shows each joint's name, type (rev/pri/con), current position in
  human-readable units (degrees or mm), and a bar indicating position
  within the joint's limits. Simulated joints are marked with a SIM tag.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @bar_width 16

  @doc """
  Renders the joints panel as a Table widget with columns for
  name, type, position with units, and a visual position bar.

  ## Examples

      iex> joints = %{shoulder: %{joint: %{name: :shoulder, type: :revolute, limits: %{lower: -1.57, upper: 1.57}}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints}
      iex> %ExRatatui.Widgets.Table{header: header} = BB.TUI.Panels.Joints.render(state, false)
      iex> header
      ["Joint", "Type", "Position", "Target"]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{joints: joints, joint_selected: selected}, focused?) do
    rows =
      joints
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, joint_data} ->
        %{position: pos, joint: joint} = joint_data
        target = Map.get(joint_data, :target)
        proximity = State.limit_proximity(pos, joint)

        [
          name_span(name, joint),
          format_type(joint),
          position_span(pos, joint, proximity),
          position_bar_line(pos, joint, proximity, target)
        ]
      end)

    %Table{
      rows: rows,
      header: ["Joint", "Type", "Position", "Target"],
      widths: [
        {:percentage, 20},
        {:percentage, 8},
        {:percentage, 15},
        {:min, @bar_width + 14}
      ],
      selected: if(focused? and rows != [], do: selected),
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: " Joint Control ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Formats a joint name, appending SIM tag for simulated joints.

  A joint is simulated when it has an empty actuators list.

  ## Examples

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{actuators: []})
      "elbow SIM"

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{actuators: [:motor]})
      "elbow"

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{})
      "elbow"
  """
  @spec format_name(atom(), map()) :: String.t()
  def format_name(name, %{actuators: []}), do: to_string(name) <> " SIM"
  def format_name(name, _joint), do: to_string(name)

  @doc """
  Formats the joint type as a short label.

  ## Examples

      iex> BB.TUI.Panels.Joints.format_type(%{type: :revolute})
      "rev"

      iex> BB.TUI.Panels.Joints.format_type(%{type: :prismatic})
      "pri"

      iex> BB.TUI.Panels.Joints.format_type(%{type: :continuous})
      "con"

      iex> BB.TUI.Panels.Joints.format_type(%{type: :fixed})
      "fix"

      iex> BB.TUI.Panels.Joints.format_type(%{})
      "-"
  """
  @spec format_type(map()) :: String.t()
  def format_type(%{type: :revolute}), do: "rev"
  def format_type(%{type: :prismatic}), do: "pri"
  def format_type(%{type: :continuous}), do: "con"
  def format_type(%{type: :fixed}), do: "fix"
  def format_type(_), do: "-"

  @doc """
  Formats position with appropriate units based on joint type.

  Revolute/continuous joints show degrees, prismatic joints show millimeters.

  ## Examples

      iex> BB.TUI.Panels.Joints.format_position(1.5708, %{type: :revolute})
      "90.0\u00B0"

      iex> BB.TUI.Panels.Joints.format_position(0.030, %{type: :prismatic})
      "30.0 mm"

      iex> BB.TUI.Panels.Joints.format_position(nil, %{type: :revolute})
      "N/A"
  """
  @spec format_position(number() | nil, map()) :: String.t()
  def format_position(nil, _joint), do: "N/A"

  def format_position(pos, %{type: :prismatic}) do
    mm = pos * 1000
    "#{float_to_str(mm)} mm"
  end

  def format_position(pos, _joint) do
    degrees = pos * 180.0 / :math.pi()
    "#{float_to_str(degrees)}\u00B0"
  end

  @doc """
  Formats a joint limit value in human-readable units (degrees or mm).

  ## Examples

      iex> BB.TUI.Panels.Joints.format_limit(1.5708, %{type: :revolute})
      "90"

      iex> BB.TUI.Panels.Joints.format_limit(-1.5708, %{type: :revolute})
      "-90"

      iex> BB.TUI.Panels.Joints.format_limit(0.037, %{type: :prismatic})
      "37"
  """
  @spec format_limit(number(), map()) :: String.t()
  def format_limit(val, %{type: :prismatic}) do
    mm = round(val * 1000)
    Integer.to_string(mm)
  end

  def format_limit(val, _joint) do
    degrees = round(val * 180.0 / :math.pi())
    Integer.to_string(degrees)
  end

  defp get_limits(%{limits: %{lower: lower, upper: upper}})
       when not is_nil(lower) and not is_nil(upper),
       do: {lower, upper}

  defp get_limits(_), do: nil

  defp marker_char(:normal), do: "\u{25CF}"
  defp marker_char(:warning), do: "\u{25C6}"
  defp marker_char(:danger), do: "\u{25C9}"

  defp proximity_suffix(:normal), do: ""
  defp proximity_suffix(:warning), do: " !"
  defp proximity_suffix(:danger), do: " !!"

  defp float_to_str(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 1)
  defp float_to_str(val) when is_integer(val), do: "#{val}.0"

  # ── Rich-text cell helpers ─────────────────────────────────

  defp name_span(name, %{actuators: []}) do
    %Line{
      spans: [
        %Span{content: to_string(name), style: %Style{fg: :white}},
        %Span{content: " SIM", style: Theme.sim_style()}
      ]
    }
  end

  defp name_span(name, _joint) do
    %Span{content: to_string(name), style: %Style{fg: :white}}
  end

  defp position_span(pos, joint, proximity) do
    text = format_position(pos, joint) <> proximity_suffix(proximity)
    style = %Style{fg: Theme.proximity_color(proximity), modifiers: position_modifiers(proximity)}
    %Span{content: text, style: style}
  end

  defp position_modifiers(:normal), do: []
  defp position_modifiers(_), do: [:bold]

  defp position_bar_line(nil, _joint, _proximity, _target), do: ""
  defp position_bar_line(_pos, %{type: :continuous}, _proximity, _target), do: ""

  defp position_bar_line(pos, joint, proximity, target) do
    case get_limits(joint) do
      {lower, upper} when upper > lower ->
        marker_pos = ratio_to_cell(pos, lower, upper)
        target_cell = target_cell(target, lower, upper, marker_pos)
        track_spans = bar_track_spans(marker_pos, target_cell, proximity)
        low_label = format_limit(lower, joint)
        high_label = format_limit(upper, joint)

        %Line{
          spans:
            [%Span{content: "#{low_label} ", style: %Style{fg: Theme.dim_text()}}] ++
              track_spans ++
              [%Span{content: " #{high_label}", style: %Style{fg: Theme.dim_text()}}]
        }

      _ ->
        ""
    end
  end

  defp bar_track_spans(marker_pos, target_cell, proximity) do
    marker_style = %Style{fg: Theme.proximity_color(proximity), modifiers: [:bold]}
    marker = marker_char(proximity)

    0..(@bar_width - 1)
    |> Enum.map(&cell_span(&1, marker_pos, marker, marker_style, target_cell))
  end

  defp cell_span(cell, marker_pos, marker, marker_style, _target_cell) when cell == marker_pos,
    do: %Span{content: marker, style: marker_style}

  defp cell_span(cell, _marker_pos, _marker, _marker_style, target_cell) when cell == target_cell,
    do: %Span{content: target_marker(), style: target_style()}

  defp cell_span(_cell, _marker_pos, _marker, _marker_style, _target_cell),
    do: %Span{content: "\u{2500}", style: %Style{fg: Theme.dim_border()}}

  defp ratio_to_cell(value, lower, upper) do
    ratio = (value - lower) / (upper - lower)
    ratio = max(0.0, min(1.0, ratio))
    round(ratio * (@bar_width - 1))
  end

  defp target_cell(nil, _lower, _upper, _marker_cell), do: nil

  defp target_cell(target, lower, upper, marker_cell) do
    cell = ratio_to_cell(target, lower, upper)
    if cell == marker_cell, do: nil, else: cell
  end

  defp target_marker, do: "\u{25CB}"
  defp target_style, do: %Style{fg: Theme.cyan(), modifiers: [:bold]}
end
