# SPDX-License-Identifier: Apache-2.0

defmodule Dev.MoveHandler do
  @moduledoc """
  Dev/UI command handler that drives a single joint to a target angle by
  publishing a position command on `[:actuator, <joint>]`. The dev
  supervisor boots `BB.Supervisor` with `simulation: :kinematic`, so
  the kinematic simulator picks the command up and emits the expected
  `JointState` sensor updates — which the dashboard already reflects
  in the joints panel.

  Returns the state machine to the robot's initial operational state
  so the runtime doesn't park in `:executing`.

  Goal shape: `%{joint: atom(), angle: float()}`.
  """
  use BB.Command

  alias BB.Dsl.Info

  @impl BB.Command
  def handle_command(%{joint: joint, angle: angle}, context, state) do
    :ok = BB.Actuator.set_position(context.robot_module, [joint], angle)
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
