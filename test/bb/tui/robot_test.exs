defmodule BB.TUI.RobotTest do
  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Robot

  setup :set_mimic_global

  @robot BB.TUI.TestRobot

  describe "subscribe/3 (local)" do
    test "subscribes to each path via BB.subscribe when node is nil" do
      test_pid = self()

      Mimic.expect(BB, :subscribe, fn BB.TUI.TestRobot, [:state_machine] ->
        send(test_pid, {:subscribed, [:state_machine]})
        :ok
      end)

      Mimic.expect(BB, :subscribe, fn BB.TUI.TestRobot, [:sensor] ->
        send(test_pid, {:subscribed, [:sensor]})
        :ok
      end)

      assert :ok = Robot.subscribe(@robot, [[:state_machine], [:sensor]], nil)
      assert_received {:subscribed, [:state_machine]}
      assert_received {:subscribed, [:sensor]}
    end
  end

  describe "read calls (local)" do
    setup do
      Mimic.stub(BB.Safety, :state, fn BB.TUI.TestRobot -> :disarmed end)
      Mimic.stub(BB.Robot.Runtime, :state, fn BB.TUI.TestRobot -> :idle end)
      Mimic.stub(BB.Robot.Runtime, :get_robot, fn BB.TUI.TestRobot -> %{name: @robot} end)
      Mimic.stub(BB.Robot.Runtime, :positions, fn BB.TUI.TestRobot -> %{shoulder: 1.0} end)

      Mimic.stub(BB.Parameter, :list, fn BB.TUI.TestRobot, [] ->
        [{[:speed], %{value: 100, type: :integer}}]
      end)

      :ok
    end

    test "safety_state/2 delegates locally when node is nil" do
      assert Robot.safety_state(@robot, nil) == :disarmed
    end

    test "runtime_state/2 delegates locally when node is nil" do
      assert Robot.runtime_state(@robot, nil) == :idle
    end

    test "get_robot/2 delegates locally when node is nil" do
      assert Robot.get_robot(@robot, nil) == %{name: @robot}
    end

    test "positions/2 delegates locally when node is nil" do
      assert Robot.positions(@robot, nil) == %{shoulder: 1.0}
    end

    test "list_parameters/3 delegates locally when node is nil" do
      assert Robot.list_parameters(@robot, [], nil) == [
               {[:speed], %{value: 100, type: :integer}}
             ]
    end
  end

  describe "discover_commands/2 (local)" do
    test "returns commands when BB.Dsl.Info is loaded and exports commands/1" do
      Mimic.stub(BB.Dsl.Info, :commands, fn BB.TUI.TestRobot -> [%{name: :home}] end)
      assert Robot.discover_commands(@robot, nil) == [%{name: :home}]
    end

    test "returns [] when BB.Dsl.Info.commands raises" do
      Mimic.stub(BB.Dsl.Info, :commands, fn _ -> raise "boom" end)
      assert Robot.discover_commands(@robot, nil) == []
    end
  end

  describe "write calls (local)" do
    test "arm/2 delegates locally when node is nil" do
      Mimic.expect(BB.Safety, :arm, fn BB.TUI.TestRobot -> :armed end)
      assert Robot.arm(@robot, nil) == :armed
    end

    test "disarm/2 delegates locally when node is nil" do
      Mimic.expect(BB.Safety, :disarm, fn BB.TUI.TestRobot -> :disarmed end)
      assert Robot.disarm(@robot, nil) == :disarmed
    end

    test "force_disarm/2 delegates locally when node is nil" do
      Mimic.expect(BB.Safety, :force_disarm, fn BB.TUI.TestRobot -> :ok end)
      assert Robot.force_disarm(@robot, nil) == :ok
    end

    test "set_actuator/4 delegates locally when node is nil" do
      Mimic.expect(BB.Actuator, :set_position!, fn BB.TUI.TestRobot, :servo_1, 0.5 -> :ok end)
      assert Robot.set_actuator(@robot, :servo_1, 0.5, nil) == :ok
    end

    test "publish/4 delegates locally when node is nil" do
      Mimic.expect(BB, :publish, fn BB.TUI.TestRobot, [:sensor, :sim], :payload -> :ok end)
      assert Robot.publish(@robot, [:sensor, :sim], :payload, nil) == :ok
    end

    test "set_parameter/4 delegates locally when node is nil" do
      Mimic.expect(BB.Parameter, :set, fn BB.TUI.TestRobot, [:speed], 200 -> :ok end)
      assert Robot.set_parameter(@robot, [:speed], 200, nil) == :ok
    end

    test "execute_command/4 delegates locally when node is nil" do
      Mimic.expect(BB.Robot.Runtime, :execute, fn BB.TUI.TestRobot, :home, %{} ->
        {:ok, self()}
      end)

      assert {:ok, _pid} = Robot.execute_command(@robot, :home, %{}, nil)
    end
  end

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

      assert :ok =
               Robot.subscribe(@robot, [[:state_machine], [:sensor]], remote)

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

  describe "read calls (remote)" do
    @remote :"robot@127.0.0.1"

    test "safety_state/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Safety, :state, [BB.TUI.TestRobot] ->
        :armed
      end)

      assert Robot.safety_state(@robot, @remote) == :armed
    end

    test "runtime_state/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :state, [BB.TUI.TestRobot] ->
        :idle
      end)

      assert Robot.runtime_state(@robot, @remote) == :idle
    end

    test "get_robot/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Robot.Runtime,
                                         :get_robot,
                                         [BB.TUI.TestRobot] ->
        %{name: BB.TUI.TestRobot}
      end)

      assert Robot.get_robot(@robot, @remote) == %{name: BB.TUI.TestRobot}
    end

    test "positions/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Robot.Runtime,
                                         :positions,
                                         [BB.TUI.TestRobot] ->
        %{shoulder: 1.5}
      end)

      assert Robot.positions(@robot, @remote) == %{shoulder: 1.5}
    end

    test "list_parameters/3 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Parameter, :list, [BB.TUI.TestRobot, []] ->
        [{[:speed], %{value: 100, type: :integer}}]
      end)

      assert Robot.list_parameters(@robot, [], @remote) == [
               {[:speed], %{value: 100, type: :integer}}
             ]
    end

    test "raises when :rpc.call returns {:badrpc, reason}" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Safety, :state, [BB.TUI.TestRobot] ->
        {:badrpc, :nodedown}
      end)

      assert_raise RuntimeError, ~r/remote call.*Safety.state\/1.*nodedown/, fn ->
        Robot.safety_state(@robot, @remote)
      end
    end
  end

  describe "discover_commands/2 (remote)" do
    @remote :"robot@127.0.0.1"

    test "returns the list when :rpc.call yields a list" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :commands, [BB.TUI.TestRobot] ->
        [%{name: :home}]
      end)

      assert Robot.discover_commands(@robot, @remote) == [%{name: :home}]
    end

    test "returns [] when :rpc.call returns {:badrpc, _}" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :commands, [BB.TUI.TestRobot] ->
        {:badrpc, :nodedown}
      end)

      assert Robot.discover_commands(@robot, @remote) == []
    end

    test "returns [] when :rpc.call returns a non-list value" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :commands, [BB.TUI.TestRobot] ->
        :something_unexpected
      end)

      assert Robot.discover_commands(@robot, @remote) == []
    end

    test "returns [] when :rpc.call raises" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :commands, [BB.TUI.TestRobot] ->
        raise "boom"
      end)

      assert Robot.discover_commands(@robot, @remote) == []
    end
  end

  describe "write calls (remote)" do
    @remote :"robot@127.0.0.1"

    test "arm/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Safety, :arm, [BB.TUI.TestRobot] ->
        :armed
      end)

      assert Robot.arm(@robot, @remote) == :armed
    end

    test "disarm/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Safety, :disarm, [BB.TUI.TestRobot] ->
        :disarmed
      end)

      assert Robot.disarm(@robot, @remote) == :disarmed
    end

    test "force_disarm/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Safety, :force_disarm, [BB.TUI.TestRobot] ->
        :ok
      end)

      assert Robot.force_disarm(@robot, @remote) == :ok
    end

    test "set_actuator/4 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Actuator,
                                         :set_position!,
                                         [BB.TUI.TestRobot, :servo_1, 0.5] ->
        :ok
      end)

      assert Robot.set_actuator(@robot, :servo_1, 0.5, @remote) == :ok
    end

    test "publish/4 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB,
                                         :publish,
                                         [BB.TUI.TestRobot, [:sensor, :sim], :payload] ->
        :ok
      end)

      assert Robot.publish(@robot, [:sensor, :sim], :payload, @remote) == :ok
    end

    test "set_parameter/4 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Parameter,
                                         :set,
                                         [BB.TUI.TestRobot, [:speed], 200] ->
        :ok
      end)

      assert Robot.set_parameter(@robot, [:speed], 200, @remote) == :ok
    end

    test "execute_command/4 routes through :rpc.call" do
      reply_pid = self()

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Robot.Runtime,
                                         :execute,
                                         [BB.TUI.TestRobot, :home, %{}] ->
        {:ok, reply_pid}
      end)

      assert {:ok, ^reply_pid} = Robot.execute_command(@robot, :home, %{}, @remote)
    end
  end
end
