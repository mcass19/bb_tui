defmodule BB.TUI.Extension.Hint do
  @moduledoc """
  The banner shown under the title bar while the robot is in `state`.
  """
  defstruct [:state, :text, __identifier__: nil, __spark_metadata__: nil]

  @type t :: %__MODULE__{state: atom(), text: String.t()}
end
