defmodule BB.TUI.Panels.Parameters do
  @moduledoc """
  Parameters panel — displays robot parameters grouped by path.

  Renders a tab strip in the title when remote bridges have been
  discovered. The `Local` tab shows parameters from `state.parameters`
  (with schema metadata from `state.parameter_metadata`). Bridge tabs
  show entries from `state.remote_parameters[bridge_name]`, which the
  app populates by calling `BB.Parameter.list_remote/2` whenever the
  user switches to that tab.

  Pure function — takes state, returns a widget struct.
  """

  alias BB.TUI.State
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Table

  @doc """
  Renders the parameters panel as a Table widget. Columns depend on the
  selected tab: the local tab shows `Parameter | Value | Type`, while a
  bridge tab shows `Parameter | Value | Type` populated from the remote
  fetch result.

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
  def render(state, focused?) do
    tab = State.selected_parameter_tab(state)
    {rows, count} = rows_and_count(state, tab)

    %Table{
      rows: rows,
      header: ["Parameter", "Value", "Type"],
      widths: [
        {:percentage, 45},
        {:percentage, 30},
        {:percentage, 25}
      ],
      selected: if(focused? and selectable_rows?(rows), do: state.param_selected),
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: title_line(state.parameter_tabs, state.parameter_tab_selected, count),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(focused?)
      }
    }
  end

  defp rows_and_count(state, :local) do
    case state.parameters do
      [] ->
        {[["No parameters defined", "", ""]], 0}

      params ->
        sorted = Enum.sort_by(params, fn {path, _} -> path end)

        rows =
          Enum.map(sorted, fn {path, value} ->
            [
              format_path(path),
              format_value(value) <> edit_hint(value),
              format_type(state.parameter_metadata[path])
            ]
          end)

        {rows, length(sorted)}
    end
  end

  defp rows_and_count(state, {:bridge, name}) do
    case state.remote_parameters[name] do
      nil ->
        {[["Loading…", "", ""]], 0}

      {:error, reason} ->
        {[["Error: #{inspect(reason)}", "", ""]], 0}

      [] ->
        {[["No remote parameters", "", ""]], 0}

      params when is_list(params) ->
        sorted = Enum.sort_by(params, &remote_id_string/1)
        rows = Enum.map(sorted, &remote_row/1)
        {rows, length(sorted)}
    end
  end

  defp remote_row(param) do
    [
      remote_id_string(param),
      param |> Map.get(:value) |> format_value() |> append_edit_hint(param),
      format_remote_type(param)
    ]
  end

  defp remote_id_string(%{id: id}) when is_binary(id), do: id
  defp remote_id_string(%{id: id}), do: to_string(id)
  defp remote_id_string(_), do: ""

  defp append_edit_hint(value_str, %{value: v}) when is_number(v) or is_boolean(v),
    do: value_str <> edit_hint(v)

  defp append_edit_hint(value_str, _), do: value_str

  defp format_remote_type(%{type: type}) when is_atom(type) and not is_nil(type),
    do: inspect(type)

  defp format_remote_type(%{type: type}) when is_binary(type), do: type
  defp format_remote_type(_), do: "—"

  defp selectable_rows?([[only_label | _]])
       when only_label in ["No parameters defined", "Loading…", "No remote parameters"],
       do: false

  defp selectable_rows?([[label | _]]) when is_binary(label) do
    not String.starts_with?(label, "Error: ")
  end

  defp selectable_rows?(_), do: true

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
  Builds the panel title as a rich `%Line{}` carrying the tab strip.

  Single-tab (local-only) state renders as ` Parameters (N) ` with a
  bold-cyan count. Multi-tab state renders ` Parameters · Local | mavlink ` etc.,
  with the active tab bold-cyan and a trailing `[t]` hint that mirrors
  the keybinding documented in the README.

  ## Examples

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Panels.Parameters.title_line([:local], 0, 5)
      iex> Enum.map_join(spans, "", & &1.content)
      " Parameters (5) "

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Panels.Parameters.title_line([:local], 0, 0)
      iex> Enum.map_join(spans, "", & &1.content)
      " Parameters "

      iex> %ExRatatui.Text.Line{spans: spans} =
      ...>   BB.TUI.Panels.Parameters.title_line([:local, {:bridge, :mavlink}], 1, 12)
      iex> Enum.map_join(spans, "", & &1.content)
      " Parameters · Local | mavlink (12) [t] "
  """
  @spec title_line([atom() | {:bridge, atom()}], non_neg_integer(), non_neg_integer()) :: Line.t()
  def title_line([:local], _idx, 0) do
    %Line{spans: [%Span{content: " Parameters ", style: %Style{}}]}
  end

  def title_line([:local], _idx, count) do
    %Line{
      spans: [
        %Span{content: " Parameters (", style: %Style{}},
        %Span{
          content: Integer.to_string(count),
          style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
        },
        %Span{content: ") ", style: %Style{}}
      ]
    }
  end

  def title_line(tabs, idx, count) do
    tab_spans =
      tabs
      |> Enum.with_index()
      |> Enum.flat_map(fn {tab, i} -> tab_span(tab, i == idx, count) end)
      |> drop_trailing_separator()

    %Line{
      spans:
        [%Span{content: " Parameters · ", style: %Style{}}] ++
          tab_spans ++ [%Span{content: " [t] ", style: %Style{fg: Theme.dim_text()}}]
    }
  end

  defp tab_span(:local, active?, count), do: labeled_span("Local", active?, count) ++ separator()

  defp tab_span({:bridge, name}, active?, count),
    do: labeled_span(Atom.to_string(name), active?, count) ++ separator()

  defp labeled_span(label, true, count) when count > 0 do
    [
      %Span{
        content: "#{label} (#{count})",
        style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
      }
    ]
  end

  defp labeled_span(label, true, _count) do
    [
      %Span{
        content: label,
        style: %Style{fg: Theme.cyan(), modifiers: [:bold]}
      }
    ]
  end

  defp labeled_span(label, false, _count) do
    [%Span{content: label, style: %Style{fg: Theme.dim_text()}}]
  end

  defp separator, do: [%Span{content: " | ", style: %Style{fg: Theme.dim_text()}}]

  # tab_span/3 always emits a `" | "` separator after the tab label, so
  # the last entry in the flat-mapped span list is guaranteed to be a
  # separator we can drop unconditionally.
  defp drop_trailing_separator(spans), do: Enum.drop(spans, -1)

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
