defmodule Dev.Drive do
  @moduledoc """
  Dev-only drive target for `Dev.TUI`: publishes the throttle and turn as a
  `BB.Message.Geometry.Twist2D` on `[:drive]`, where the event log shows
  them. Stands in for a kit's own drive module (`BB.NSK.Drive` on a
  balance bot).
  """

  alias BB.Message.Geometry.Twist2D

  @max_speed_mps 0.3

  @doc "Publishes a drive command: `throttle` in -1..1, `turn` in rad/s."
  @spec command(module(), number(), number()) :: :ok
  def command(robot, throttle, turn) do
    {:ok, msg} = Twist2D.new(:base_footprint, throttle * @max_speed_mps, 0.0, turn)
    BB.publish(robot, [:drive], msg)
  end

  @doc "Publishes a zero command."
  @spec stop(module()) :: :ok
  def stop(robot), do: command(robot, 0.0, 0.0)
end
