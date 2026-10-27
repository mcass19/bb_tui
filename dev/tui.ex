defmodule Dev.TUI do
  @moduledoc """
  Dev-only `BB.TUI.Extension` for `Dev.TestRobot`, using every part of the
  DSL: a drive through `Dev.Drive`, panels with readouts, plots and an
  attitude indicator from each kind of source, a key bound to a command,
  and per-state hints.
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
      attitude "attitude", pitch: joint(:shoulder), roll: joint(:waist), range: 60
    end

    panel :oscillator do
      title "Oscillator"
      readout "output", controller(:oscillator, :output), unit: :degree, decimals: 1, spark: true
      readout "target", controller(:oscillator, :target), unit: :degree, decimals: 1
      readout "ticks", controller(:oscillator, :ticks)

      plot "output vs target",
           [controller(:oscillator, :output), controller(:oscillator, :target)],
           unit: :degree,
           window: 8_000
    end

    panel :telemetry do
      title "Telemetry"
      readout "battery", topic([:sensor, :battery_bus], :voltage), unit: :volt, decimals: 2
      readout "drive", topic([:drive], :vx), unit: :centimeter_per_second, decimals: 0
      readout "trim", param([:controller, :trim]), decimals: 1

      plot "arm", [joint(:shoulder), joint(:elbow)], window: 5_000, y_range: {-3.2, 3.2}
    end
  end

  keys do
    bind "w", command: :wobble, label: "wobble"
  end

  hints do
    state :disarmed, "a to arm; on Drive, t takes the wheel and the arrows drive"
    state :idle, "w to wobble; on Drive, t takes the wheel"
  end
end
