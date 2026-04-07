defmodule BB.TUI do
  @moduledoc """
  Terminal-based dashboard for Beam Bots robots.

  BB.TUI provides a TUI interface for monitoring and controlling BB robots —
  safety controls, runtime state, joint positions, event stream, and command
  display — in terminal environments.

  ## Usage

      # Interactive — from IEx when robot is already running
      BB.TUI.run(MyApp.Robot)

      # Supervised — add to your app's supervision tree
      children = [
        {BB.Supervisor, MyApp.Robot},
        {BB.TUI, robot: MyApp.Robot}
      ]

      # Mix task — standalone
      $ mix bb.tui --robot MyApp.Robot

  ## Remote attach

  When the robot is running on a different BEAM node — for example a
  Nerves device on the network — pass the `:node` option so the TUI
  renders on the local terminal but pulls all data and dispatches all
  commands across distribution:

      # On the dev node, after Node.connect/1 with the robot node
      BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")

  See `BB.TUI.Robot` for the routing layer that backs this option.
  """

  @doc """
  Returns a child specification for supervision trees.

  ## Examples

      iex> %{id: BB.TUI, start: {BB.TUI, :start, _}} = BB.TUI.child_spec(robot: MyApp.Robot)

  """
  def child_spec(opts) when is_list(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, [opts[:robot], Keyword.delete(opts, :robot)]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc """
  Runs the TUI dashboard interactively, blocking until the user quits.

  Use this from IEx or scripts. The terminal is taken over for the
  duration and restored when the TUI exits (press `q` to quit).

  ## Options

    * `:node` — connected remote node atom. When set, all robot data is
      fetched from that node via `:rpc.call/4` and PubSub messages are
      relayed back to the local TUI. The dev node must be connected to
      the remote node first via `Node.connect/1`.
    * `:test_mode` — `{width, height}` tuple for headless testing
      (optional).

  ## Examples

      # Local
      BB.TUI.run(MyApp.Robot)

      # Remote — render here, data from there
      Node.connect(:"robot@192.168.1.42")
      BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")

  """
  @spec run(module(), keyword()) :: :ok | {:error, term()}
  def run(robot, opts \\ []) when is_atom(robot) do
    case start(robot, opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Starts the TUI dashboard as a linked process.

  Use `run/2` for interactive use from IEx. Use `start/2` or the
  child spec when adding to a supervision tree.

  ## Options

    * `:node` — connected remote node atom (see `run/2`).
    * `:test_mode` — `{width, height}` tuple for headless testing
      (optional).

  """
  @spec start(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(robot, opts \\ []) when is_atom(robot) do
    BB.TUI.App.start_link(Keyword.put(opts, :robot, robot))
  end
end
