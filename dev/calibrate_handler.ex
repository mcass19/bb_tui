# SPDX-License-Identifier: Apache-2.0

defmodule Dev.CalibrateHandler do
  @moduledoc """
  Dev-only command handler that sleeps for a couple of seconds before
  succeeding. Useful for eyeballing the executing-command throbber and
  the events panel's `command.started`/`command.succeeded` pair without
  a real long-running operation.

  Runs in its own command process spawned by `BB.Command`, so the
  sleep does not block the TUI runtime.
  """
  use BB.Command

  alias BB.Dsl.Info

  @sleep_ms 2_000

  @impl BB.Command
  def handle_command(goal, context, state) do
    Process.sleep(@sleep_ms)
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
