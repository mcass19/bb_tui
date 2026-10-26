defmodule BB.TUI.Test.RemoteRobot do
  @moduledoc false
  # A real (DSL-built) robot for the `:distributed` tests, which start it on a
  # `:peer` node and attach a dashboard with `node:`. Kept to what those tests
  # drive: a fast and a slow command, a string parameter, and one actuated
  # joint. Compiled to disk so the peer can load it.
  use BB
  import BB.Unit

  settings do
    name(:remote_robot)
  end

  commands do
    command :home do
      handler(BB.TUI.Test.InstantCommand)
      allowed_states([:idle])
    end

    command :calibrate do
      handler(BB.TUI.Test.SlowCommand)
      allowed_states([:idle])
    end
  end

  parameters do
    group :identity do
      param(:label, type: :string, default: "remote")
    end
  end

  topology do
    link :base do
      joint :shoulder do
        type(:revolute)

        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
          effort(~u(10 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        actuator(:shoulder_servo, BB.TUI.Test.Servo)

        sensor(
          :shoulder_position,
          {BB.Sensor.OpenLoopPositionEstimator, actuator: :shoulder_servo}
        )

        link(:arm)
      end
    end
  end
end

defmodule BB.TUI.Test.InstantCommand do
  @moduledoc false
  # Finishes inside handle_command/3, so it is gone before anyone can await it:
  # the await is answered from bb's node-local ResultCache.
  use BB.Command

  alias BB.Dsl.Info

  @impl BB.Command
  def handle_command(goal, context, state) do
    next_state = Info.initial_state(context.robot_module)
    {:stop, :normal, %{state | result: {:ok, goal}, next_state: next_state}}
  end

  @impl BB.Command
  def result(%{result: {:ok, value}, next_state: next_state}),
    do: {:ok, value, next_state: next_state}
end

defmodule BB.TUI.Test.SlowCommand do
  @moduledoc false
  # Runs until cancelled (or for a minute), staying responsive so a cancel lands.
  use BB.Command

  @impl BB.Command
  def handle_command(_goal, _context, state) do
    Process.send_after(self(), :done, 60_000)
    {:noreply, state}
  end

  @impl BB.Command
  def handle_info(:done, state), do: {:stop, :normal, %{state | result: {:ok, :done}}}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl BB.Command
  def result(%{result: {:ok, _} = result}), do: result
  def result(_state), do: {:error, :cancelled}
end

defmodule BB.TUI.Test.Servo do
  @moduledoc false
  # Stand-in driver: kinematic simulation swaps it for BB.Sim.Actuator.
  use BB.Actuator, options_schema: []

  @impl BB.Actuator
  def init(_opts), do: {:ok, %{}}

  @impl BB.Actuator
  def handle_command(_command, state), do: {:noreply, state}

  @impl BB.Actuator
  def disarm(_opts), do: :ok
end

defmodule BB.TUI.Test.PeerHelper do
  @moduledoc false
  # Runs on the `:peer` node. `BB.Supervisor.start_link/2` links the robot to
  # its caller, which under `:rpc.call` is a process that exits as soon as the
  # call returns — so the robot is unlinked straight away.

  def start_robot_unlinked(robot) do
    {:ok, _} = Application.ensure_all_started(:bb)
    {:ok, pid} = BB.Supervisor.start_link(robot, simulation: :kinematic)
    Process.unlink(pid)
    {:ok, pid}
  end
end
