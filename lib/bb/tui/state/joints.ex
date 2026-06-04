defmodule BB.TUI.State.Joints do
  @moduledoc """
  Joint positions and selection, split out of `BB.TUI.State`.

  `entries` maps each joint name to its `%{joint:, position:, target:}` data
  (the joints panel renders from it); `selected` is the highlighted row index.
  `entries` is seeded when `BB.TUI.App` starts.
  """

  defstruct entries: %{},
            selected: 0

  @type t :: %__MODULE__{
          entries: %{atom() => %{position: float(), joint: term()}},
          selected: non_neg_integer()
        }
end
