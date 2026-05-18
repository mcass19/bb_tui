# SPDX-License-Identifier: Apache-2.0

defmodule Dev.MoveHandler do
  @moduledoc """
  Dev/UI command handler that drives a single joint by publishing a
  synthetic `JointState` sensor message on `[:sensor, :simulated]`.

  This mirrors `BB.LiveView.Components.JointControl.send_simulated_position/3`
  in bb_liveview — when no real actuator is wired up (as in our dev
  robot and the default `mix bb.add_robot` scaffold), publishing a
  fake `JointState` is the pragmatic way to feed position updates
  into the dashboard's joints panel. No need for actuator
  declarations or `simulation: :kinematic`.

  Returns the state machine to the robot's initial operational state
  so the runtime doesn't park in `:executing`.

  Goal shape: `%{joint: atom(), angle: float()}`.
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Message
  alias BB.Message.Sensor.JointState

  @impl BB.Command
  def handle_command(%{joint: joint, angle: angle}, context, state) do
    {:ok, msg} =
      Message.new(JointState, :simulated,
        names: [joint],
        positions: [angle * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    BB.publish(context.robot_module, [:sensor, :simulated], msg)
    next_state = Info.initial_state(context.robot_module)

    {:stop, :normal,
     %{state | result: {:ok, %{joint: joint, angle: angle}}, next_state: next_state}}
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
