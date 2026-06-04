# SPDX-License-Identifier: Apache-2.0

defmodule Dev.StreamHandler do
  @moduledoc """
  Dev-only command that emits a high-rate burst of synthetic `JointState`
  sensor messages on `[:sensor, :simulated]`, sweeping a joint through a
  sine motion for ~2s at ~100Hz.

  Its purpose is to make the dashboard's high-rate handling visible: the
  joints panel animates smoothly because sensor-driven renders are
  coalesced to ~30fps, while the event log shows a single debounced
  `JointState` row per second instead of hundreds. Run it from the
  Commands panel and watch the Events count stay calm while the joint
  bar sweeps.

  Mirrors `Dev.MoveHandler`'s publish pattern; the burst runs in the
  command's own process (so the TUI keeps rendering), returning the state
  machine to its initial operational state when done.

  Goal shape: `%{joint: atom()}`.
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Message
  alias BB.Message.Sensor.JointState

  @ticks 200
  @interval_ms 10

  @impl BB.Command
  def handle_command(%{joint: joint}, context, state) do
    Enum.each(1..@ticks, fn tick ->
      {:ok, msg} =
        Message.new(JointState, :simulated,
          names: [joint],
          positions: [:math.sin(tick / 10.0)],
          velocities: [0.0],
          efforts: [0.0]
        )

      BB.publish(context.robot_module, [:sensor, :simulated], msg)
      Process.sleep(@interval_ms)
    end)

    next_state = Info.initial_state(context.robot_module)

    {:stop, :normal,
     %{state | result: {:ok, %{joint: joint, ticks: @ticks}}, next_state: next_state}}
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
