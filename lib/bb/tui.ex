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

  ## Remote attach (distribution)

  When the robot is running on a different BEAM node — for example a
  Nerves device on the network — pass the `:node` option so the TUI
  renders on the local terminal but pulls all data and dispatches all
  commands across distribution:

      # On the dev node, after Node.connect/1 with the robot node
      BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")

  See `BB.TUI.Robot` for the routing layer that backs this option.

  ## SSH transport

  When the robot runs on a headless device (Nerves board, container, remote
  host), you can serve the dashboard over SSH so any SSH client can connect
  without a local Elixir node or distribution setup on the client side:

      # In the robot's supervision tree
      children = [
        {BB.Supervisor, MyApp.Robot},
        {BB.TUI, robot: MyApp.Robot, transport: :ssh, port: 2222,
         auto_host_key: true, auth_methods: ~c"password",
         user_passwords: [{~c"admin", ~c"s3cret"}]}
      ]

  Then from any machine:

      ssh admin@robot.local -p 2222

  Each SSH client gets its own isolated session with independent panel
  selection, scroll positions, and event streams. Multiple operators can
  monitor the same robot simultaneously.

  For Nerves devices already running `nerves_ssh`, plug into the existing
  daemon as a subsystem instead — see `subsystem/1`.

  See `ExRatatui.SSH.Daemon` for the full list of SSH options.

  ## Distributed transport (attach from a connected node)

  As an alternative to the `:node` option — which keeps mount/render local
  and routes data calls through `:rpc` — you can run the TUI app _on the
  robot node_ and attach to it from any connected BEAM node. This is the
  `ExRatatui.Distributed` transport: the remote node runs the app
  (mount/render/handle_event), and your local node only renders the
  widgets it receives and forwards terminal events back.

  **1. On the robot node**, add the Distributed listener to its
  supervision tree (in addition to whatever app you normally supervise):

      children = [
        {BB.Supervisor, MyApp.Robot},
        ExRatatui.Distributed.Listener
      ]

  **2. From any connected node**, attach:

      iex --name dev@127.0.0.1 --cookie secret -S mix
      iex> Node.connect(:"robot@192.168.1.42")
      iex> ExRatatui.Distributed.attach(:"robot@192.168.1.42", BB.TUI.App,
      ...>   listener: ExRatatui.Distributed.Listener)

  For local experimentation, `Dev.Application` already supervises a
  matching `ExRatatui.Distributed.Listener` wired to `Dev.TestRobot`,
  so two named shells sharing a cookie are enough to exercise the
  full round-trip — see the README's "Testing distribution locally"
  section.

  **`:node` option vs `Distributed.attach/3` — which do I want?**

  | Concern                       | `:node` option      | `Distributed.attach/3` |
  |-------------------------------|---------------------|------------------------|
  | Where app callbacks run       | Local (this) node   | Remote node            |
  | Where robot code is needed    | Both nodes          | Remote node only       |
  | Transport                     | Ad-hoc `:rpc.call`  | Erlang distribution    |
  | Reconnect on remote crash     | Manual              | Monitor-driven cleanup |
  | Good for                      | Dev/ops workstations already running BB.TUI | Thin clients attaching to long-running robots |

  Both require Erlang distribution (same cookie, reachable EPMD/ports).

  ## Runtime inspection and tracing

  The supervising runtime exposes a few debugging hooks — handy when
  something goes wrong inside an SSH session you can't easily peek into:

      # Quick headless-or-not check plus dimensions, render count, etc.
      ExRatatui.Runtime.snapshot(pid)

      # Capture the last N state transitions in memory.
      ExRatatui.Runtime.enable_trace(pid, limit: 200)
      ExRatatui.Runtime.trace_events(pid)
      ExRatatui.Runtime.disable_trace(pid)

      # Deterministically drive input in tests (see test/bb/tui/integration_test.exs)
      ExRatatui.Runtime.inject_event(pid, %ExRatatui.Event.Key{code: "tab", kind: "press"})

  See `ExRatatui.Runtime` for the full API.

  ## Reducer runtime

  `BB.TUI.App` is built on the ExRatatui **reducer runtime**
  (`use ExRatatui.App, runtime: :reducer`). Every keyboard event,
  PubSub message, async result, and subscription tick flows through
  a single `update/2` arrow; pure state transitions live in
  `BB.TUI.State`.

    * `init/1` — validates the robot, subscribes to PubSub, snapshots
      ETS state.
    * `update({:event, ev}, state)` — terminal input.
    * `update({:info, msg}, state)` — PubSub, async results,
      `send_after` deliveries, subscription ticks.
    * `subscriptions/1` — declares the 100ms throbber tick whenever
      the dashboard has something animating; the runtime diffs the
      result so the timer only runs when needed.

  Long-running command execution is owned by the runtime via
  `ExRatatui.Command.async/2`, batched with `Command.send_after/2`
  for the timeout. Both reach the reducer as `{:info, _}` messages.
  Fast, fire-and-forget robot calls (arm / disarm / set_actuator /
  set_parameter / publish) are invoked inline from `update/2`.

  See the README for the full rationale and the cross-references to
  `ExRatatui.Command`, `ExRatatui.Subscription`, and
  `ExRatatui.Runtime`.
  """

  alias BB.TUI.App

  @doc """
  Returns a child specification for supervision trees.

  Accepts all options supported by `start/2` and `start_ssh/2`. When
  `transport: :ssh` is present, the spec starts an SSH daemon instead
  of a local terminal.

  ## Examples

      iex> %{id: BB.TUI, start: {BB.TUI, :start, _}} = BB.TUI.child_spec(robot: MyApp.Robot)

      iex> spec = BB.TUI.child_spec(robot: MyApp.Robot, transport: :ssh, port: 2222)
      iex> spec.id
      BB.TUI

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

  Use this from IEx or scripts. For local transport, the terminal is
  taken over for the duration and restored when the TUI exits (press
  `q` to quit). For SSH transport, the daemon runs until the process
  is stopped.

  ## Options

    * `:node` — connected remote node atom. When set, all robot data is
      fetched from that node via `:rpc.call/4` and PubSub messages are
      relayed back to the local TUI. The dev node must be connected to
      the remote node first via `Node.connect/1`.
    * `:transport` — `:local` (default) for the OS terminal, or `:ssh`
      to start an SSH daemon. When `:ssh`, all `ExRatatui.SSH.Daemon`
      options (`:port`, `:system_dir`, etc.) are accepted.
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

  When `transport: :ssh` is set in `opts`, starts an SSH daemon that
  serves the dashboard to connecting SSH clients. Otherwise starts a
  local terminal session.

  Use `run/2` for interactive use from IEx. Use `start/2` or the
  child spec when adding to a supervision tree.

  ## Options

    * `:node` — connected remote node atom (see `run/2`).
    * `:transport` — `:local` (default) or `:ssh`. When `:ssh`, all
      `ExRatatui.SSH.Daemon` options are accepted (`:port`,
      `:system_dir`, `:auto_host_key`, etc.).
    * `:test_mode` — `{width, height}` tuple for headless testing
      (optional).

  ## Examples

      # Local terminal
      BB.TUI.start(MyApp.Robot)

      # SSH daemon on port 2222
      BB.TUI.start(MyApp.Robot, transport: :ssh, port: 2222, auto_host_key: true)

  """
  @spec start(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(robot, opts \\ []) when is_atom(robot) do
    case Keyword.get(opts, :transport) do
      :ssh ->
        opts
        |> wrap_app_opts(robot)
        |> App.start_link()

      _ ->
        App.start_link(Keyword.put(opts, :robot, robot))
    end
  end

  @doc """
  Starts the TUI dashboard as an SSH daemon.

  Convenience wrapper around `start/2` that sets `transport: :ssh`
  automatically. Each connecting SSH client gets its own isolated
  dashboard session.

  ## Options

  Accepts all `ExRatatui.SSH.Daemon` options:

    * `:port` — TCP port to listen on (default `2222`).
    * `:auto_host_key` — auto-generate an RSA host key on first boot
      (default `false`).
    * `:system_dir` — host key directory (alternative to
      `:auto_host_key`).
    * `:auth_methods` — e.g. `~c"password"` or `~c"publickey"`.
    * `:user_passwords` — `[{~c"user", ~c"pass"}]` pairs.
    * `:node` — remote BEAM node atom, forwarded to each client's
      `mount/1`.

  All other OTP `:ssh.daemon/2` options are forwarded as-is.

  ## Examples

      # Auto-generated host key, password auth
      BB.TUI.start_ssh(MyApp.Robot,
        port: 2222,
        auto_host_key: true,
        auth_methods: ~c"password",
        user_passwords: [{~c"admin", ~c"s3cret"}]
      )

      # In a supervision tree
      children = [
        {BB.Supervisor, MyApp.Robot},
        %{
          id: BB.TUI.SSH,
          start: {BB.TUI, :start_ssh, [MyApp.Robot, [port: 2222, auto_host_key: true]]}
        }
      ]

  """
  @spec start_ssh(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_ssh(robot, opts \\ []) when is_atom(robot) do
    opts
    |> Keyword.put(:transport, :ssh)
    |> wrap_app_opts(robot)
    |> App.start_link()
  end

  @doc """
  Returns a subsystem tuple for plugging into an existing SSH daemon.

  Use this when the robot already runs `nerves_ssh` (or any OTP
  `:ssh.daemon/2`) and you want to add the dashboard as an SSH
  subsystem instead of spinning up a separate daemon.

  ## Nerves example

      # config/runtime.exs
      import Config

      if Application.spec(:nerves_ssh) do
        config :nerves_ssh,
          subsystems: [
            :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
            BB.TUI.subsystem(MyApp.Robot)
          ]
      end

  Then connect with:

      ssh -t nerves.local -s Elixir.BB.TUI.App

  The `-t` flag is required — it forces PTY allocation, which the TUI
  needs for interactive input.

  ## Examples

      iex> {name, {mod, args}} = BB.TUI.subsystem(SomeRobot)
      iex> name
      ~c"Elixir.BB.TUI.App"
      iex> mod
      ExRatatui.SSH
      iex> Keyword.fetch!(args, :subsystem)
      true

  """
  @spec subsystem(module()) :: {charlist(), {module(), keyword()}}
  def subsystem(robot) when is_atom(robot) do
    {name, {mod, args}} = ExRatatui.SSH.subsystem(BB.TUI.App)
    args = Keyword.update(args, :app_opts, [robot: robot], &Keyword.put(&1, :robot, robot))
    {name, {mod, args}}
  end

  # Moves :robot and :node into :app_opts so they reach each SSH
  # client's mount/1 via the daemon. The daemon passes :app_opts to
  # every spawned channel's Server, which forwards them to mount/1.
  defp wrap_app_opts(opts, robot) do
    {node, opts} = Keyword.pop(opts, :node)

    app_opts =
      Keyword.get(opts, :app_opts, [])
      |> Keyword.put(:robot, robot)
      |> then(fn ao -> if node, do: Keyword.put(ao, :node, node), else: ao end)

    Keyword.put(opts, :app_opts, app_opts)
  end
end
