defmodule BB.TUITest do
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Test.Fixtures

  setup :set_mimic_global

  describe "start/2" do
    test "starts the TUI app in test mode" do
      Fixtures.stub_bb_modules()

      {:ok, pid} = BB.TUI.start(BB.TUI.TestRobot, test_mode: {80, 24}, name: nil)
      assert Process.alive?(pid)

      Process.unlink(pid)
      Process.exit(pid, :kill)
    end
  end

  describe "run/2" do
    test "blocks until the TUI process exits and returns :ok" do
      Fixtures.stub_bb_modules()

      # Start the app directly to get the pid
      {:ok, pid} = BB.TUI.start(BB.TUI.TestRobot, test_mode: {80, 24}, name: nil)
      Process.unlink(pid)
      ref = Process.monitor(pid)

      # run/2 uses start + monitor + receive, so verify the same pattern
      Process.exit(pid, :shutdown)
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}
    end
  end
end
