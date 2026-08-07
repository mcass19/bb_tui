# SPDX-License-Identifier: Apache-2.0

defmodule Dev.DriveHandler do
  @moduledoc """
  Dev-only command that drives the planar `base_motion` joint in a circle,
  publishing synthetic `JointState` messages carrying `BB.Math.Transform2D`
  poses on `[:sensor, :simulated]` for ~3s at ~30Hz.

  Its purpose is to demonstrate multi-DoF joints end-to-end: the joints
  panel's read-only `pla` row tracks the pose, the event log renders the
  compact `(x, y, θ°)` form, and the 3D view shows the whole arm driving
  the loop. Mirrors `Dev.StreamHandler`'s publish pattern; the burst runs
  in the command's own process, returning the state machine to its initial
  operational state when done.

  Goal shape: none.
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Math.Transform2D
  alias BB.Message
  alias BB.Message.Sensor.JointState

  @ticks 90
  @interval_ms 33
  @radius_m 0.15

  @impl BB.Command
  def handle_command(_goal, context, state) do
    Enum.each(1..@ticks, fn tick ->
      angle = 2 * :math.pi() * tick / @ticks

      pose =
        Transform2D.new(
          @radius_m * :math.cos(angle),
          @radius_m * :math.sin(angle),
          # Heading tangent to the circle, so the arm faces its direction of travel.
          angle + :math.pi() / 2
        )

      {:ok, msg} =
        Message.new(JointState, :simulated,
          names: [:base_motion],
          positions: [pose],
          velocities: [],
          efforts: []
        )

      BB.publish(context.robot_module, [:sensor, :simulated], msg)
      Process.sleep(@interval_ms)
    end)

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
