defmodule BB.TUI.State.Safety do
  @moduledoc """
  Robot safety status, split out of `BB.TUI.State`.

  `state` mirrors the robot's safety state machine (`:armed`/`:disarmed`/
  `:disarming`/`:error`), `runtime` its operational runtime state, and
  `confirm_force_disarm?` tracks whether the force-disarm confirmation
  dialog is open. `state`/`runtime` are seeded when `BB.TUI.App` starts.
  """

  defstruct state: nil,
            runtime: nil,
            confirm_force_disarm?: false

  @type t :: %__MODULE__{
          state: :armed | :disarmed | :disarming | :error | nil,
          runtime: atom() | nil,
          confirm_force_disarm?: boolean()
        }
end
