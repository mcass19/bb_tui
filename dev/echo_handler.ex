# SPDX-License-Identifier: Apache-2.0

defmodule Dev.EchoHandler do
  @moduledoc """
  No-op command handler for dev/UI testing. Echoes the goal map back as
  the result, and returns the state machine to the robot's initial
  operational state so the runtime doesn't park in `:executing`
  forever. Use only from the dev tree.
  """
  use BB.Command

  alias BB.Dsl.Info

  @impl BB.Command
  def handle_command(goal, context, state) do
    next_state = Info.initial_state(context.robot_module)
    {:stop, :normal, %{state | result: {:ok, goal}, next_state: next_state}}
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
