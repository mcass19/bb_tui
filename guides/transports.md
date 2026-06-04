# Transports

`BB.TUI.App`'s `mount` / `render` / `handle_event` / `handle_info` callbacks are transport-agnostic — the same dashboard code serves a local terminal, an SSH client, or a thin renderer attached over Erlang distribution. This guide covers the remote transports and how to drive each one locally.

## Local

The default transport renders to the terminal that launched the dashboard. Start it with the mix task, from IEx, or as a supervised child:

```sh
mix bb.tui --robot MyApp.Robot
```

```elixir
BB.TUI.start(MyApp.Robot)
```

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  {BB.TUI, robot: MyApp.Robot}
]
```

## SSH

When the robot runs on a headless device (Nerves board, container, remote host), serve the dashboard over SSH so any SSH client can connect — no local Elixir node or distribution needed on the client side. Each SSH client gets its own isolated session with independent panel selection, scroll positions, and event streams, so multiple operators can monitor the same robot at once.

### Supervised (production)

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  {BB.TUI, robot: MyApp.Robot, transport: :ssh, port: 2222,
   auto_host_key: true, auth_methods: ~c"password",
   user_passwords: [{~c"admin", ~c"s3cret"}]}
]
```

Then from any machine with an SSH client:

```sh
ssh admin@robot.local -p 2222
```

### Programmatic

```elixir
BB.TUI.start_ssh(MyApp.Robot,
  port: 2222,
  auto_host_key: true,
  auth_methods: ~c"password",
  user_passwords: [{~c"admin", ~c"s3cret"}]
)
```

### Mix task

```sh
# Defaults: port 2222, admin/admin
mix bb.tui --robot MyApp.Robot --ssh

# Custom port
mix bb.tui --robot MyApp.Robot --ssh --port 3333
```

### Nerves subsystem

If the device already runs `nerves_ssh`, plug into its daemon instead of starting a second one:

```elixir
# config/runtime.exs
import Config

if Application.spec(:nerves_ssh) do
  config :nerves_ssh,
    subsystems: [
      :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
      BB.TUI.subsystem(MyApp.Robot)
    ]
end
```

Then connect with:

```sh
ssh -t nerves.local -s Elixir.BB.TUI.App
```

The `-t` flag is required — it forces PTY allocation, which the TUI needs for interactive input.

`runtime.exs` is the right home for this: Mix evaluates compile-time configs before it builds deps for the target, so `ExRatatui.SSH` isn't on the code path yet, whereas `runtime.exs` runs at device boot after all beam files are loaded. The `Application.spec(:nerves_ssh)` guard keeps host builds silent.

Under the hood, `ExRatatui.SSH.Daemon` listens on a TCP port and spawns an isolated `ExRatatui.SSH` channel process per client; each channel owns an in-memory `ExRatatui.Session` (backed by a Rust VTE parser) and a linked server running `BB.TUI.App`. See `ExRatatui.SSH.Daemon` for the full list of SSH options (authentication, host keys, idle timeout, max sessions).

## Erlang distribution

When the robot runs on a different BEAM node, the dashboard can render on the robot's terminal, on a local terminal that pulls all data from the robot node, or as a thin renderer attached to a TUI already running on the robot node.

### Remote attach via `:node`

Spawn the TUI on the robot node so it renders on the robot's terminal:

```elixir
# On the dev node, after Node.connect/1
:rpc.call(:"robot@192.168.1.42", BB.TUI, :run, [MyApp.Robot])
```

This is the simplest variant — the entire TUI runs on the robot node and binds to whatever stdio that node has.

Or spawn the TUI locally and pull data from the robot node, so it renders on the local terminal while every robot call goes to the remote node:

```elixir
# On the dev node, after Node.connect/1
BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")
```

The dev node needs `bb_tui` (and the BB modules it depends on) loaded so the rendering layer has its types available, but no robot supervision tree is started locally. The same `--node` flag is available on the mix task:

```sh
iex --name dev@127.0.0.1 --cookie secret -S mix bb.tui \
    --robot MyApp.Robot --node robot@192.168.1.42
```

### Renderer-only attach via `Distributed.attach/3`

Run the TUI _on the robot node_ and attach to it from any connected BEAM node. The remote node runs the app callbacks (`mount` / `render` / `handle_event`); the local node only renders the widgets it receives and forwards terminal events back. No robot code is required on the local node.

On the robot node, add the listener to the supervision tree:

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  ExRatatui.Distributed.Listener
]
```

From any connected node:

```elixir
iex --name dev@127.0.0.1 --cookie secret -S mix
iex> Node.connect(:"robot@192.168.1.42")
iex> ExRatatui.Distributed.attach(:"robot@192.168.1.42", BB.TUI.App)
```

### Choosing between them

| Concern | `:node` option | `Distributed.attach/3` |
|---|---|---|
| Where app callbacks run | Local node | Remote node |
| Where robot code is needed | Both nodes | Remote node only |
| Transport | Ad-hoc `:rpc.call` | Erlang distribution |
| Reconnect on remote crash | Manual | Monitor-driven cleanup |
| Good for | Dev/ops workstations that already run `bb_tui` | Thin clients attaching to long-running robots |

Both require Erlang distribution (same cookie, reachable EPMD/ports). See `ExRatatui.Distributed` for the full transport reference.

## Inspecting a running session

The running `BB.TUI.App` pid (local, SSH, or distributed) exposes debugging hooks via `ExRatatui.Runtime` — handy for peeking into SSH sessions that aren't otherwise observable, asserting against a running TUI from tests, or tracing transitions when a panel misbehaves:

```elixir
# Headless-or-not check plus dimensions, render count, subscriptions, etc.
ExRatatui.Runtime.snapshot(pid)

# Record the last N state transitions in memory — each event / info message,
# render, command dispatch, and subscription firing gets a trace record.
ExRatatui.Runtime.enable_trace(pid, limit: 200)
ExRatatui.Runtime.trace_events(pid)
ExRatatui.Runtime.disable_trace(pid)

# Deterministically drive input — works under test_mode where live polling
# is disabled. See test/bb/tui/integration_test.exs for end-to-end examples.
ExRatatui.Runtime.inject_event(pid, %ExRatatui.Event.Key{code: "tab", kind: "press"})
```

## Testing transports locally

The dev application ships a simulated robot, so both remote transports can be exercised without hardware.

### SSH

Start the SSH daemon against the simulated robot:

```sh
mix bb.tui --robot Dev.TestRobot --ssh
```

This starts a daemon on port 2222 with auto-generated host keys and default credentials (`admin` / `admin`). Then from another terminal:

```sh
ssh admin@localhost -p 2222
```

Multiple SSH sessions can run simultaneously — each gets its own independent dashboard. A host key warning on reconnect (after recompiling) clears with `ssh-keygen -R "[localhost]:2222"`.

### Erlang distribution

The dev application (`dev/application.ex`) also supervises an `ExRatatui.Distributed.Listener` wired to `BB.TUI.App` with `Dev.TestRobot`, so no further setup is needed on the "robot" side — just boot two named BEAM nodes sharing a cookie.

Terminal 1 — robot node (app + listener, no terminal takeover):

```sh
iex --sname robot --cookie demo -S mix
```

Terminal 2 — client node (renders + forwards input):

```sh
iex --sname dev --cookie demo -S mix
```

```elixir
iex> Node.connect(:"robot@<your-hostname>")
iex> ExRatatui.Distributed.attach(:"robot@<your-hostname>", BB.TUI.App)
```

Terminal 2 takes over with the dashboard while the app callbacks run on the robot node. Press `q` to disconnect — monitors fire on both sides and the local terminal is restored.
