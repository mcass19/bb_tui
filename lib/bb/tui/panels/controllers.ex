defmodule BB.TUI.Panels.Controllers do
  @moduledoc """
  The Controllers tab: every controller the robot declares, with its module
  and whether its process is running, and a popup of its state.

  Pure functions — take state, return widget structs.
  """

  alias BB.TUI.State
  alias BB.TUI.State.Controllers
  alias BB.TUI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.CodeBlock
  alias ExRatatui.Widgets.Popup
  alias ExRatatui.Widgets.Table

  @doc """
  Renders the controllers table.

  ## Examples

      iex> controllers = %BB.TUI.State.Controllers{
      ...>   list: [%{name: :balancer, module: MyBot.Balancer, simulation: :omit}],
      ...>   alive: %{balancer: true}
      ...> }
      iex> %ExRatatui.Widgets.Table{rows: [[name, module, _status]]} =
      ...>   BB.TUI.Panels.Controllers.render(%BB.TUI.State{controllers: controllers})
      iex> {name, module}
      {"balancer", "MyBot.Balancer"}
  """
  @spec render(State.t()) :: Table.t()
  def render(%State{controllers: %Controllers{} = controllers} = state) do
    rows =
      for %{name: name, module: module} = controller <- controllers.list,
          do: [Atom.to_string(name), inspect(module), status(state, controller)]

    %Table{
      rows: rows,
      header: ["Controller", "Module", "Status"],
      widths: [{:percentage, 25}, {:percentage, 50}, {:min, 20}],
      selected: if(rows != [], do: controllers.selected),
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "\u{25B6} ",
      block: %Block{
        title: " Controllers ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(true)
      }
    }
  end

  # A controller left out of simulation isn't running by design, which is
  # different from one that crashed.
  defp status(%State{simulation: simulation}, %{simulation: :omit}) when simulation != nil,
    do: line("off in simulation", Theme.dim_text())

  defp status(%State{controllers: %{alive: alive}}, %{name: name}) do
    case Map.fetch(alive, name) do
      {:ok, true} -> line("\u{25CF} running", Theme.green())
      {:ok, false} -> line("\u{25CB} not running", Theme.red())
      :error -> line("?", Theme.dim_text())
    end
  end

  defp line(text, color), do: %Line{spans: [%Span{content: text, style: %Style{fg: color}}]}

  @doc """
  Renders the inspect popup: the controller's state, pretty-printed.

  ## Examples

      iex> %ExRatatui.Widgets.Popup{content: %ExRatatui.Widgets.CodeBlock{content: content}} =
      ...>   BB.TUI.Panels.Controllers.detail(%{name: :yaw, result: {:ok, %{heading: 0.5}}})
      iex> content
      "%{heading: 0.5}"
  """
  @spec detail(Controllers.detail()) :: Popup.t()
  def detail(%{name: name, result: result}) do
    %Popup{
      content: %CodeBlock{
        content: content(result),
        language: "elixir",
        theme: :base16_ocean_dark,
        wrap: false,
        style: %Style{}
      },
      percent_width: 70,
      percent_height: 70,
      block: %Block{
        title: " #{name} state  \u{23CE} refresh, any key closes ",
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp content(:loading), do: "# asking…"

  defp content({:ok, value}),
    do: inspect(value, pretty: true, limit: :infinity, printable_limit: 200)

  defp content({:error, reason}), do: "# no answer: #{inspect(reason)}"
end
