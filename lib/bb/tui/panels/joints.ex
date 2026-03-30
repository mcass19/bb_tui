defmodule BB.TUI.Panels.Joints do
  @moduledoc """
  Joints panel — displays a table of joint positions and limits.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @doc """
  Renders the joints panel as a Table widget with columns for
  name, position, min limit, max limit.
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{joints: joints}, focused?) do
    rows =
      joints
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, %{position: pos, joint: joint}} ->
        [
          to_string(name),
          format_position(pos),
          format_limit(joint, :lower),
          format_limit(joint, :upper)
        ]
      end)

    %Table{
      rows: rows,
      header: ["Joint", "Position", "Min", "Max"],
      widths: [
        {:percentage, 30},
        {:percentage, 25},
        {:percentage, 22},
        {:percentage, 23}
      ],
      highlight_style: Theme.highlight_style(),
      block: %Block{
        title: " Joints ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  defp format_position(pos) when is_float(pos), do: :erlang.float_to_binary(pos, decimals: 2)
  defp format_position(pos) when is_integer(pos), do: Integer.to_string(pos)
  defp format_position(_), do: "-"

  defp format_limit(joint, bound) do
    case get_limit(joint, bound) do
      nil -> "-"
      val -> format_position(val)
    end
  end

  defp get_limit(joint, :lower) do
    case Map.get(joint, :limit) do
      %{lower: lower} -> lower
      _ -> nil
    end
  end

  defp get_limit(joint, :upper) do
    case Map.get(joint, :limit) do
      %{upper: upper} -> upper
      _ -> nil
    end
  end
end
