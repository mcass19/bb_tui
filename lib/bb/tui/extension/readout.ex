defmodule BB.TUI.Extension.Readout do
  @moduledoc """
  A labelled value in a panel, read from a `BB.TUI.Extension.Source`.

  `unit` names the unit the value is shown in (a radian joint as `:degree`,
  say), `scale` multiplies it first, `decimals` rounds it, and `spark: true`
  draws a sparkline of its recent values beside it.
  """
  defstruct [
    :label,
    :source,
    :unit,
    :scale,
    :decimals,
    spark: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          label: String.t(),
          source: BB.TUI.Extension.Source.t(),
          unit: atom() | nil,
          scale: number() | nil,
          decimals: non_neg_integer() | nil,
          spark: boolean()
        }
end
