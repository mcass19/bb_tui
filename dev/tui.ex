defmodule Dev.TUI do
  @moduledoc """
  Dev-only `BB.TUI.Extension` for `Dev.TestRobot`, using every part of the
  DSL: a drive through `Dev.Drive`, panels with readouts and plots from each
  kind of source, a key bound to a command, and per-state hints.
  """
  use BB.TUI.Extension

  drive do
    publish {Dev.Drive, :command}
    stop {Dev.Drive, :stop}
    throttle_scale param([:motion, :max_speed])
    turn_scale 1.5
    rate 20
  end

  panels do
    panel :arm do
      title "Arm"
      tab :drive
      readout "shoulder", joint(:shoulder), unit: :degree, decimals: 1, spark: true
      readout "elbow", joint(:elbow), unit: :degree, decimals: 1
      readout "max speed", param([:motion, :max_speed]), decimals: 2
    end

    panel :telemetry do
      title "Telemetry"
      readout "battery", topic([:sensor, :battery], :voltage), decimals: 2
      readout "drive", topic([:drive], [:vx]), scale: 100, decimals: 0
      readout "gait", controller(:gait, :pattern)

      plot "arm", [joint(:shoulder), joint(:elbow)], window: 5_000, y_range: {-3.2, 3.2}
    end
  end

  keys do
    bind "w", command: :wobble, label: "wobble"
  end

  hints do
    state :disarmed, "a to arm, then hold the arrows to drive"
    state :idle, "w to wobble, arrows to drive"
  end
end
