defmodule BB.TUI.Robot do
  @moduledoc """
  Routing layer for BB.* calls used by the TUI.

  When the TUI is launched against a remote BEAM node (via
  `BB.TUI.run(robot, node: :"robot@host")`) all robot data needs to come
  from that node — but the rendering, keyboard input and process state
  live locally on the developer's machine. This module is the boundary
  that decides where each call goes:

    * `node == nil` — call the local `BB.*` module directly.
    * `node` is a connected remote node atom — call via `BB.TUI.Rpc`,
      a thin wrapper over `:rpc.call/4` that exists so the cross-node
      paths can be mocked in tests (`:rpc` itself is a sticky kernel
      module that cannot be replaced at runtime).

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

  alias BB.Dsl.Info
  alias BB.Robot.Runtime
  alias BB.TUI.Rpc

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

    Rpc.spawn_link(node, fn ->
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
  def runtime_state(robot, nil), do: Runtime.state(robot)
  def runtime_state(robot, node), do: rpc(node, BB.Robot.Runtime, :state, [robot])

  @doc "Returns the runtime robot struct (joints, actuators, etc.)."
  @spec get_robot(module(), maybe_node()) :: term()
  def get_robot(robot, nil), do: Runtime.get_robot(robot)
  def get_robot(robot, node), do: rpc(node, BB.Robot.Runtime, :get_robot, [robot])

  @doc "Returns the latest joint positions known by the runtime."
  @spec positions(module(), maybe_node()) :: %{atom() => float()}
  def positions(robot, nil), do: Runtime.positions(robot)
  def positions(robot, node), do: rpc(node, BB.Robot.Runtime, :positions, [robot])

  @doc "Returns the parameter list (with metadata maps) for the robot."
  @spec list_parameters(module(), keyword(), maybe_node()) :: [{list(), term()}]
  def list_parameters(robot, opts, nil), do: BB.Parameter.list(robot, opts)
  def list_parameters(robot, opts, node), do: rpc(node, BB.Parameter, :list, [robot, opts])

  @doc """
  Returns the list of declared parameter bridges for the robot.

  Each bridge is rendered down to `%{name: atom(), simulation: atom()}` for
  the UI; the underlying `BB.Dsl.Bridge` struct is not exposed so callers
  don't depend on Spark internals. Bridges where `:simulation` is `:omit`
  while the robot is in simulation mode are filtered out (matching
  `bb_liveview`'s discovery rules).

  Returns `[]` when the DSL is unavailable or raises.
  """
  @spec list_bridges(module(), maybe_node()) :: [map()]
  def list_bridges(robot, nil) do
    if Code.ensure_loaded?(Info) and function_exported?(Info, :parameters, 1) do
      sim_mode = local_simulation_mode(robot)

      robot
      |> Info.parameters()
      |> filter_bridges(sim_mode)
    else
      []
    end
  rescue
    _ -> []
  end

  def list_bridges(robot, node) do
    sim_mode = remote_simulation_mode(robot, node)

    case Rpc.call(node, BB.Dsl.Info, :parameters, [robot]) do
      {:badrpc, _} -> []
      result when is_list(result) -> filter_bridges(result, sim_mode)
      _ -> []
    end
  rescue
    _ -> []
  end

  @doc """
  Lists parameters exposed by a remote bridge.

  Returns the bridge's flat parameter list (each entry a map carrying
  `:id`, `:value`, `:type`, optionally `:min`, `:max`, `:doc`). Returns
  `{:error, reason}` when the bridge is unavailable or the call fails.
  """
  @spec list_remote_parameters(module(), atom(), maybe_node()) ::
          {:ok, [map()]} | {:error, term()}
  def list_remote_parameters(robot, bridge_name, nil) do
    BB.Parameter.list_remote(robot, bridge_name)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, reason}
  end

  def list_remote_parameters(robot, bridge_name, node) do
    case Rpc.call(node, BB.Parameter, :list_remote, [robot, bridge_name]) do
      {:badrpc, reason} -> {:error, reason}
      result -> result
    end
  end

  @doc """
  Sets a parameter value on a remote bridge.
  """
  @spec set_remote_parameter(module(), atom(), term(), term(), maybe_node()) ::
          :ok | {:error, term()}
  def set_remote_parameter(robot, bridge_name, param_id, value, nil) do
    BB.Parameter.set_remote(robot, bridge_name, param_id, value)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, reason}
  end

  def set_remote_parameter(robot, bridge_name, param_id, value, node) do
    case Rpc.call(node, BB.Parameter, :set_remote, [robot, bridge_name, param_id, value]) do
      {:badrpc, reason} -> {:error, reason}
      result -> result
    end
  end

  defp local_simulation_mode(robot) do
    Runtime.simulation_mode(robot)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp remote_simulation_mode(robot, node) do
    case Rpc.call(node, BB.Robot.Runtime, :simulation_mode, [robot]) do
      {:badrpc, _} -> nil
      mode when is_atom(mode) -> mode
      _ -> nil
    end
  end

  defp filter_bridges(entities, sim_mode) do
    entities
    |> Enum.filter(&match?(%BB.Dsl.Bridge{}, &1))
    |> Enum.reject(fn bridge ->
      sim_mode != nil and bridge.simulation == :omit
    end)
    |> Enum.map(fn bridge ->
      %{name: bridge.name, simulation: bridge.simulation}
    end)
  end

  @doc """
  Returns the list of declared commands for the robot, normalized for the
  UI. Returns `[]` if the command DSL is not available or raises.

  Each command map has the shape:

      %{
        name: atom(),
        handler: term(),
        timeout: integer() | :infinity,
        allowed_states: [atom()],
        arguments: [%{name: atom(), type: String.t(), required: boolean(),
                      default: term(), doc: String.t() | nil}]
      }

  Argument types are normalized to strings: `"boolean"`, `"integer"`,
  `"float"`, `"atom"`, `"string"`, or `"enum:[a, b, c]"`. Mirrors
  `BB.LiveView.Components.Command` so both UIs see the same shape.
  """
  @spec discover_commands(module(), maybe_node()) :: [map()]
  def discover_commands(robot, nil) do
    if Code.ensure_loaded?(Info) and function_exported?(Info, :commands, 1) do
      robot |> Info.commands() |> normalize_commands()
    else
      []
    end
  rescue
    _ -> []
  end

  def discover_commands(robot, node) do
    case Rpc.call(node, BB.Dsl.Info, :commands, [robot]) do
      {:badrpc, _} -> []
      result when is_list(result) -> normalize_commands(result)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp normalize_commands(commands) do
    commands
    |> Enum.map(&format_command/1)
    |> Enum.sort_by(& &1.name)
  end

  defp format_command(cmd) do
    %{
      name: cmd.name,
      handler: Map.get(cmd, :handler),
      timeout: Map.get(cmd, :timeout, :infinity),
      allowed_states: Map.get(cmd, :allowed_states, []),
      arguments: cmd |> Map.get(:arguments, []) |> Enum.map(&format_argument/1)
    }
  end

  defp format_argument(arg) do
    raw_type = Map.get(arg, :type, :string)

    %{
      name: arg.name,
      type: format_type(raw_type),
      enum_values: enum_values(raw_type),
      required: Map.get(arg, :required, false),
      default: Map.get(arg, :default),
      doc: Map.get(arg, :doc)
    }
  end

  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:in, values}), do: "enum:#{inspect(values)}"
  defp format_type(other), do: inspect(other)

  defp enum_values({:in, values}) when is_list(values), do: values
  defp enum_values(_), do: nil

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
    Runtime.execute(robot, name, args)
  end

  def execute_command(robot, name, args, node) do
    rpc(node, BB.Robot.Runtime, :execute, [robot, name, args])
  end

  # ── Internal ───────────────────────────────────────────────

  defp rpc(node, mod, fun, args) do
    case Rpc.call(node, mod, fun, args) do
      {:badrpc, reason} ->
        raise "BB.TUI.Robot: remote call #{inspect(mod)}.#{fun}/#{length(args)} " <>
                "on #{inspect(node)} failed: #{inspect(reason)}"

      result ->
        result
    end
  end
end
