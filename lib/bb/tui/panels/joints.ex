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
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @bar_width 16

  @doc """
  Renders the joints panel as a Table widget with columns for
  name, type, position with units, and a visual position bar.

  ## Examples

      iex> joints = %{shoulder: %{joint: %{name: :shoulder, type: :revolute, limit: %{lower: -1.57, upper: 1.57}}, position: 0.0}}
      iex> state = %BB.TUI.State{joints: joints}
      iex> %ExRatatui.Widgets.Table{header: header} = BB.TUI.Panels.Joints.render(state, false)
      iex> header
      ["Joint", "Type", "Position", "Range"]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{joints: joints, joint_selected: selected}, focused?) do
    rows =
      joints
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, %{position: pos, joint: joint}} ->
        [
          format_name(name, joint),
          format_type(joint),
          format_position(pos, joint),
          position_bar(pos, joint)
        ]
      end)

    %Table{
      rows: rows,
      header: ["Joint", "Type", "Position", "Range"],
      widths: [
        {:percentage, 25},
        {:percentage, 10},
        {:percentage, 20},
        {:min, @bar_width + 2}
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

  ## Examples

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{actuator: nil})
      "elbow SIM"

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{actuator: :some_actuator})
      "elbow"

      iex> BB.TUI.Panels.Joints.format_name(:elbow, %{})
      "elbow"
  """
  @spec format_name(atom(), map()) :: String.t()
  def format_name(name, joint) do
    base = to_string(name)

    if Map.get(joint, :actuator) == nil and Map.has_key?(joint, :actuator) do
      base <> " SIM"
    else
      base
    end
  end

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
  Builds a text-based position bar showing where the joint is within its limits.

  ## Examples

      iex> joint = %{type: :revolute, limit: %{lower: -1.5708, upper: 1.5708}}
      iex> bar = BB.TUI.Panels.Joints.position_bar(0.0, joint)
      iex> String.length(bar)
      16

      iex> BB.TUI.Panels.Joints.position_bar(0.0, %{type: :continuous})
      ""
  """
  @spec position_bar(number() | nil, map()) :: String.t()
  def position_bar(nil, _joint), do: ""
  def position_bar(_pos, %{type: :continuous}), do: ""

  def position_bar(pos, joint) do
    case get_limits(joint) do
      {lower, upper} when upper > lower ->
        ratio = (pos - lower) / (upper - lower)
        ratio = max(0.0, min(1.0, ratio))
        filled = round(ratio * @bar_width)
        unfilled = @bar_width - filled
        String.duplicate("\u{2588}", filled) <> String.duplicate("\u{2591}", unfilled)

      _ ->
        ""
    end
  end

  defp get_limits(%{limit: %{lower: lower, upper: upper}}), do: {lower, upper}
  defp get_limits(_), do: nil

  defp float_to_str(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 1)
  defp float_to_str(val) when is_integer(val), do: "#{val}.0"
end
