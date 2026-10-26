defmodule BB.TUI.PilotTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Pilot

  alias BB.TUI.Pilot

  # Each test leases its own robot name: `:global` names are node-wide.
  setup context, do: %{robot: Module.concat(__MODULE__, "Robot#{context.line}")}

  defp hold(robot) do
    test = self()

    pid =
      spawn_link(fn ->
        :ok = Pilot.take(robot)
        send(test, :holding)

        receive do
          :release -> Pilot.release(robot)
        end

        receive do: (:never -> :ok)
      end)

    assert_receive :holding
    pid
  end

  test "another session's lease can't be taken, only seen", %{robot: robot} do
    other = hold(robot)

    assert Pilot.holder(robot) == {:other, other}
    assert Pilot.take(robot) == {:error, {:held_by, other}}
    # Releasing a lease this process doesn't hold changes nothing.
    assert Pilot.release(robot) == :ok
    assert Pilot.holder(robot) == {:other, other}
  end

  test "a lease goes with its session", %{robot: robot} do
    other = hold(robot)
    Process.unlink(other)
    ref = Process.monitor(other)
    Process.exit(other, :kill)
    assert_receive {:DOWN, ^ref, :process, ^other, :killed}

    # :global cleans up on the holder's exit.
    Process.sleep(20)
    assert Pilot.holder(robot) == :free
    assert Pilot.take(robot) == :ok
  end
end
