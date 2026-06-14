# SPDX-License-Identifier: Apache-2.0

defmodule Dev.DiagnosticsHandler do
  @moduledoc """
  Dev-only command that publishes one of each newly-surfaced diagnostic
  message so they appear in the Events panel:

    * a `BB.Safety.HardwareError` on `[:safety, :error]` — the detail behind an
      error badge. This publishes the report directly and does **not** trip
      the safety state machine; production errors arrive via
      `BB.Safety.report_error/3`, which also forces a disarm.
    * an estimator `BB.Message.Estimator.Pose` on `[:estimator, :base_link]`.

  Both subtrees are subscribed by `BB.TUI.App` but not modelled in dedicated
  state, so they flow through the event log's catch-all. Run this to confirm
  the surfacing end to end.

  Goal shape: `%{}` (no arguments).
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Math.Transform
  alias BB.Message
  alias BB.Message.Estimator.Pose
  alias BB.Safety.HardwareError

  @impl BB.Command
  def handle_command(_goal, context, state) do
    {:ok, error} =
      Message.new(HardwareError, :safety, path: [:actuator, :elbow], error: :overcurrent)

    BB.publish(context.robot_module, [:safety, :error], error)

    {:ok, pose} = Message.new(Pose, :base_link, transform: Transform.identity())
    BB.publish(context.robot_module, [:estimator, :base_link], pose)

    next_state = Info.initial_state(context.robot_module)
    {:stop, :normal, %{state | result: {:ok, %{published: 2}}, next_state: next_state}}
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
