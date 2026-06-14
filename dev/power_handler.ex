# SPDX-License-Identifier: Apache-2.0

defmodule Dev.PowerHandler do
  @moduledoc """
  Dev-only command that emits a short battery + power telemetry sweep on
  `[:sensor, :battery_bus]`, draining a simulated pack from ~95% to ~10%
  over ~2s so the status bar's battery readout shifts green → yellow → red.

  A real robot publishes `BB.Message.Sensor.BatteryState` (and/or
  `BB.Message.Sensor.PowerState`) continuously from its power monitor; this
  handler fakes that stream on demand so the status-bar indicator is
  demonstrable without hardware. Because every reading shares the same
  `{path, payload-type}` key, the event log collapses the burst to one
  debounced row per second while the status bar tracks the live value.

  Runs in its own command process (so the TUI keeps rendering), returning the
  state machine to its initial operational state when done.

  Goal shape: `%{}` (no arguments).
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Message
  alias BB.Message.Sensor.BatteryState
  alias BB.Message.Sensor.PowerState

  @ticks 40
  @interval_ms 50

  @impl BB.Command
  def handle_command(_goal, context, state) do
    Enum.each(1..@ticks, fn tick ->
      percentage = max(0.95 - tick / @ticks * 0.85, 0.0)
      voltage = 10.5 + percentage * 2.1

      {:ok, battery} =
        Message.new(BatteryState, :battery_bus,
          voltage: voltage,
          current: -1.2,
          percentage: percentage,
          power_supply_status: :discharging,
          present: true
        )

      BB.publish(context.robot_module, [:sensor, :battery_bus], battery)
      Process.sleep(@interval_ms)
    end)

    {:ok, power} =
      Message.new(PowerState, :battery_bus, voltage: 10.6, current: -1.2, power: -12.7)

    BB.publish(context.robot_module, [:sensor, :battery_bus], power)

    next_state = Info.initial_state(context.robot_module)
    {:stop, :normal, %{state | result: {:ok, %{ticks: @ticks}}, next_state: next_state}}
  end

  @impl BB.Command
  def result(%{result: result, next_state: next_state}) when not is_nil(next_state) do
    case result do
      {:ok, value} -> {:ok, value, next_state: next_state}
      other -> other
    end
  end

  def result(%{result: result}), do: result
end
