defmodule BB.TUITest do
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Test.Fixtures

  setup :set_mimic_global

  describe "start/1" do
    test "starts the TUI app in test mode" do
      Fixtures.stub_bb_modules()

      {:ok, pid} = BB.TUI.start(BB.TUI.TestRobot, test_mode: {80, 24}, name: nil)
      assert Process.alive?(pid)

      Process.unlink(pid)
      Process.exit(pid, :kill)
    end
  end
end
