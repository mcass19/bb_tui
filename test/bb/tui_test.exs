defmodule BB.TUITest do
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Test.Fixtures

  setup :set_mimic_global

  describe "child_spec/1" do
    test "returns a worker spec routed through start/2 with the robot option" do
      spec = BB.TUI.child_spec(robot: BB.TUI.TestRobot, test_mode: {80, 24})

      assert %{
               id: BB.TUI,
               start: {BB.TUI, :start, [BB.TUI.TestRobot, opts]},
               type: :worker,
               restart: :temporary
             } = spec

      assert opts[:test_mode] == {80, 24}
      refute Keyword.has_key?(opts, :robot)
    end

    test "passes through arbitrary keyword options" do
      spec = BB.TUI.child_spec(robot: BB.TUI.TestRobot, node: :"robot@127.0.0.1")

      {BB.TUI, :start, [BB.TUI.TestRobot, opts]} = spec.start
      assert opts[:node] == :"robot@127.0.0.1"
    end

    test "passes transport: :ssh through to start/2" do
      spec =
        BB.TUI.child_spec(
          robot: BB.TUI.TestRobot,
          transport: :ssh,
          port: 3333,
          auto_host_key: true
        )

      {BB.TUI, :start, [BB.TUI.TestRobot, opts]} = spec.start
      assert opts[:transport] == :ssh
      assert opts[:port] == 3333
      assert opts[:auto_host_key] == true
    end
  end

  describe "start/2" do
    test "starts the TUI app in test mode" do
      Fixtures.stub_bb_modules()

      {:ok, pid} = BB.TUI.start(BB.TUI.TestRobot, test_mode: {80, 24}, name: nil)
      assert Process.alive?(pid)

      Process.unlink(pid)
      GenServer.stop(pid)
    end

    test "start/1 defaults opts to []" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts == [robot: BB.TUI.TestRobot]
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} = BB.TUI.start(BB.TUI.TestRobot)
    end

    test "forwards the :node option through to the App so the Robot routing layer sees it" do
      Fixtures.stub_bb_modules()

      # Stub the Rpc layer so the App's remote-path mount calls don't try
      # to actually reach :"robot@127.0.0.1".
      Mimic.stub(BB.TUI.Rpc, :call, fn _node, mod, fun, args ->
        apply(mod, fun, args)
      end)

      Mimic.stub(BB.TUI.Rpc, :spawn_link, fn _node, fun ->
        spawn_link(fun)
      end)

      {:ok, pid} =
        BB.TUI.start(BB.TUI.TestRobot,
          test_mode: {80, 24},
          name: nil,
          node: :"robot@127.0.0.1"
        )

      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert state.user_state.node == :"robot@127.0.0.1"

      Process.unlink(pid)
      GenServer.stop(pid)
    end

    test "wraps :robot into :app_opts when transport is :ssh" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:transport] == :ssh
        assert opts[:app_opts][:robot] == BB.TUI.TestRobot
        refute Keyword.has_key?(opts, :robot)
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} = BB.TUI.start(BB.TUI.TestRobot, transport: :ssh, port: 0)
    end

    test "wraps :node into :app_opts when transport is :ssh" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:app_opts][:robot] == BB.TUI.TestRobot
        assert opts[:app_opts][:node] == :"robot@127.0.0.1"
        refute Keyword.has_key?(opts, :node)
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} =
               BB.TUI.start(BB.TUI.TestRobot,
                 transport: :ssh,
                 port: 0,
                 node: :"robot@127.0.0.1"
               )
    end
  end

  describe "start_ssh/2" do
    test "sets transport: :ssh and wraps :robot into :app_opts" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:transport] == :ssh
        assert opts[:app_opts][:robot] == BB.TUI.TestRobot
        assert opts[:port] == 4444
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} = BB.TUI.start_ssh(BB.TUI.TestRobot, port: 4444)
    end

    test "forwards :node into :app_opts" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:app_opts][:node] == :"robot@127.0.0.1"
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} =
               BB.TUI.start_ssh(BB.TUI.TestRobot,
                 port: 0,
                 node: :"robot@127.0.0.1"
               )
    end

    test "merges caller-supplied :app_opts with :robot" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:app_opts][:robot] == BB.TUI.TestRobot
        assert opts[:app_opts][:custom] == :value
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} =
               BB.TUI.start_ssh(BB.TUI.TestRobot, port: 0, app_opts: [custom: :value])
    end

    test "defaults opts to []" do
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:transport] == :ssh
        assert opts[:app_opts][:robot] == BB.TUI.TestRobot
        {:ok, spawn(fn -> :ok end)}
      end)

      assert {:ok, _pid} = BB.TUI.start_ssh(BB.TUI.TestRobot)
    end
  end

  describe "subsystem/1" do
    test "returns a subsystem tuple for BB.TUI.App" do
      {name, {mod, args}} = BB.TUI.subsystem(BB.TUI.TestRobot)

      assert name == ~c"Elixir.BB.TUI.App"
      assert mod == ExRatatui.SSH
      assert Keyword.fetch!(args, :subsystem) == true
      assert Keyword.fetch!(args, :mod) == BB.TUI.App
      assert args[:app_opts][:robot] == BB.TUI.TestRobot
    end
  end

  describe "run/2" do
    test "monitors the TUI process and returns :ok when it exits" do
      test_pid = self()

      # Stub App.start_link so we get a controllable pid without spinning
      # up the real ExRatatui server.
      Mimic.expect(BB.TUI.App, :start_link, fn opts ->
        assert opts[:robot] == BB.TUI.TestRobot

        fake_tui =
          spawn(fn ->
            receive do
              :stop -> :ok
            end
          end)

        send(test_pid, {:fake_tui, fake_tui})
        {:ok, fake_tui}
      end)

      runner =
        spawn(fn ->
          result = BB.TUI.run(BB.TUI.TestRobot)
          send(test_pid, {:run_returned, result})
        end)

      assert_receive {:fake_tui, fake_tui}
      send(fake_tui, :stop)

      assert_receive {:run_returned, :ok}, 1_000
      refute Process.alive?(runner)
    end

    test "returns the error tuple when start/2 fails" do
      Mimic.expect(BB.TUI.App, :start_link, fn _opts -> {:error, :nope} end)
      assert {:error, :nope} = BB.TUI.run(BB.TUI.TestRobot)
    end
  end
end
