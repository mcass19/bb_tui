defmodule BB.TUI.Extension.Panel do
  @moduledoc """
  A `panel` declared in a `BB.TUI.Extension`: a titled box of readouts and
  plots, in display order.

  `tab` names the tab it sits on: `:drive` places it beside the drive pad,
  any other atom groups panels sharing it, and `nil` (the default) gives the
  panel a tab of its own named after it.
  """
  defstruct [:name, :title, :tab, items: [], __identifier__: nil, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: atom(),
          title: String.t() | nil,
          tab: atom() | nil,
          items: [BB.TUI.Extension.Readout.t() | BB.TUI.Extension.Plot.t()]
        }
end
