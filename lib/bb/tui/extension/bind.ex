defmodule BB.TUI.Extension.Bind do
  @moduledoc """
  A key bound to a robot command: pressing `key` runs `command` through the
  same path as the commands panel.
  """
  defstruct [:key, :command, :label, __identifier__: nil, __spark_metadata__: nil]

  @type t :: %__MODULE__{key: String.t(), command: atom(), label: String.t() | nil}
end
