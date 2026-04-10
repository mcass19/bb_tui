defmodule Mix.Tasks.Bb.TuiTest do
  use ExUnit.Case, async: false
  use Mimic

  setup :set_mimic_global

  setup do
    test_pid = self()

    # Capture Mix.shell output instead of printing to stdout.
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    # The mix task calls BB.TUI.run/2 which calls BB.TUI.App.start_link/1.
    # We can't copy BB.TUI globally without losing coverage on its function
    # heads, so instead we mock at the App boundary and let BB.TUI.run/2's
    # real monitor/receive logic execute against a controllable pid.
    Mimic.stub(BB.TUI.App, :start_link, fn opts ->
      send(test_pid, {:app_started, opts})

      pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      send(test_pid, {:app_pid, pid})
      {:ok, pid}
    end)

    :ok
  end

  describe "run/1" do
    test "raises when --robot is missing" do
      assert_raise Mix.Error, ~r/--robot option is required/, fn ->
        Mix.Tasks.Bb.Tui.run([])
      end
    end

    test "translates the --robot string into a module atom and runs the TUI" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run(["--robot", "BB.TUI.TestRobot"])
        end)

      assert_receive {:app_started, opts}, 1_000
      assert opts[:robot] == BB.TUI.TestRobot
      refute Keyword.has_key?(opts, :node)

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end

    test "translates --node into an atom and forwards it through to the App" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run([
            "--robot",
            "BB.TUI.TestRobot",
            "--node",
            "robot@127.0.0.1"
          ])
        end)

      assert_receive {:app_started, opts}, 1_000
      assert opts[:robot] == BB.TUI.TestRobot
      assert opts[:node] == :"robot@127.0.0.1"

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end

    test "--ssh sets transport: :ssh with default port and auto_host_key" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run(["--robot", "BB.TUI.TestRobot", "--ssh"])
        end)

      assert_receive {:app_started, opts}, 1_000
      assert opts[:transport] == :ssh
      assert opts[:port] == 2222
      assert opts[:auto_host_key] == true
      assert opts[:auth_methods] == ~c"password"
      assert opts[:user_passwords] == [{~c"admin", ~c"admin"}]

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end

    test "--ssh --port overrides the default SSH port" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run([
            "--robot",
            "BB.TUI.TestRobot",
            "--ssh",
            "--port",
            "3333"
          ])
        end)

      assert_receive {:app_started, opts}, 1_000
      assert opts[:transport] == :ssh
      assert opts[:port] == 3333

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end

    test "--ssh with --node passes both through" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run([
            "--robot",
            "BB.TUI.TestRobot",
            "--ssh",
            "--node",
            "robot@127.0.0.1"
          ])
        end)

      assert_receive {:app_started, opts}, 1_000
      assert opts[:transport] == :ssh
      assert opts[:app_opts][:node] == :"robot@127.0.0.1"

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end

    test "--port without --ssh is ignored" do
      task =
        Task.async(fn ->
          Mix.Tasks.Bb.Tui.run(["--robot", "BB.TUI.TestRobot", "--port", "3333"])
        end)

      assert_receive {:app_started, opts}, 1_000
      refute Keyword.has_key?(opts, :transport)
      refute Keyword.has_key?(opts, :port)

      assert_receive {:app_pid, pid}
      send(pid, :stop)

      Task.await(task, 1_000)
    end
  end
end
