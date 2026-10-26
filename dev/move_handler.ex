# SPDX-License-Identifier: Apache-2.0

defmodule Dev.MoveHandler do
  @moduledoc """
  Dev/UI command handler that drives a single joint.

  A joint with an actuator (`waist`, `shoulder` and `elbow` on the dev
  robot) is sent the target through `BB.Actuator.set_position/4`, the way
  real code drives hardware: under `simulation: :kinematic` the simulated
  actuator moves it and its position estimator reports the motion, and a
  refusal — a disarmed robot, a stale arm epoch — becomes the command's
  error result.

  A joint without one has nothing to command, so the handler publishes a
  synthetic `JointState` on `[:sensor, :simulated]` instead, mirroring
  `BB.LiveView.Components.JointControl.send_simulated_position/3` in
  bb_liveview and the dashboard's own fallback for actuator-less joints.

  Returns the state machine to the robot's initial operational state
  so the runtime doesn't park in `:executing`.

  Goal shape: `%{joint: atom(), angle: float()}`.
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Message
  alias BB.Message.Sensor.JointState

  @impl BB.Command
  def handle_command(%{joint: joint, angle: angle} = goal, context, state) do
    result =
      case actuator_for(context.robot, joint) do
        nil -> publish_simulated(context.robot_module, joint, angle)
        actuator -> BB.Actuator.set_position(context.robot_module, actuator, angle)
      end

    next_state = Info.initial_state(context.robot_module)
    result = with :ok <- result, do: {:ok, goal}

    {:stop, :normal, %{state | result: result, next_state: next_state}}
  end

  @impl BB.Command
  def result(%{result: {:ok, value}, next_state: next_state}) when not is_nil(next_state),
    do: {:ok, value, next_state: next_state}

  def result(%{result: result}), do: result

  defp actuator_for(robot, joint) do
    Enum.find_value(robot.actuators, fn {name, info} -> if info.joint == joint, do: name end)
  end

  defp publish_simulated(robot_module, joint, angle) do
    {:ok, msg} =
      Message.new(JointState, :simulated,
        names: [joint],
        positions: [angle * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    BB.publish(robot_module, [:sensor, :simulated], msg)
  end
end
