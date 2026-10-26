defmodule BB.TUI.State.VelocityJog do
  @moduledoc """
  Holding a jog key on a velocity-only joint — a wheel — spins it: the
  joint's actuator gets a velocity command when the key goes down and a
  stop when it is let go, as `BB.TUI.State.Hold` decides.

  Pure: each function returns the actuator commands to send, as
  `{:velocity, actuator, rad_per_s}` and `{:stop, actuator}`, alongside the
  new jog (`nil` when nothing spins).
  """

  alias BB.TUI.State.Hold

  defstruct [:actuator, :joint, :velocity, :pressed_at, :last_at]

  @type t :: %__MODULE__{
          actuator: atom(),
          joint: atom(),
          velocity: float(),
          pressed_at: integer(),
          last_at: integer()
        }

  @type command :: {:velocity, atom(), float()} | {:stop, atom()}

  @doc """
  A jog key went down (or repeated) for `joint`, whose `actuator` should
  spin at `velocity`. Holding the same key keeps it spinning without
  re-sending; another speed or direction is sent at once, and another joint
  stops the first.

  ## Examples

      iex> alias BB.TUI.State.VelocityJog
      iex> {[{:velocity, :wheel_motor, 0.4}], jog} = VelocityJog.press(nil, :wheel_motor, :wheel, 0.4, 0)
      iex> {[], jog} = VelocityJog.press(jog, :wheel_motor, :wheel, 0.4, 30)
      iex> {[{:velocity, :wheel_motor, -0.4}], jog} = VelocityJog.press(jog, :wheel_motor, :wheel, -0.4, 60)
      iex> {[{:stop, :wheel_motor}, {:velocity, :other_motor, 0.4}], _jog} =
      ...>   VelocityJog.press(jog, :other_motor, :other, 0.4, 90)
  """
  @spec press(t() | nil, atom(), atom(), float(), integer()) :: {[command()], t()}
  def press(
        %__MODULE__{actuator: actuator, velocity: velocity} = jog,
        actuator,
        _joint,
        velocity,
        now
      ),
      do: {[], %{jog | last_at: now}}

  def press(%__MODULE__{actuator: actuator} = jog, actuator, _joint, velocity, now),
    do:
      {[{:velocity, actuator, velocity}],
       %{jog | velocity: velocity, pressed_at: now, last_at: now}}

  def press(jog, actuator, joint, velocity, now) do
    {stop, nil} = halt(jog)

    {stop ++ [{:velocity, actuator, velocity}],
     %__MODULE__{
       actuator: actuator,
       joint: joint,
       velocity: velocity,
       pressed_at: now,
       last_at: now
     }}
  end

  @doc """
  Stops a spinning joint once its key counts as let go (see
  `BB.TUI.State.Hold`).

  ## Examples

      iex> alias BB.TUI.State.VelocityJog
      iex> {_send, jog} = VelocityJog.press(nil, :wheel_motor, :wheel, 0.4, 0)
      iex> {[], ^jog} = VelocityJog.tick(jog, :inference, 600)
      iex> VelocityJog.tick(jog, :inference, 601)
      {[{:stop, :wheel_motor}], nil}
  """
  @spec tick(t(), Hold.mode(), integer()) :: {[command()], t() | nil}
  def tick(%__MODULE__{} = jog, mode, now) do
    if Hold.held?(mode, jog, now), do: {[], jog}, else: halt(jog)
  end

  @doc """
  Stops a spinning joint now — its key came up, or the jog was interrupted
  (another joint selected, the tab or panel left, the wheel lost).

  ## Examples

      iex> BB.TUI.State.VelocityJog.halt(nil)
      {[], nil}
  """
  @spec halt(t() | nil) :: {[command()], nil}
  def halt(nil), do: {[], nil}
  def halt(%__MODULE__{actuator: actuator}), do: {[{:stop, actuator}], nil}

  @doc """
  The velocity a jog key commands for `joint`: 10% of its velocity limit,
  or half of it for the shifted keys (`multiplier` 10), in the key's
  `direction`. A joint without a limit uses 1 rad/s.

  ## Examples

      iex> BB.TUI.State.VelocityJog.velocity(%{limits: %{velocity: 4.0}}, :increase, 1)
      0.4
      iex> BB.TUI.State.VelocityJog.velocity(%{limits: %{velocity: 4.0}}, :decrease, 10)
      -2.0
      iex> BB.TUI.State.VelocityJog.velocity(%{}, :increase, 1)
      0.1
  """
  @spec velocity(map(), :increase | :decrease, pos_integer()) :: float()
  def velocity(joint, direction, multiplier) do
    limit =
      case joint do
        %{limits: %{velocity: limit}} when is_number(limit) and limit > 0 -> limit
        _ -> 1.0
      end

    share = if multiplier > 1, do: 0.5, else: 0.1
    sign = if direction == :increase, do: 1, else: -1
    sign * limit * share
  end
end
