defmodule BB.TUI.RobotTest do
  use ExUnit.Case, async: true
  use Mimic

  alias BB.TUI.Robot

  setup :set_mimic_private

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
      Mimic.stub(BB.Robot.Runtime, :configurations, fn BB.TUI.TestRobot -> %{shoulder: 1.0} end)

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

    test "configurations/2 delegates locally when node is nil" do
      assert Robot.configurations(@robot, nil) == %{shoulder: 1.0}
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

      assert [
               %{
                 name: :home,
                 handler: nil,
                 timeout: :infinity,
                 allowed_states: [],
                 arguments: []
               }
             ] = Robot.discover_commands(@robot, nil)
    end

    test "normalizes argument types to strings (mirrors bb_liveview)" do
      Mimic.stub(BB.Dsl.Info, :commands, fn BB.TUI.TestRobot ->
        [
          %{
            name: :move,
            arguments: [
              %{name: :angle, type: :float, default: 0.0, required: true, doc: "Radians"},
              %{name: :side, type: {:in, [:left, :right]}, default: :left}
            ]
          }
        ]
      end)

      [%{arguments: [angle_arg, side_arg]}] = Robot.discover_commands(@robot, nil)
      assert angle_arg.type == "float"
      assert angle_arg.required == true
      assert angle_arg.enum_values == nil
      assert side_arg.type == "enum:[:left, :right]"
      assert side_arg.required == false
      assert side_arg.enum_values == [:left, :right]
    end

    test "returns [] when BB.Dsl.Info.commands raises" do
      Mimic.stub(BB.Dsl.Info, :commands, fn _ -> raise "boom" end)
      assert Robot.discover_commands(@robot, nil) == []
    end

    test "renders unknown argument-type shapes via inspect/1 fallback" do
      Mimic.stub(BB.Dsl.Info, :commands, fn BB.TUI.TestRobot ->
        [
          %{
            name: :weird,
            arguments: [
              %{name: :payload, type: {:struct, SomeFutureType, []}}
            ]
          }
        ]
      end)

      [%{arguments: [arg]}] = Robot.discover_commands(@robot, nil)
      assert arg.type == "{:struct, SomeFutureType, []}"
    end
  end

  describe "controllers" do
    @remote :"robot@127.0.0.1"

    test "list_controllers/2 reads each controller's name, module and simulation mode" do
      Mimic.stub(BB.Dsl.Info, :controllers, fn BB.TUI.TestRobot ->
        [
          %BB.Dsl.Controller{name: :balancer, child_spec: {MyBot.Balancer, gain: 2}},
          %BB.Dsl.Controller{name: :yaw, child_spec: MyBot.Yaw, simulation: :start}
        ]
      end)

      assert Robot.list_controllers(@robot, nil) == [
               %{name: :balancer, module: MyBot.Balancer, simulation: :omit},
               %{name: :yaw, module: MyBot.Yaw, simulation: :start}
             ]
    end

    test "list_controllers/2 is empty when the DSL can't be read" do
      Mimic.stub(BB.Dsl.Info, :controllers, fn _robot -> raise ArgumentError end)
      assert Robot.list_controllers(@robot, nil) == []

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :controllers, [_] ->
        {:badrpc, :nodedown}
      end)

      assert Robot.list_controllers(@robot, @remote) == []
    end

    test "controllers_alive/3 looks each controller up in the robot's registry" do
      pid = self()

      Mimic.stub(BB.Process, :whereis, fn
        BB.TUI.TestRobot, :balancer -> pid
        BB.TUI.TestRobot, :yaw -> :undefined
      end)

      assert Robot.controllers_alive(@robot, [:balancer, :yaw], nil) == %{
               balancer: true,
               yaw: false
             }
    end

    test "controllers_alive/3 says none run when the robot isn't running" do
      Mimic.stub(BB.Process, :whereis, fn _robot, _name -> raise ArgumentError end)
      assert Robot.controllers_alive(@robot, [:balancer], nil) == %{balancer: false}
    end

    test "controllers_alive/3 asks the robot's node once, and claims nothing when it can't" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         Robot,
                                         :controllers_alive,
                                         [BB.TUI.TestRobot, [:balancer], nil] ->
        %{balancer: true}
      end)

      assert Robot.controllers_alive(@robot, [:balancer], @remote) == %{balancer: true}

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, Robot, :controllers_alive, _args ->
        {:badrpc, :timeout}
      end)

      assert Robot.controllers_alive(@robot, [:balancer], @remote) == %{}
    end
  end

  describe "list_bridges/2 (local)" do
    test "returns bridge structs as plain maps, filtering :omit in sim mode" do
      Mimic.stub(BB.Robot.Runtime, :simulation_mode, fn BB.TUI.TestRobot -> :mock end)

      Mimic.stub(BB.Dsl.Info, :parameters, fn BB.TUI.TestRobot ->
        [
          %BB.Dsl.Bridge{name: :mavlink, simulation: :start},
          %BB.Dsl.Bridge{name: :ros, simulation: :omit},
          %BB.Dsl.Param{}
        ]
      end)

      bridges = Robot.list_bridges(@robot, nil)
      assert bridges == [%{name: :mavlink, simulation: :start}]
    end

    test "keeps :omit bridges when no simulation mode is reported" do
      Mimic.stub(BB.Robot.Runtime, :simulation_mode, fn _ -> nil end)

      Mimic.stub(BB.Dsl.Info, :parameters, fn _ ->
        [%BB.Dsl.Bridge{name: :ros, simulation: :omit}]
      end)

      assert Robot.list_bridges(@robot, nil) == [%{name: :ros, simulation: :omit}]
    end

    test "tolerates simulation_mode raising" do
      Mimic.stub(BB.Robot.Runtime, :simulation_mode, fn _ -> raise "boom" end)
      Mimic.stub(BB.Dsl.Info, :parameters, fn _ -> [] end)

      assert Robot.list_bridges(@robot, nil) == []
    end

    test "tolerates simulation_mode exiting" do
      Mimic.stub(BB.Robot.Runtime, :simulation_mode, fn _ -> exit(:noproc) end)
      Mimic.stub(BB.Dsl.Info, :parameters, fn _ -> [] end)

      assert Robot.list_bridges(@robot, nil) == []
    end

    test "returns [] when BB.Dsl.Info.parameters raises" do
      Mimic.stub(BB.Robot.Runtime, :simulation_mode, fn _ -> nil end)
      Mimic.stub(BB.Dsl.Info, :parameters, fn _ -> raise "boom" end)

      assert Robot.list_bridges(@robot, nil) == []
    end
  end

  describe "list_remote_parameters/3 (local)" do
    test "delegates to BB.Parameter.list_remote and returns its tuple" do
      Mimic.expect(BB.Parameter, :list_remote, fn BB.TUI.TestRobot, :mavlink ->
        {:ok, [%{id: "PITCH_P", value: 0.1}]}
      end)

      assert Robot.list_remote_parameters(@robot, :mavlink, nil) ==
               {:ok, [%{id: "PITCH_P", value: 0.1}]}
    end

    test "wraps raised exceptions as {:error, message}" do
      Mimic.expect(BB.Parameter, :list_remote, fn _, _ -> raise "boom" end)

      assert {:error, "boom"} = Robot.list_remote_parameters(@robot, :mavlink, nil)
    end

    test "wraps caller exit as {:error, reason}" do
      Mimic.expect(BB.Parameter, :list_remote, fn _, _ -> exit(:noproc) end)

      assert {:error, :noproc} = Robot.list_remote_parameters(@robot, :mavlink, nil)
    end
  end

  describe "set_remote_parameter/5 (local)" do
    test "delegates to BB.Parameter.set_remote" do
      Mimic.expect(BB.Parameter, :set_remote, fn BB.TUI.TestRobot, :mavlink, "PITCH_P", 0.2 ->
        :ok
      end)

      assert Robot.set_remote_parameter(@robot, :mavlink, "PITCH_P", 0.2, nil) == :ok
    end

    test "wraps raised exceptions" do
      Mimic.expect(BB.Parameter, :set_remote, fn _, _, _, _ -> raise "boom" end)

      assert {:error, "boom"} =
               Robot.set_remote_parameter(@robot, :mavlink, "PITCH_P", 0.2, nil)
    end

    test "wraps caller exit" do
      Mimic.expect(BB.Parameter, :set_remote, fn _, _, _, _ -> exit(:noproc) end)

      assert {:error, :noproc} =
               Robot.set_remote_parameter(@robot, :mavlink, "PITCH_P", 0.2, nil)
    end
  end

  describe "remote bridge calls via :rpc.call" do
    @remote :"robot@127.0.0.1"

    test "list_bridges routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        nil
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        [%BB.Dsl.Bridge{name: :mavlink, simulation: :start}]
      end)

      assert Robot.list_bridges(@robot, @remote) ==
               [%{name: :mavlink, simulation: :start}]
    end

    test "list_bridges returns [] when :rpc.call yields {:badrpc, _}" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        nil
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        {:badrpc, :nodedown}
      end)

      assert Robot.list_bridges(@robot, @remote) == []
    end

    test "list_bridges returns [] when :rpc.call yields a non-list value" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        nil
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        :something_unexpected
      end)

      assert Robot.list_bridges(@robot, @remote) == []
    end

    test "list_bridges returns [] when :rpc.call raises" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        nil
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        raise "boom"
      end)

      assert Robot.list_bridges(@robot, @remote) == []
    end

    test "list_bridges filters :omit when simulation_mode RPC reports a mode" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        :mock
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        [
          %BB.Dsl.Bridge{name: :mavlink, simulation: :start},
          %BB.Dsl.Bridge{name: :ros, simulation: :omit}
        ]
      end)

      assert Robot.list_bridges(@robot, @remote) == [
               %{name: :mavlink, simulation: :start}
             ]
    end

    test "list_bridges treats :badrpc from simulation_mode as 'no sim mode'" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        {:badrpc, :nodedown}
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        [%BB.Dsl.Bridge{name: :ros, simulation: :omit}]
      end)

      assert Robot.list_bridges(@robot, @remote) == [%{name: :ros, simulation: :omit}]
    end

    test "list_bridges treats non-atom simulation_mode response as nil" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Robot.Runtime, :simulation_mode, _ ->
        "unexpected"
      end)

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :parameters, _ ->
        [%BB.Dsl.Bridge{name: :ros, simulation: :omit}]
      end)

      assert Robot.list_bridges(@robot, @remote) == [%{name: :ros, simulation: :omit}]
    end

    test "list_remote_parameters routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Parameter, :list_remote, _ ->
        {:ok, [%{id: "PITCH_P", value: 0.1}]}
      end)

      assert Robot.list_remote_parameters(@robot, :mavlink, @remote) ==
               {:ok, [%{id: "PITCH_P", value: 0.1}]}
    end

    test "list_remote_parameters maps {:badrpc, _} to {:error, _}" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Parameter, :list_remote, _ ->
        {:badrpc, :nodedown}
      end)

      assert Robot.list_remote_parameters(@robot, :mavlink, @remote) ==
               {:error, :nodedown}
    end

    test "set_remote_parameter routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Parameter, :set_remote, _ -> :ok end)

      assert Robot.set_remote_parameter(@robot, :mavlink, "PITCH_P", 0.2, @remote) == :ok
    end

    test "set_remote_parameter maps {:badrpc, _} to {:error, _}" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Parameter, :set_remote, _ ->
        {:badrpc, :nodedown}
      end)

      assert Robot.set_remote_parameter(@robot, :mavlink, "PITCH_P", 0.2, @remote) ==
               {:error, :nodedown}
    end
  end

  describe "write calls (local)" do
    test "set_velocity/4 and stop_actuator/3 broadcast locally when node is nil" do
      Mimic.expect(BB.Actuator, :set_velocity, fn BB.TUI.TestRobot, :wheel_motor, 0.4 -> :ok end)
      Mimic.expect(BB.Actuator, :stop, fn BB.TUI.TestRobot, :wheel_motor -> :ok end)

      assert Robot.set_velocity(@robot, :wheel_motor, 0.4, nil) == :ok
      assert Robot.stop_actuator(@robot, :wheel_motor, nil) == :ok
    end

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
      Mimic.expect(BB.Actuator, :set_position, fn BB.TUI.TestRobot,
                                                  :servo_1,
                                                  0.5,
                                                  [timeout: 250] ->
        :ok
      end)

      assert Robot.set_actuator(@robot, :servo_1, 0.5, nil) == :ok
    end

    test "set_actuator/4 returns the actuator's refusal" do
      Mimic.expect(BB.Actuator, :set_position, fn BB.TUI.TestRobot,
                                                  :servo_1,
                                                  0.5,
                                                  [timeout: 250] ->
        {:error, :disarmed}
      end)

      assert Robot.set_actuator(@robot, :servo_1, 0.5, nil) == {:error, :disarmed}
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

    test "await_command/2 awaits locally with :infinity when node is nil" do
      cmd_pid = self()
      Mimic.expect(BB.Command, :await, fn ^cmd_pid, :infinity -> {:ok, :done} end)

      assert Robot.await_command(cmd_pid, nil) == {:ok, :done}
    end

    test "cancel_command/3 cancels by execution id locally when node is nil" do
      id = make_ref()
      Mimic.expect(BB.Command, :cancel, fn @robot, ^id -> :ok end)

      assert Robot.cancel_command(@robot, id, nil) == :ok
    end

    test "cancel_command/3 ignores a command that has already finished" do
      id = make_ref()
      Mimic.expect(BB.Command, :cancel, fn @robot, ^id -> {:error, :not_found} end)

      assert Robot.cancel_command(@robot, id, nil) == :ok
    end

    # BB.Command.cancel/2 ends in GenServer.stop(pid, {:shutdown, :cancelled}),
    # which exits when the command stops for any other reason — a handler that
    # ends cleanly on cancellation exits :normal. bb only catches {:noproc, _},
    # so that exit escapes. This runs inline from update/2, so letting it
    # through kills the whole dashboard.
    test "cancel_command/3 swallows the exit when the command stops normally" do
      id = make_ref()

      Mimic.expect(BB.Command, :cancel, fn @robot, ^id ->
        exit({:normal, {GenServer, :stop, [self(), {:shutdown, :cancelled}, :infinity]}})
      end)

      assert Robot.cancel_command(@robot, id, nil) == :ok
    end

    test "running_commands/2 lists the robot's running commands locally" do
      entry = %{name: :home, execution_id: make_ref(), started_at: DateTime.utc_now()}
      Mimic.expect(BB.Command, :list, fn @robot -> [entry] end)

      assert Robot.running_commands(@robot, nil) == [entry]
    end

    test "running_commands/2 is empty when the robot's registry is not up" do
      Mimic.expect(BB.Command, :list, fn @robot -> raise ArgumentError, "unknown registry" end)

      assert Robot.running_commands(@robot, nil) == []
    end
  end

  # `subscribe/3 (remote)` lives in
  # `test/bb/tui/robot_subscribe_remote_test.exs` because the spawned
  # relay process needs `:set_mimic_global` to see BB.subscribe stubs.

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

    test "configurations/2 routes through :rpc.call" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         BB.Robot.Runtime,
                                         :configurations,
                                         [BB.TUI.TestRobot] ->
        %{shoulder: 1.5}
      end)

      assert Robot.configurations(@robot, @remote) == %{shoulder: 1.5}
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

    test "returns the normalized list when :rpc.call yields commands" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :commands, [BB.TUI.TestRobot] ->
        [%{name: :home}]
      end)

      assert [%{name: :home, arguments: []}] = Robot.discover_commands(@robot, @remote)
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

    test "set_velocity/4 and stop_actuator/3 are cast to the node" do
      Mimic.expect(BB.TUI.Rpc, :cast, fn @remote,
                                         BB.Actuator,
                                         :set_velocity,
                                         [BB.TUI.TestRobot, :wheel_motor, 0.4] ->
        :ok
      end)

      Mimic.expect(BB.TUI.Rpc, :cast, fn @remote,
                                         BB.Actuator,
                                         :stop,
                                         [BB.TUI.TestRobot, :wheel_motor] ->
        :ok
      end)

      assert Robot.set_velocity(@robot, :wheel_motor, 0.4, @remote) == :ok
      assert Robot.stop_actuator(@robot, :wheel_motor, @remote) == :ok
    end

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
                                         :set_position,
                                         [BB.TUI.TestRobot, :servo_1, 0.5, [timeout: 250]] ->
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

    # bb's ResultCache is node-local: awaited from the dashboard's node, a
    # command that already finished reports :noproc although it succeeded.
    test "await_command/2 awaits on the robot's node" do
      cmd_pid = self()

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :await, [^cmd_pid, :infinity] ->
        {:ok, :done}
      end)

      Mimic.reject(&BB.Command.await/2)

      assert Robot.await_command(cmd_pid, @remote) == {:ok, :done}
    end

    test "await_command/2 reports a lost robot node as an error" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :await, _args ->
        {:badrpc, :nodedown}
      end)

      assert Robot.await_command(self(), @remote) == {:error, {:badrpc, :nodedown}}
    end

    test "cancel_command/3 routes through :rpc.call" do
      id = make_ref()

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :cancel, [@robot, ^id] ->
        :ok
      end)

      assert Robot.cancel_command(@robot, id, @remote) == :ok
    end

    # Unlike every other remote call here, a :badrpc from cancel is ignored
    # rather than raised — the command's own events report the outcome.
    test "cancel_command/3 ignores a :badrpc reply instead of raising" do
      id = make_ref()

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :cancel, [@robot, ^id] ->
        {:badrpc, {:EXIT, {:normal, {GenServer, :stop, []}}}}
      end)

      assert Robot.cancel_command(@robot, id, @remote) == :ok
    end

    test "running_commands/2 routes through :rpc.call" do
      entry = %{name: :home, execution_id: make_ref(), started_at: DateTime.utc_now()}
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :list, [@robot] -> [entry] end)

      assert Robot.running_commands(@robot, @remote) == [entry]
    end

    test "running_commands/2 is empty when the remote node can't be reached" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, BB.Command, :list, [@robot] ->
        {:badrpc, :nodedown}
      end)

      assert Robot.running_commands(@robot, @remote) == []
    end
  end

  describe "inspect_controller/3" do
    @remote :"robot@127.0.0.1"

    test "returns the controller's :inspect answer" do
      Mimic.expect(BB.Process, :call, fn @robot, :balancer, :inspect, 200 -> %{lean: 0.1} end)
      assert Robot.inspect_controller(@robot, :balancer, nil) == {:ok, %{lean: 0.1}}
    end

    test "turns a missing, crashing or slow controller into an error" do
      Mimic.expect(BB.Process, :call, fn _robot, _name, _msg, _timeout -> exit(:noproc) end)
      assert Robot.inspect_controller(@robot, :balancer, nil) == {:error, :noproc}
    end

    test "asks on the robot's node" do
      Mimic.expect(BB.TUI.Rpc, :call, fn @remote,
                                         Robot,
                                         :inspect_controller,
                                         [@robot, :yaw, nil] ->
        {:ok, %{heading: 1.0}}
      end)

      assert Robot.inspect_controller(@robot, :yaw, @remote) == {:ok, %{heading: 1.0}}

      Mimic.expect(BB.TUI.Rpc, :call, fn @remote, Robot, :inspect_controller, _args ->
        {:badrpc, :nodedown}
      end)

      assert Robot.inspect_controller(@robot, :yaw, @remote) == {:error, :nodedown}
    end
  end

  describe "exported?/4" do
    @remote :"robot@127.0.0.1"

    test "checks a function here, loading its module" do
      assert Robot.exported?(BB.TUI.Test.Drive, :command, 3, nil)
      refute Robot.exported?(BB.TUI.Test.Drive, :command, 2, nil)
      refute Robot.exported?(BB.TUI.Test.NotHere, :command, 3, nil)
    end

    test "checks a function on the robot's node" do
      Mimic.stub(BB.TUI.Rpc, :call, fn
        @remote, Code, :ensure_loaded?, [BB.TUI.Test.Drive] -> true
        @remote, Code, :ensure_loaded?, [_missing] -> false
        @remote, :erlang, :function_exported, [BB.TUI.Test.Drive, :command, 3] -> true
      end)

      assert Robot.exported?(BB.TUI.Test.Drive, :command, 3, @remote)
      refute Robot.exported?(BB.TUI.Test.NotHere, :command, 3, @remote)
    end

    test "is false when the robot's node can't be reached" do
      Mimic.stub(BB.TUI.Rpc, :call, fn @remote, Code, :ensure_loaded?, _ ->
        {:badrpc, :nodedown}
      end)

      refute Robot.exported?(BB.TUI.Test.Drive, :command, 3, @remote)
    end
  end

  describe "command_payloads/2" do
    @remote :"robot@127.0.0.1"

    defmodule VelocityDriver do
      @moduledoc false
      def command_payloads(_opts), do: [BB.Message.Actuator.Command.Velocity]
    end

    defmodule OptsDriver do
      @moduledoc false
      def command_payloads(opts), do: Keyword.fetch!(opts, :payloads)
    end

    # base ─ wheel (left_motor) ─ hub ─ spin (spin_motor, bare module)
    #      └ lean (no actuator)
    defp topology(spin_driver \\ VelocityDriver) do
      hub = %BB.Dsl.Link{
        name: :hub,
        joints: [
          %BB.Dsl.Joint{
            name: :spin,
            actuators: [%BB.Dsl.Actuator{name: :spin_motor, child_spec: spin_driver}]
          }
        ]
      }

      [
        %BB.Dsl.Link{
          name: :base,
          joints: [
            %BB.Dsl.Joint{
              name: :wheel,
              link: hub,
              actuators: [
                %BB.Dsl.Actuator{
                  name: :left_motor,
                  child_spec: {OptsDriver, payloads: [BB.Message.Actuator.Command.Stop]}
                }
              ]
            },
            %BB.Dsl.Joint{name: :lean, actuators: []}
          ]
        }
      ]
    end

    test "walks the topology and asks each driver with its declared options" do
      Mimic.stub(BB.Dsl.Info, :topology, fn @robot -> topology() end)

      assert Robot.command_payloads(@robot, nil) == %{
               left_motor: [BB.Message.Actuator.Command.Stop],
               spin_motor: [BB.Message.Actuator.Command.Velocity]
             }
    end

    test "leaves out a driver that can't answer from its declared options" do
      # A bare module gets `[]`, so OptsDriver's `fetch!` raises.
      Mimic.stub(BB.Dsl.Info, :topology, fn @robot -> topology(OptsDriver) end)

      assert Robot.command_payloads(@robot, nil) == %{
               left_motor: [BB.Message.Actuator.Command.Stop]
             }
    end

    test "is empty when the topology can't be read" do
      Mimic.stub(BB.Dsl.Info, :topology, fn _ -> raise "no DSL" end)

      assert Robot.command_payloads(@robot, nil) == %{}
    end

    test "asks the remote node for the topology and each driver's list" do
      Mimic.stub(BB.TUI.Rpc, :call, fn
        @remote, BB.Dsl.Info, :topology, [@robot] -> topology()
        @remote, OptsDriver, :command_payloads, [opts] -> opts[:payloads]
        @remote, VelocityDriver, :command_payloads, [[]] -> {:badrpc, :nodedown}
      end)

      assert Robot.command_payloads(@robot, @remote) == %{
               left_motor: [BB.Message.Actuator.Command.Stop]
             }
    end

    test "is empty when the remote topology call fails" do
      Mimic.stub(BB.TUI.Rpc, :call, fn @remote, BB.Dsl.Info, :topology, _ ->
        {:badrpc, :nodedown}
      end)

      assert Robot.command_payloads(@robot, @remote) == %{}
    end
  end
end
