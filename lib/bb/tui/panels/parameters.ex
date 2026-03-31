defmodule BB.TUI.Panels.Parameters do
  @moduledoc """
  Parameters panel — displays robot parameters grouped by path.

  Shows parameter paths and their current values in a table format.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @doc """
  Renders the parameters panel as a Table widget with path and value columns.

  ## Examples

      iex> state = %BB.TUI.State{parameters: [{[:speed], 100}, {[:controller, :kp], 0.5}]}
      iex> %ExRatatui.Widgets.Table{header: header} = BB.TUI.Panels.Parameters.render(state, false)
      iex> header
      ["Parameter", "Value"]

      iex> state = %BB.TUI.State{parameters: []}
      iex> %ExRatatui.Widgets.Table{rows: rows} = BB.TUI.Panels.Parameters.render(state, false)
      iex> rows
      [["No parameters defined", ""]]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(%State{parameters: parameters}, focused?) do
    rows =
      case parameters do
        [] ->
          [["No parameters defined", ""]]

        params ->
          params
          |> Enum.sort_by(fn {path, _} -> path end)
          |> Enum.map(fn {path, value} ->
            [format_path(path), format_value(value)]
          end)
      end

    %Table{
      rows: rows,
      header: ["Parameter", "Value"],
      widths: [
        {:percentage, 55},
        {:percentage, 45}
      ],
      highlight_style: Theme.highlight_style(),
      block: %Block{
        title: title(length(parameters)),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Builds the panel title with parameter count.

  ## Examples

      iex> BB.TUI.Panels.Parameters.title(0)
      " Parameters "

      iex> BB.TUI.Panels.Parameters.title(5)
      " Parameters (5) "
  """
  @spec title(non_neg_integer()) :: String.t()
  def title(0), do: " Parameters "
  def title(count), do: " Parameters (#{count}) "

  @doc """
  Formats a parameter path list as a dot-separated string.

  ## Examples

      iex> BB.TUI.Panels.Parameters.format_path([:controller, :kp])
      "controller.kp"

      iex> BB.TUI.Panels.Parameters.format_path([:speed])
      "speed"
  """
  @spec format_path(list()) :: String.t()
  def format_path(path) when is_list(path) do
    path |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  @doc """
  Formats a parameter value for display.

  ## Examples

      iex> BB.TUI.Panels.Parameters.format_value(42)
      "42"

      iex> BB.TUI.Panels.Parameters.format_value(3.14159)
      "3.142"

      iex> BB.TUI.Panels.Parameters.format_value(true)
      "true"

      iex> BB.TUI.Panels.Parameters.format_value(:fast)
      ":fast"
  """
  @spec format_value(term()) :: String.t()
  def format_value(val) when is_float(val) do
    :erlang.float_to_binary(val, decimals: 3)
  end

  def format_value(val) when is_integer(val), do: Integer.to_string(val)
  def format_value(val) when is_boolean(val), do: to_string(val)
  def format_value(val) when is_atom(val), do: inspect(val)
  def format_value(val), do: inspect(val, pretty: false, limit: 30)
end
