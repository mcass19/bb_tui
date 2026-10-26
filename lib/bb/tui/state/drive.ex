defmodule BB.TUI.State.Drive do
  @moduledoc """
  Hold-to-drive with the arrow keys, as a pure state machine.

  Up/down set the throttle to 1/-1 and left/right the turn to 1/-1 (left is
  positive, counter-clockwise), one direction per axis: pressing the
  opposite arrow takes over. `step/2` turns what is held into what to do
  now — publish a throttle and turn, stop, or nothing.

  Terminals report key releases unevenly, so there are two modes (see
  `BB.TUI.State.Hold`):

    * **inference** (the start): only presses arrive, and holding a key
      repeats them after the OS autorepeat delay (~0.5 s, longer than a
      robot's dead-man timeout). A key counts as held for 600 ms after
      its first press and then 150 ms after each repeat, and is let go
      when its presses stop.
    * **release**: entered on the first `"release"` event, from a terminal
      speaking the kitty keyboard protocol or a browser. A key is held until
      its release; a 1 s safety window, refreshed by its repeats,
      still lets go of one whose release got lost.
  """

  alias BB.TUI.State.Hold

  @keys %{
    "up" => {:throttle, 1},
    "down" => {:throttle, -1},
    "left" => {:turn, 1},
    "right" => {:turn, -1}
  }

  defstruct mode: :inference, held: %{}, driving?: false, lease: :free

  @type axis :: :throttle | :turn
  @type t :: %__MODULE__{
          mode: :inference | :release,
          held: %{
            axis() => %{
              key: String.t(),
              direction: -1 | 1,
              pressed_at: integer(),
              last_at: integer()
            }
          },
          driving?: boolean(),
          lease: lease()
        }

  @typedoc """
  The pilot lease (see `BB.TUI.Pilot`) as this session last saw it: its own,
  free, or another session's — with that session's node and when this one
  first saw it there.
  """
  @type lease :: :mine | :free | {:other, node(), NaiveDateTime.t()}

  @type action :: {:publish, -1 | 0 | 1, -1 | 0 | 1} | :stop | :idle

  @doc """
  The drive keys.

  ## Examples

      iex> BB.TUI.State.Drive.keys()
      ["down", "left", "right", "up"]
  """
  @spec keys() :: [String.t()]
  def keys, do: @keys |> Map.keys() |> Enum.sort()

  @doc """
  A drive key went down, or repeated. A key already held keeps its
  `pressed_at`, so an autorepeat counts as a repeat.

  ## Examples

      iex> alias BB.TUI.State.Drive
      iex> drive = Drive.press(%Drive{}, "up", 0)
      iex> drive.held.throttle.direction
      1
      iex> Drive.press(drive, "down", 10).held.throttle.direction
      -1
  """
  @spec press(t(), String.t(), integer()) :: t()
  def press(%__MODULE__{held: held} = drive, key, now) do
    {axis, direction} = Map.fetch!(@keys, key)

    entry =
      case held do
        %{^axis => %{key: ^key} = entry} -> %{entry | last_at: now}
        _ -> %{key: key, direction: direction, pressed_at: now, last_at: now}
      end

    %{drive | held: Map.put(held, axis, entry)}
  end

  @doc """
  A drive key came up. The first release switches to release mode for the
  rest of the session. Releasing a key that isn't the one held on its axis
  (the opposite arrow, already taken over) changes nothing.

  ## Examples

      iex> alias BB.TUI.State.Drive
      iex> drive = Drive.press(%Drive{}, "up", 0) |> Drive.release("up")
      iex> {drive.mode, drive.held}
      {:release, %{}}
  """
  @spec release(t(), String.t()) :: t()
  def release(%__MODULE__{held: held} = drive, key) do
    {axis, _direction} = Map.fetch!(@keys, key)

    held =
      case held do
        %{^axis => %{key: ^key}} -> Map.delete(held, axis)
        _ -> held
      end

    %{drive | mode: :release, held: held}
  end

  @doc """
  What to do at `now`: lets go of keys whose window has passed, then
  publishes the held throttle and turn, stops once when the last key is let
  go, or does nothing.

  ## Examples

      iex> alias BB.TUI.State.Drive
      iex> drive = Drive.press(%Drive{}, "up", 0) |> Drive.press("left", 0)
      iex> {{:publish, 1, 1}, drive} = Drive.step(drive, 100)
      iex> # No repeat arrived within the first-press window.
      iex> {:stop, drive} = Drive.step(drive, 700)
      iex> {:idle, _drive} = Drive.step(drive, 800)
  """
  @spec step(t(), integer()) :: {action(), t()}
  def step(%__MODULE__{} = drive, now) do
    held = Map.filter(drive.held, fn {_axis, entry} -> Hold.held?(drive.mode, entry, now) end)

    drive = %{drive | held: held}

    cond do
      held != %{} ->
        {{:publish, direction(held, :throttle), direction(held, :turn)},
         %{drive | driving?: true}}

      drive.driving? ->
        {:stop, %{drive | driving?: false}}

      true ->
        {:idle, drive}
    end
  end

  defp direction(held, axis) do
    case held do
      %{^axis => %{direction: direction}} -> direction
      _ -> 0
    end
  end

  @doc """
  Lets go of every key at once — quitting, leaving the Drive tab, losing
  focus. Returns `:stop` when it was driving, `:idle` otherwise. The mode
  is kept.

  ## Examples

      iex> alias BB.TUI.State.Drive
      iex> {_publish, drive} = Drive.press(%Drive{}, "up", 0) |> Drive.step(0)
      iex> {:stop, drive} = Drive.halt(drive)
      iex> {:idle, _drive} = Drive.halt(drive)
  """
  @spec halt(t()) :: {:stop | :idle, t()}
  def halt(%__MODULE__{driving?: true} = drive),
    do: {:stop, %{drive | held: %{}, driving?: false}}

  def halt(%__MODULE__{} = drive), do: {:idle, %{drive | held: %{}}}

  @doc """
  Records who holds the pilot lease, as `BB.TUI.Pilot.holder/1` reports
  it at `at` (a wall-clock time). Another session's lease keeps the time it
  was first seen, so "since" doesn't move while it stays the same.

  ## Examples

      iex> alias BB.TUI.State.Drive
      iex> at = ~N[2026-10-26 12:00:00]
      iex> drive = Drive.observe_lease(%Drive{}, {:other, :"robot@goatbot"}, at)
      iex> Drive.observe_lease(drive, {:other, :"robot@goatbot"}, ~N[2026-10-26 12:05:00]).lease
      {:other, :"robot@goatbot", ~N[2026-10-26 12:00:00]}
      iex> Drive.observe_lease(drive, :mine, at).lease
      :mine
  """
  @spec observe_lease(t(), :mine | :free | {:other, node()}, NaiveDateTime.t()) :: t()
  def observe_lease(%__MODULE__{lease: {:other, node, _since}} = drive, {:other, node}, _at),
    do: drive

  def observe_lease(%__MODULE__{} = drive, {:other, node}, at),
    do: %{drive | lease: {:other, node, at}}

  def observe_lease(%__MODULE__{} = drive, lease, _at) when lease in [:mine, :free],
    do: %{drive | lease: lease}

  @doc """
  Whether a key is held or a stop is still owed — while this is true, the
  drive needs ticking.

  ## Examples

      iex> BB.TUI.State.Drive.active?(%BB.TUI.State.Drive{})
      false
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{held: held, driving?: driving?}), do: held != %{} or driving?
end
