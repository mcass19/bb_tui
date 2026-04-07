defmodule BB.TUI.Robot do
  @moduledoc """
  Routing layer for BB.* calls used by the TUI.

  When the TUI is launched against a remote BEAM node (via
  `BB.TUI.run(robot, node: :"robot@host")`) all robot data needs to come
  from that node — but the rendering, keyboard input and process state
  live locally on the developer's machine. This module is the boundary
  that decides where each call goes:

    * `node == nil` — call the local `BB.*` module directly.
    * `node` is a connected remote node atom — call via `:rpc.call/4`.

  ## PubSub across nodes

  `BB.PubSub` is built on `Registry`, which is node-local, so we cannot
  simply call `BB.subscribe/2` from the dev node and expect to receive
  messages published on the robot node. Instead `subscribe/3` spawns a
  small relay process on the remote node via `Node.spawn_link/2`. The
  relay subscribes locally there and forwards every `{:bb, _, _}`
  message back to the TUI process on the dev node.

  This is the only "process with a runtime reason" introduced by the
  remote path: it exists because we need (1) a place to receive PubSub
  messages on the remote node and (2) fault isolation if the remote node
  goes away (the link will tear it down on disconnect).
  """

  @typedoc "Either nil for local execution or a connected remote node."
  @type maybe_node :: node() | nil

  # ── PubSub ─────────────────────────────────────────────────

  @doc """
  Subscribes to one or more PubSub paths for the given robot.

  Local node — calls `BB.subscribe/2` for each path directly so messages
  arrive at `self()`.

  Remote node — spawns a relay process on the remote node that subscribes
  there and forwards every `{:bb, _, _}` message back to `self()`.
  """
  @spec subscribe(module(), [list()], maybe_node()) :: :ok
  def subscribe(robot, paths, nil) when is_list(paths) do
    Enum.each(paths, &BB.subscribe(robot, &1))
    :ok
  end

  def subscribe(robot, paths, node) when is_list(paths) and is_atom(node) do
    parent = self()

    Node.spawn_link(node, fn ->
      Enum.each(paths, &BB.subscribe(robot, &1))
      relay_loop(parent)
    end)

    :ok
  end

  defp relay_loop(parent) do
    receive do
      {:bb, _, _} = msg ->
        send(parent, msg)
        relay_loop(parent)

      _ ->
        relay_loop(parent)
    end
  end

  # ── Read calls ─────────────────────────────────────────────

  @doc "Returns the safety state of the robot."
  @spec safety_state(module(), maybe_node()) :: atom()
  def safety_state(robot, nil), do: BB.Safety.state(robot)
  def safety_state(robot, node), do: rpc(node, BB.Safety, :state, [robot])

  @doc "Returns the runtime state machine state."
  @spec runtime_state(module(), maybe_node()) :: atom()
  def runtime_state(robot, nil), do: BB.Robot.Runtime.state(robot)
  def runtime_state(robot, node), do: rpc(node, BB.Robot.Runtime, :state, [robot])

  @doc "Returns the runtime robot struct (joints, actuators, etc.)."
  @spec get_robot(module(), maybe_node()) :: term()
  def get_robot(robot, nil), do: BB.Robot.Runtime.get_robot(robot)
  def get_robot(robot, node), do: rpc(node, BB.Robot.Runtime, :get_robot, [robot])

  @doc "Returns the latest joint positions known by the runtime."
  @spec positions(module(), maybe_node()) :: %{atom() => float()}
  def positions(robot, nil), do: BB.Robot.Runtime.positions(robot)
  def positions(robot, node), do: rpc(node, BB.Robot.Runtime, :positions, [robot])

  @doc "Returns the parameter list (with metadata maps) for the robot."
  @spec list_parameters(module(), keyword(), maybe_node()) :: [{list(), term()}]
  def list_parameters(robot, opts, nil), do: BB.Parameter.list(robot, opts)
  def list_parameters(robot, opts, node), do: rpc(node, BB.Parameter, :list, [robot, opts])

  @doc """
  Returns the list of declared commands for the robot, or `[]` if the
  command DSL is not available or raises.
  """
  @spec discover_commands(module(), maybe_node()) :: [term()]
  def discover_commands(robot, nil) do
    if Code.ensure_loaded?(BB.Dsl.Info) and function_exported?(BB.Dsl.Info, :commands, 1) do
      BB.Dsl.Info.commands(robot)
    else
      []
    end
  rescue
    _ -> []
  end

  def discover_commands(robot, node) do
    case :rpc.call(node, BB.Dsl.Info, :commands, [robot]) do
      {:badrpc, _} -> []
      result when is_list(result) -> result
      _ -> []
    end
  rescue
    _ -> []
  end

  # ── Write calls ────────────────────────────────────────────

  @doc "Arms the robot."
  @spec arm(module(), maybe_node()) :: term()
  def arm(robot, nil), do: BB.Safety.arm(robot)
  def arm(robot, node), do: rpc(node, BB.Safety, :arm, [robot])

  @doc "Disarms the robot."
  @spec disarm(module(), maybe_node()) :: term()
  def disarm(robot, nil), do: BB.Safety.disarm(robot)
  def disarm(robot, node), do: rpc(node, BB.Safety, :disarm, [robot])

  @doc "Force-disarms the robot from an error state."
  @spec force_disarm(module(), maybe_node()) :: term()
  def force_disarm(robot, nil), do: BB.Safety.force_disarm(robot)
  def force_disarm(robot, node), do: rpc(node, BB.Safety, :force_disarm, [robot])

  @doc "Commands an actuator to a position."
  @spec set_actuator(module(), atom(), number(), maybe_node()) :: term()
  def set_actuator(robot, actuator, position, nil) do
    BB.Actuator.set_position!(robot, actuator, position)
  end

  def set_actuator(robot, actuator, position, node) do
    rpc(node, BB.Actuator, :set_position!, [robot, actuator, position])
  end

  @doc "Publishes a PubSub message under the robot's topic."
  @spec publish(module(), list(), term(), maybe_node()) :: term()
  def publish(robot, path, msg, nil), do: BB.publish(robot, path, msg)
  def publish(robot, path, msg, node), do: rpc(node, BB, :publish, [robot, path, msg])

  @doc "Sets a parameter value."
  @spec set_parameter(module(), list(), term(), maybe_node()) :: term()
  def set_parameter(robot, path, value, nil) do
    BB.Parameter.set(robot, path, value)
  end

  def set_parameter(robot, path, value, node) do
    rpc(node, BB.Parameter, :set, [robot, path, value])
  end

  @doc """
  Executes a command on the runtime.

  Returns whatever the runtime returns — typically `{:ok, pid}` for the
  command process, or `{:error, reason}`. Cross-node pids are tracked
  transparently by the Erlang distribution layer.
  """
  @spec execute_command(module(), atom(), map(), maybe_node()) ::
          {:ok, pid()} | {:error, term()}
  def execute_command(robot, name, args, nil) do
    BB.Robot.Runtime.execute(robot, name, args)
  end

  def execute_command(robot, name, args, node) do
    rpc(node, BB.Robot.Runtime, :execute, [robot, name, args])
  end

  # ── Internal ───────────────────────────────────────────────

  defp rpc(node, mod, fun, args) do
    case :rpc.call(node, mod, fun, args) do
      {:badrpc, reason} ->
        raise "BB.TUI.Robot: remote call #{inspect(mod)}.#{fun}/#{length(args)} " <>
                "on #{inspect(node)} failed: #{inspect(reason)}"

      result ->
        result
    end
  end
end
