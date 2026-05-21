defmodule BB.TUI.Panels.EventDetail do
  @moduledoc """
  Event detail popup — overlay showing the full payload of the selected
  event as a syntax-highlighted Elixir term.

  Renders the message payload via `inspect(payload, pretty: true)` inside
  an `ExRatatui.Widgets.CodeBlock` so operators get real Elixir
  highlighting (atoms, structs, numerics) instead of the previous
  hand-rendered tree. The popup's block title carries the one-line
  summary built by `BB.TUI.Panels.Events.format_event/1`.

  Pure function — takes an event tuple, returns a Popup widget struct.
  """

  alias BB.TUI.Panels.Events
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.CodeBlock
  alias ExRatatui.Widgets.Popup

  @doc """
  Renders the event detail popup for the given event.

  ## Examples

      iex> event = {~U[2026-01-15 18:23:12.000Z], [:sensor, :sim], %{payload: %{names: [:a], positions: [1.0]}}}
      iex> %ExRatatui.Widgets.Popup{content: %ExRatatui.Widgets.CodeBlock{language: "elixir"}} =
      ...>   BB.TUI.Panels.EventDetail.render(event)
  """
  @spec render({DateTime.t(), list(), term()}) :: struct()
  def render({_ts, _path, msg} = event) do
    summary = Events.format_event(event)
    source = format_source(msg)

    content = %CodeBlock{
      content: source,
      language: "elixir",
      theme: :base16_ocean_dark,
      wrap: false,
      style: %Style{}
    }

    %Popup{
      content: content,
      percent_width: 70,
      percent_height: 60,
      block: %Block{
        title: " " <> summary <> " ",
        borders: [:all],
        border_type: :double,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp format_source(%{payload: payload}), do: format_source(payload)

  defp format_source(payload) do
    inspect(payload, pretty: true, limit: :infinity, structs: true, printable_limit: 200)
  end
end
