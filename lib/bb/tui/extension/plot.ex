defmodule BB.TUI.Extension.Plot do
  @moduledoc """
  A live chart in a panel: one line per source over the last `window`
  milliseconds, with an optional fixed `y_range`.
  """
  defstruct [:label, :y_range, sources: [], window: 10_000, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          label: String.t(),
          sources: [BB.TUI.Extension.Source.t()],
          window: pos_integer(),
          y_range: {number(), number()} | nil
        }
end
