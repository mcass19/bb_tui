defmodule BB.TUI.RobotSubscribeRemoteTest do
  @moduledoc """
  The relay test spawns a process via `BB.TUI.Rpc.spawn_link/2` that
  internally invokes `BB.subscribe/2`. Under `:set_mimic_private` the
  spawned process would not see stubs set up in the test process, so
  this single test stays in its own sync file with `:set_mimic_global`.

  Everything else in the Robot module runs the stubbed callbacks
  inside the test process and lives in `test/bb/tui/robot_test.exs`
  under async-private Mimic.
  """
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Robot

  setup :set_mimic_global

  @robot BB.TUI.TestRobot

  describe "subscribe/3 (remote)" do
    test "spawns a relay process on the remote node that forwards :bb messages" do
      test_pid = self()
      remote = :"robot@127.0.0.1"

      # Capture the relay function and run it locally so we can inspect its
      # behavior without needing real distribution.
      Mimic.expect(BB.TUI.Rpc, :spawn_link, fn ^remote, fun when is_function(fun, 0) ->
        spawn_link(fn ->
          send(test_pid, {:relay_started, self()})
          fun.()
        end)
      end)

      Mimic.expect(BB, :subscribe, fn BB.TUI.TestRobot, [:state_machine] -> :ok end)
      Mimic.expect(BB, :subscribe, fn BB.TUI.TestRobot, [:sensor] -> :ok end)

      assert :ok = Robot.subscribe(@robot, [[:state_machine], [:sensor]], remote)

      assert_receive {:relay_started, relay_pid}

      # The relay should forward {:bb, _, _} messages back to us.
      send(relay_pid, {:bb, [:state_machine], %{from: :idle, to: :armed}})
      assert_receive {:bb, [:state_machine], %{from: :idle, to: :armed}}

      # Other messages are silently dropped (loop continues).
      send(relay_pid, :ignored)
      send(relay_pid, {:bb, [:sensor], %{payload: :ok}})
      assert_receive {:bb, [:sensor], %{payload: :ok}}

      Process.unlink(relay_pid)
      Process.exit(relay_pid, :kill)
    end
  end
end
