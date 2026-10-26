# SPDX-License-Identifier: Apache-2.0

defmodule Dev.Servo do
  @moduledoc """
  Dev-only stand-in for a servo driver, declared on the dev robot's `waist`,
  `shoulder` and `elbow` joints.

  The dev application always starts the robot with `simulation: :kinematic`,
  where bb swaps every actuator for `BB.Sim.Actuator`: it accepts position
  commands, times the motion from the joint's velocity limit, and publishes
  `BeginMotion` for the joint's `BB.Sensor.OpenLoopPositionEstimator` to turn
  into `JointState`. So jogging these joints goes through bb's real actuator
  path — the arm check, arm epochs, `CommandPending` for a slow answer — while
  the wrist and gripper stay actuator-less and are driven by the dashboard's
  simulated `JointState` fallback.

  Outside simulation this driver accepts every command and moves nothing.
  """
  use BB.Actuator, options_schema: []

  @impl BB.Actuator
  def init(_opts), do: {:ok, %{}}

  @impl BB.Actuator
  def handle_command(_command, state), do: {:noreply, state}

  @impl BB.Actuator
  def disarm(_opts), do: :ok
end
