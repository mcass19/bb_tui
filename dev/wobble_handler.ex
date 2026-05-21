# SPDX-License-Identifier: Apache-2.0

defmodule Dev.WobbleHandler do
  @moduledoc """
  Dev-only command handler that always fails. Useful for eyeballing the
  Events panel's failure rendering and the Commands panel's
  `{:error, _}` result formatting without driving a real fault.

  Returns the state machine to the robot's initial operational state so
  the runtime doesn't park in `:executing` on repeated invocations.
  """
  use BB.Command

  alias BB.Dsl.Info

  @impl BB.Command
  def handle_command(_goal, context, state) do
    next_state = Info.initial_state(context.robot_module)
    {:stop, :normal, %{state | result: {:error, :wobble_failed}, next_state: next_state}}
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
