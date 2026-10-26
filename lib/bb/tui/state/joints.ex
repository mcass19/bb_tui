defmodule BB.TUI.State.Joints do
  @moduledoc """
  Joint configurations and selection, split out of `BB.TUI.State`.

  `entries` maps each joint name to its `%{joint:, position:, target:}` data
  (the joints panel renders from it); `selected` is the highlighted row index.
  `entries` is seeded when `BB.TUI.App` starts. A single-DoF joint's
  `:position` is a float; planar and floating joints hold their
  `BB.Math.Transform2D`/`BB.Math.Transform` configuration structs.

  `jogs` holds one key per actuator with a jog in flight, mapped to the
  position parked behind it (or `nil`); see `BB.TUI.State.request_jog/3`.
  """

  defstruct entries: %{},
            selected: 0,
            jogs: %{}

  @type t :: %__MODULE__{
          entries: %{atom() => %{position: float() | struct(), joint: term()}},
          selected: non_neg_integer(),
          jogs: %{atom() => float() | nil}
        }
end
