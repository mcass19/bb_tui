defmodule BB.TUI.Pilot do
  @moduledoc """
  The pilot lease: which dashboard session may drive a robot.

  The lease is a `:global` name, `{BB.TUI.Pilot, robot}`, registered to the
  session process that holds it. That makes it visible from every connected
  node — a laptop on `node:`, an SSH session on the robot, an attached
  terminal — and lets it go by itself when the session ends, however it
  ends.

  After a network split heals, two sessions can briefly both hold it.
  `:global`'s default resolution would kill one of them; this registers
  with `:global.random_notify_name/3` instead, which unregisters the loser
  and sends it `{:global_name_conflict, name}` — `BB.TUI.App` stops driving
  on it.

  Only bb_tui sessions take the lease. Other pilots (a badge, a phone pad)
  aren't coordinated by it.
  """

  @doc """
  The lease's `:global` name for `robot`.

  ## Examples

      iex> BB.TUI.Pilot.name(MyRobot)
      {BB.TUI.Pilot, MyRobot}
  """
  @spec name(module()) :: {module(), module()}
  def name(robot), do: {__MODULE__, robot}

  @doc """
  Takes the lease for the calling process. Returns `:ok` when it now holds
  it (or already did), or `{:error, {:held_by, holder}}` — `holder` is
  `:undefined` in the rare case it was let go between the two lookups, and
  taking again then succeeds.

  ## Examples

      iex> :ok = BB.TUI.Pilot.take(PilotDocRobot)
      iex> BB.TUI.Pilot.holder(PilotDocRobot)
      :mine
      iex> :ok = BB.TUI.Pilot.take(PilotDocRobot)
      iex> BB.TUI.Pilot.release(PilotDocRobot)
      :ok
      iex> BB.TUI.Pilot.holder(PilotDocRobot)
      :free
  """
  @spec take(module()) :: :ok | {:error, {:held_by, pid() | :undefined}}
  def take(robot) do
    name = name(robot)
    self = self()

    case :global.register_name(name, self, &:global.random_notify_name/3) do
      :yes ->
        :ok

      :no ->
        case :global.whereis_name(name) do
          ^self -> :ok
          holder -> {:error, {:held_by, holder}}
        end
    end
  end

  @doc """
  Lets go of the lease, if the calling process holds it.
  """
  @spec release(module()) :: :ok
  def release(robot) do
    name = name(robot)
    if :global.whereis_name(name) == self(), do: :global.unregister_name(name)
    :ok
  end

  @doc """
  Who holds the lease, from the calling process's point of view: `:mine`,
  `:free`, or `{:other, pid}`. A lookup in `:global`'s local table, cheap
  enough for every drive tick.
  """
  @spec holder(module()) :: :mine | :free | {:other, pid()}
  def holder(robot) do
    self = self()

    case :global.whereis_name(name(robot)) do
      ^self -> :mine
      :undefined -> :free
      pid -> {:other, pid}
    end
  end
end
