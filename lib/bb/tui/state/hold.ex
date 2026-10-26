defmodule BB.TUI.State.Hold do
  @moduledoc """
  When a held key counts as let go, shared by driving (`BB.TUI.State.Drive`)
  and velocity jogging (`BB.TUI.State.VelocityJog`).

  A hold is `%{pressed_at: ms, last_at: ms}`: when its key first went down
  and when it last went down or repeated. In `:inference` mode — a terminal
  that only reports presses — it is let go 600 ms after a lone press,
  covering the OS autorepeat delay, and 150 ms after the latest repeat. In
  `:release` mode it lasts until its release, with a 1 s safety window,
  refreshed by repeats, for a release that never arrives.
  """

  @first_press_ms 600
  @repeat_ms 150
  @release_safety_ms 1_000

  @type mode :: :inference | :release
  @type hold :: %{
          required(:pressed_at) => integer(),
          required(:last_at) => integer(),
          optional(atom()) => term()
        }

  @doc """
  Whether `hold` still counts as held at `now`.

  ## Examples

      iex> alias BB.TUI.State.Hold
      iex> Hold.held?(:inference, %{pressed_at: 0, last_at: 0}, 600)
      true
      iex> Hold.held?(:inference, %{pressed_at: 0, last_at: 550}, 701)
      false
      iex> Hold.held?(:release, %{pressed_at: 0, last_at: 0}, 1_000)
      true
  """
  @spec held?(mode(), hold(), integer()) :: boolean()
  def held?(mode, %{last_at: last_at} = hold, now), do: now - last_at <= window(mode, hold)

  defp window(:release, _hold), do: @release_safety_ms
  defp window(_inference, %{pressed_at: same, last_at: same}), do: @first_press_ms
  defp window(_inference, _hold), do: @repeat_ms
end
