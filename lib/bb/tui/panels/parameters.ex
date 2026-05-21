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
  Renders the parameters panel as a Table widget with path, value, and
  schema-declared type columns.

  When `state.parameter_metadata` carries no entry for a path (e.g. the
  parameter was registered without a Spark schema), the Type column
  falls back to `"—"`.

  ## Examples

      iex> state = %BB.TUI.State{parameters: [{[:speed], 100}, {[:controller, :kp], 0.5}]}
      iex> %ExRatatui.Widgets.Table{header: header} = BB.TUI.Panels.Parameters.render(state, false)
      iex> header
      ["Parameter", "Value", "Type"]

      iex> state = %BB.TUI.State{parameters: []}
      iex> %ExRatatui.Widgets.Table{rows: rows} = BB.TUI.Panels.Parameters.render(state, false)
      iex> rows
      [["No parameters defined", "", ""]]
  """
  @spec render(State.t(), boolean()) :: struct()
  def render(
        %State{parameters: parameters, parameter_metadata: meta, param_selected: selected},
        focused?
      ) do
    rows =
      case parameters do
        [] ->
          [["No parameters defined", "", ""]]

        params ->
          params
          |> Enum.sort_by(fn {path, _} -> path end)
          |> Enum.map(fn {path, value} ->
            [
              format_path(path),
              format_value(value) <> edit_hint(value),
              format_type(meta[path])
            ]
          end)
      end

    %Table{
      rows: rows,
      header: ["Parameter", "Value", "Type"],
      widths: [
        {:percentage, 45},
        {:percentage, 30},
        {:percentage, 25}
      ],
      selected: if(focused? and parameters != [], do: selected),
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: title(length(parameters)),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  @doc """
  Formats a parameter's Spark-declared type for the Type column.

  Returns `"—"` when no schema metadata is present. Atom types render as
  `":float"`; option-tagged types like `{:integer, [min: 0, max: 100]}`
  render as their head atom — the bounds belong in the (future) edit
  popup, not in a one-line table cell.

  ## Examples

      iex> BB.TUI.Panels.Parameters.format_type(nil)
      "—"

      iex> BB.TUI.Panels.Parameters.format_type(%{type: nil})
      "—"

      iex> BB.TUI.Panels.Parameters.format_type(%{type: :float})
      ":float"

      iex> BB.TUI.Panels.Parameters.format_type(%{type: {:integer, [min: 0, max: 100]}})
      ":integer"

      iex> BB.TUI.Panels.Parameters.format_type(%{type: {:custom, MyMod, :validate, []}})
      "{:custom, MyMod, :validate, []}"

      iex> BB.TUI.Panels.Parameters.format_type(%{})
      "—"
  """
  @spec format_type(map() | nil) :: String.t()
  def format_type(nil), do: "—"
  def format_type(%{type: nil}), do: "—"
  def format_type(%{type: type}) when is_atom(type), do: inspect(type)
  def format_type(%{type: {head, opts}}) when is_atom(head) and is_list(opts), do: inspect(head)
  def format_type(%{type: other}), do: inspect(other)
  def format_type(_), do: "—"

  @doc """
  Returns an edit hint suffix indicating how a parameter can be edited.

  ## Examples

      iex> BB.TUI.Panels.Parameters.edit_hint(42)
      " [h/l]"

      iex> BB.TUI.Panels.Parameters.edit_hint(3.14)
      " [h/l]"

      iex> BB.TUI.Panels.Parameters.edit_hint(true)
      " [enter]"

      iex> BB.TUI.Panels.Parameters.edit_hint(:fast)
      ""
  """
  @spec edit_hint(term()) :: String.t()
  def edit_hint(val) when is_number(val), do: " [h/l]"
  def edit_hint(val) when is_boolean(val), do: " [enter]"
  def edit_hint(_val), do: ""

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
    Enum.map_join(path, ".", &to_string/1)
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
