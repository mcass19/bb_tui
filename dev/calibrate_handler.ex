# SPDX-License-Identifier: Apache-2.0

defmodule Dev.CalibrateHandler do
  @moduledoc """
  Dev-only command that takes a couple of seconds before succeeding. Useful
  for eyeballing the commands panel's `⏳ Running` badge, `c` to cancel, and
  the events panel's `command.started`/`command.succeeded` (or `cancelled`)
  pair without a real long-running operation.

  It waits on a timer rather than sleeping inside `handle_command/3`, so the
  command process stays responsive: a cancel lands immediately instead of
  after the wait, and `result/1` reports it as `{:error, :cancelled}`.
  """
  use BB.Command

  alias BB.Dsl.Info

  @duration_ms 2_000

  @impl BB.Command
  def handle_command(goal, context, state) do
    Process.send_after(self(), {:calibrated, goal}, @duration_ms)
    {:noreply, %{state | next_state: Info.initial_state(context.robot_module)}}
  end

  @impl BB.Command
  def handle_info({:calibrated, goal}, state) do
    {:stop, :normal, %{state | result: {:ok, goal}}}
  end

  # The command server also delivers its `[:state_machine]` subscription here.
  def handle_info(_msg, state), do: {:noreply, state}

  @impl BB.Command
  def result(%{result: {:ok, value}, next_state: next_state}) when not is_nil(next_state),
    do: {:ok, value, next_state: next_state}

  def result(%{result: {:ok, _} = result}), do: result
  def result(_state), do: {:error, :cancelled}
end
