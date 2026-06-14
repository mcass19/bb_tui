defmodule BB.TUI.State.Power do
  @moduledoc """
  Latest electrical telemetry, split out of `BB.TUI.State`.

  `battery` holds the most recent `BB.Message.Sensor.BatteryState` payload and
  `power` the most recent `BB.Message.Sensor.PowerState`, or `nil` until one
  arrives on the `[:sensor | _]` path. The status bar reads these to render an
  at-a-glance charge / voltage segment — most useful when driving a headless
  robot over SSH, where the charge level is otherwise invisible.

  Only the freshest reading of each kind is kept; the event log carries the
  history.
  """

  defstruct battery: nil, power: nil

  @type t :: %__MODULE__{
          battery: struct() | nil,
          power: struct() | nil
        }
end
