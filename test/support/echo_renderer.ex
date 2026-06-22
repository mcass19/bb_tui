defmodule BB.TUI.Test.EchoRenderer do
  @moduledoc false
  # A consumer-side `BB.TUI.Renderer` for the generic seam tests. Owns the
  # `[:demo]` path with a plain-map payload (`%{slot: ..., label: ..., value:
  # ..., freshness: ..., seq: ...}`) — deliberately NOT named after or shaped
  # like any bb_mcuhub struct, to prove bb_tui needs zero downstream knowledge.

  @behaviour BB.TUI.Renderer

  @impl true
  def summarize([:demo | _], %{label: label, value: value}) do
    "echo #{label}=#{value}"
  end

  def summarize(_path, _payload), do: nil

  @impl true
  def observed([:demo | _], %{slot: slot} = payload) do
    display = %{label: Map.get(payload, :label) || inspect(slot)}

    meta = %{
      freshness: Map.get(payload, :freshness, :fresh),
      seq: Map.get(payload, :seq, 0)
    }

    {slot, display, meta}
  end

  def observed(_path, _payload), do: nil
end

defmodule BB.TUI.Test.SummaryOnlyRenderer do
  @moduledoc false
  # A renderer that implements only the required `summarize/2` and deliberately
  # omits the optional `observed/2`, to prove the dispatch skips `observed/2`
  # via `function_exported?/3` when the consumer doesn't export it.

  @behaviour BB.TUI.Renderer

  @impl true
  def summarize([:demo | _], %{label: label}), do: "summary-only #{label}"
  def summarize(_path, _payload), do: nil
end

defmodule BB.TUI.Test.NilSummaryRenderer do
  @moduledoc false
  # A renderer whose `summarize/2` always returns `nil`, to prove the event log
  # falls back to bb_tui's generic `inspect` rendering for a renderer-owned path
  # when the consumer declines to summarise the payload.

  @behaviour BB.TUI.Renderer

  @impl true
  def summarize(_path, _payload), do: nil
end
