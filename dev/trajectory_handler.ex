# SPDX-License-Identifier: Apache-2.0

defmodule Dev.TrajectoryHandler do
  @moduledoc """
  Dev-only command that sweeps the `shoulder` and `elbow` joints through a
  coordinated trajectory, publishing a real
  `BB.Message.Actuator.Command.Trajectory` per joint on `[:actuator | joint]`
  and then the motion it describes as synthetic `JointState` messages on
  `[:sensor, :simulated]` for ~2.4s at ~30Hz.

  Its purpose is to demonstrate trajectories end-to-end: the event log
  summarizes each command as `shoulder ← trajectory 4 waypoints over 2400ms`
  and its detail pane collapses the waypoints to `position@time`, while the
  joints panel and the 3D view show the arm moving *through* the waypoints
  rather than snapping between targets.

  The dev robot declares no actuators — like `Dev.MoveHandler`, the burst of
  `JointState` messages stands in for a driver following the trajectory.
  Waypoints carry no `velocity` or `acceleration`, which `bb` 0.29 made
  optional: pace is the driver's business, and here that is the interpolation
  below.

  Goal shape: none.
  """
  use BB.Command

  alias BB.Dsl.Info
  alias BB.Message
  alias BB.Message.Actuator.Command.Trajectory
  alias BB.Message.Sensor.JointState

  @interval_ms 33
  @duration_ms 2400

  # Both joints start and end at rest, so the arm returns to its home pose.
  @trajectories [
    shoulder: [
      [position: 0.0, time_from_start: 0],
      [position: -0.6, time_from_start: 800],
      [position: 0.4, time_from_start: 1600],
      [position: 0.0, time_from_start: @duration_ms]
    ],
    elbow: [
      [position: 0.0, time_from_start: 0],
      [position: 0.8, time_from_start: 800],
      [position: -0.3, time_from_start: 1600],
      [position: 0.0, time_from_start: @duration_ms]
    ]
  ]

  @impl BB.Command
  def handle_command(_goal, context, state) do
    robot = context.robot_module

    Enum.each(@trajectories, fn {joint, waypoints} ->
      {:ok, msg} = Message.new(Trajectory, joint, waypoints: waypoints, repeat: 1)
      BB.publish(robot, [:actuator, joint], msg)
    end)

    names = Keyword.keys(@trajectories)
    # Round up, so the last tick lands on (or past) the final waypoint and the
    # arm settles exactly where the trajectory said it would.
    ticks = ceil(@duration_ms / @interval_ms)

    Enum.each(0..ticks, fn tick ->
      elapsed = tick * @interval_ms
      positions = Enum.map(@trajectories, fn {_joint, waypoints} -> at(waypoints, elapsed) end)

      {:ok, msg} =
        Message.new(JointState, :simulated,
          names: names,
          positions: positions,
          velocities: List.duplicate(0.0, length(names)),
          efforts: List.duplicate(0.0, length(names))
        )

      BB.publish(robot, [:sensor, :simulated], msg)
      Process.sleep(@interval_ms)
    end)

    next_state = Info.initial_state(robot)

    {:stop, :normal,
     %{state | result: {:ok, %{joints: names, duration_ms: @duration_ms}}, next_state: next_state}}
  end

  # Linear interpolation between the waypoints bracketing `elapsed_ms` — the
  # simplest stand-in for a driver's motion profile, and enough to show the
  # arm passing through every waypoint.
  defp at(waypoints, elapsed_ms) do
    waypoints
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [_from, to] -> elapsed_ms <= to[:time_from_start] end)
    |> case do
      [from, to] ->
        span = to[:time_from_start] - from[:time_from_start]
        progress = (elapsed_ms - from[:time_from_start]) / span

        from[:position] + (to[:position] - from[:position]) * progress

      nil ->
        List.last(waypoints)[:position]
    end
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
