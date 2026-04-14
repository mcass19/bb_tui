# BB.TUI

> **Proposal** — This package is a proposal and has **not** been reviewed or accepted by the author of [Beam Bots](https://github.com/beam-bots). It is published here for discussion and feedback.

Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots. Built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

## Features

- **Safety controls** — arm / disarm / force disarm with confirmation popup
- **Joint control panel** — position table with type (revolute/prismatic/continuous), units (degrees/mm), visual range bars, target tracking, simulated joint markers, and direct position adjustment via keyboard (1% and 10% steps)
- **Event stream** — scrollable, color-coded event list with formatted timestamps and message summaries; pause/resume, clear, and Enter to open a detail popup showing full payload
- **Commands panel** — lists available robot commands with Ready/Blocked indicators based on runtime state; select and execute directly from the TUI
- **Parameters panel** — live parameter table grouped by path with real-time updates
- **Runtime state monitoring** — safety state and runtime state displayed in the sidebar
- **Status bar** — robot name, safety indicator, runtime state, and key hints
- **Help overlay** — scrollable popup with full keybinding reference
- **Theme system** — consistent color palette with semantic styles (safety colors, focus borders, panel headers)
- **Keyboard-driven navigation** — Tab to cycle panels, vim-style j/k/h/l within panels
- **SSH transport** — serve the dashboard over SSH; multiple operators can connect simultaneously, each with their own isolated session
- **Distribution attach** — run the TUI on the robot node and attach a thin renderer from any connected BEAM node (built on ExRatatui v0.7's `:distributed` transport)
- **Runtime inspection** — snapshot, trace, and inject events into a running TUI via `ExRatatui.Runtime` — useful for debugging SSH sessions you can't otherwise peek into
- **Mix task** — `mix bb.tui --robot MyApp.Robot` for standalone launch
- **Headless test suite** — full coverage using Mimic + ExRatatui test backend, including end-to-end tests that drive a real server with `ExRatatui.Runtime.inject_event/2`

## Layout

```
┌ Safety ────────┬─ Joint Control ──────────────────────────────┐
│ ● ARMED        │ Joint       Type  Position  Target           │
│ Runtime: Idle  │ elbow       rev   -63.8°    ████████░░░░░░   │  60%
│ [a] Arm        │ gripper SIM pri    30.6mm   ███░░░░░░░░░░░   │  height
│ [d] Disarm     │ ...                                          │
├ Commands ──────┤                                              │
│ ▶ home   Ready │                                              │
│   calibrate    │                                              │
├ Events (47) ───┴── Parameters ────────────────────────────────┤
│ 18:23:12 sensor.sim  │ speed              100                 │  40%
│ 18:23:11 state_m...  │ controller.kp      0.5                 │  height
└──────────────────────┴────────────────────────────────────────┘
 Robot | ● Armed | idle | [q]Quit [Tab]Panel [?]Help               1 line
```

## Installation

Add `bb_tui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bb_tui, "~> 0.1"}
  ]
end
```

## Usage

### Mix task (standalone)

```sh
mix bb.tui --robot MyApp.Robot
```

### Programmatic (IEx)

```elixir
BB.TUI.start(MyApp.Robot)
```

### Supervised

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  {BB.TUI, robot: MyApp.Robot}
]
```

### Remote attach (distribution)

When the robot is running on a different BEAM node, you can render the dashboard on the robot terminal, or on your local terminal while pulling all data from the robot node.

**1. Spawn the TUI on the robot node (renders on the robot's terminal):**

```elixir
# On the dev node, after Node.connect/1
:rpc.call(:"robot@192.168.1.42", BB.TUI, :run, [MyApp.Robot])
```

This is the simplest variant — the entire TUI runs on the robot node and binds to whatever stdio that node has.

**2. Spawn the TUI locally and pull data from the robot node (renders local):**

```elixir
# On the dev node, after Node.connect/1
BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")
```

This renders on local terminal but every robot call goes to the remote node. The dev node needs `bb_tui` (and the BB modules it depends
on) loaded so the rendering layer has its types available, but no robot supervision tree is started locally.

The same `--node` flag is available on the mix task:

```sh
iex --name dev@127.0.0.1 --cookie secret -S mix bb.tui \
    --robot MyApp.Robot --node robot@192.168.1.42
```

### Distribution attach (renderer-only local node)

An alternative to the `--node` / `:node` option: run the TUI _on the robot node_ and attach to it from any connected BEAM node. The remote node runs the app callbacks (mount/render/handle_event); your local node only renders the widgets it receives and forwards terminal events back. No robot code required on the local node.

**1. On the robot node**, add the listener to the supervision tree:

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  ExRatatui.Distributed.Listener
]
```

**2. From any connected node**:

```elixir
iex --name dev@127.0.0.1 --cookie secret -S mix
iex> Node.connect(:"robot@192.168.1.42")
iex> ExRatatui.Distributed.attach(:"robot@192.168.1.42", BB.TUI.App)
```

**`:node` option vs `Distributed.attach/3`**

| Concern                       | `:node` option      | `Distributed.attach/3` |
|-------------------------------|---------------------|------------------------|
| Where app callbacks run       | Local node          | Remote node            |
| Where robot code is needed    | Both nodes          | Remote node only       |
| Transport                     | Ad-hoc `:rpc.call`  | Erlang distribution    |
| Reconnect on remote crash     | Manual              | Monitor-driven cleanup |
| Good for                      | Dev/ops workstations that already run `bb_tui` | Thin clients attaching to long-running robots |

Both require Erlang distribution (same cookie, reachable EPMD/ports). See `ExRatatui.Distributed` for the full transport reference.

### SSH transport

When the robot runs on a headless device (Nerves board, container, remote host), serve the dashboard over SSH so any SSH client can connect — no local Elixir node or distribution needed on the client side.

Each SSH client gets its own isolated session with independent panel selection, scroll positions, and event streams. Multiple operators can monitor the same robot simultaneously.

**1. Supervised (production):**

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

**2. Programmatic:**

```elixir
BB.TUI.start_ssh(MyApp.Robot,
  port: 2222,
  auto_host_key: true,
  auth_methods: ~c"password",
  user_passwords: [{~c"admin", ~c"s3cret"}]
)
```

**3. Mix task:**

```sh
# Start SSH daemon with defaults (port 2222, admin/admin)
mix bb.tui --robot MyApp.Robot --ssh

# Custom port
mix bb.tui --robot MyApp.Robot --ssh --port 3333
```

**4. Nerves subsystem (plugging into existing `nerves_ssh`):**

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

> **Why `runtime.exs`?** Mix evaluates compile-time configs before it builds deps for the target, so `ExRatatui.SSH` isn't on the code path yet. `runtime.exs` runs at device boot after all beam files are loaded. The `Application.spec(:nerves_ssh)` guard keeps host builds silent.

See `ExRatatui.SSH.Daemon` for the full list of SSH options (authentication, host keys, idle timeout, max sessions, etc.).

## Keybindings

### Global

| Key   | Action                    |
|-------|---------------------------|
| `q`   | Quit                      |
| `Tab` | Cycle active panel        |
| `?`   | Toggle help overlay       |
| `a`   | Arm robot                 |
| `d`   | Disarm robot              |
| `f`   | Force disarm (error only) |

### Events panel

| Key          | Action              |
|--------------|---------------------|
| `j` / `Down` | Scroll down         |
| `k` / `Up`   | Scroll up           |
| `Enter`      | Show event details  |
| `p`          | Pause / resume      |
| `c`          | Clear events        |

### Commands panel

| Key           | Action         |
|---------------|----------------|
| `j` / `Down`  | Select next    |
| `k` / `Up`    | Select previous|
| `Enter`       | Execute        |

### Joints panel

| Key            | Action                       |
|----------------|------------------------------|
| `j` / `Down`   | Select next joint            |
| `k` / `Up`     | Select previous joint        |
| `l` / `Right`  | Increase position (1% step)  |
| `h` / `Left`   | Decrease position (1% step)  |
| `L`            | Increase position (10% step) |
| `H`            | Decrease position (10% step) |

### Parameters panel

| Key            | Action                                   |
|----------------|------------------------------------------|
| `j` / `Down`   | Select next parameter                    |
| `k` / `Up`     | Select previous parameter                |
| `l` / `Right`  | Increase value (+1 int, +0.1 float)      |
| `h` / `Left`   | Decrease value (-1 int, -0.1 float)      |
| `L`            | Increase value x10                        |
| `H`            | Decrease value x10                        |
| `Enter`        | Toggle boolean parameter                  |

## How It Works

BB stores state in ETS and publishes changes over PubSub. The TUI subscribes to `[:state_machine]`, `[:sensor]`, and `[:param]` paths. `mount/1` takes a one-time ETS snapshot, then `handle_info/2` keeps state fresh via PubSub messages. Keyboard events in `handle_event/2` call BB APIs directly (safety, actuator, command execution). No optimistic updates, the TUI is a faithful reflection of the robot's actual state.

All state transitions live in `BB.TUI.State` as pure functions — no side effects, no process communication — making the dashboard easy to test headlessly.

The SSH transport is built on OTP's `:ssh` module. `ExRatatui.SSH.Daemon` listens on a TCP port and spawns an isolated `ExRatatui.SSH` channel process per client. Each channel owns an in-memory `ExRatatui.Session` (backed by a Rust VTE parser) and a linked server running `BB.TUI.App`. The `mount/render/handle_event/handle_info` callbacks are completely transport-agnostic — the same code path serves both local and SSH sessions.

## Development

The project ships a simulated WidowX-200 robot arm that starts automatically in dev:

```sh
mix deps.get
iex -S mix
```

Then launch the TUI against the simulated robot:

```elixir
BB.TUI.start(Dev.TestRobot)
```

Or via the mix task:

```sh
mix bb.tui --robot Dev.TestRobot
```

### Testing SSH locally

Start the SSH daemon against the simulated robot:

```sh
mix bb.tui --robot Dev.TestRobot --ssh
```

This starts a daemon on port 2222 with auto-generated host keys and default credentials (`admin` / `admin`). Then from another terminal:

```sh
ssh admin@localhost -p 2222
```

To use a custom port:

```sh
mix bb.tui --robot Dev.TestRobot --ssh --port 3333
ssh admin@localhost -p 3333
```

Or from IEx for more control:

```elixir
BB.TUI.start_ssh(Dev.TestRobot,
  port: 2222,
  auto_host_key: true,
  auth_methods: ~c"password",
  user_passwords: [{~c"dev", ~c"dev"}]
)
```

Then connect from another terminal. You can open multiple SSH sessions simultaneously — each gets its own independent dashboard.

> **Tip:** If you see a host key warning on reconnect (after recompiling), remove the old key with `ssh-keygen -R "[localhost]:2222"`.

### Testing distribution locally

The dev application ([`dev/application.ex`](dev/application.ex)) also supervises an `ExRatatui.Distributed.Listener` wired to `BB.TUI.App` with `Dev.TestRobot` as the robot, so no further setup is needed on the "robot" side — just boot two named BEAM nodes sharing a cookie.

**Terminal 1 — robot node (app + listener, no terminal takeover):**

```sh
iex --sname robot --cookie demo -S mix
```

`Dev.Application` starts `BB.Supervisor` with the simulated robot and registers `ExRatatui.Distributed.Listener` under its default name. The shell stays idle.

**Terminal 2 — client node (renders + forwards input):**

```sh
iex --sname dev --cookie demo -S mix
```

```elixir
iex> Node.connect(:"robot@<your-hostname>")
iex> ExRatatui.Distributed.attach(:"robot@<your-hostname>", BB.TUI.App)
```

Terminal 2 takes over with the dashboard while `mount/render/handle_event/handle_info` run on the robot node. Press `q` to disconnect — monitors fire on both sides and the local terminal is restored.

## Runtime inspection

The running `BB.TUI.App` pid (local, SSH, or distributed) exposes debugging hooks via `ExRatatui.Runtime`. Handy for peeking into SSH sessions, asserting against a running TUI from tests, or tracing transitions when a panel misbehaves:

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

## Planned: reducer runtime migration

`BB.TUI.App` currently uses the ExRatatui **callback runtime** (`use ExRatatui.App` with the default `runtime: :callbacks`), which behaves like a GenServer (`mount/1`, `render/2`, `handle_event/2`, `handle_info/2`). ExRatatui v0.7 shipped an Elm-style **reducer runtime** (`use ExRatatui.App, runtime: :reducer`) that is planned as the next step for this dashboard.

**Why migrate?**

- **Side effects become data.** Commands like "execute this robot action and route the result back" become `ExRatatui.Command` values returned from `update/2`. The runtime supervises the async task, handles cancellation, and surfaces results via a unified `{:msg, _}` path — replacing the mount-owned `Task.Supervisor` + hand-rolled `send/2` pattern in `execute_selected_command/1`.
- **Subscriptions replace ad-hoc timers.** The throbber step, command timeouts, and any periodic ETS polling would be declared in a single `subscriptions/1` callback and diffed by the runtime, instead of being scattered across `Process.send_after/3` calls.
- **A single update arrow is easier to reason about and trace.** Pure state transitions already live in [`BB.TUI.State`](lib/bb/tui/state.ex); the reducer migration removes the impedance mismatch between those pure functions and the GenServer-shaped callback module. Combined with `ExRatatui.Runtime.enable_trace/2`, the dashboard becomes introspectable down to every message and command.
- **Cleaner multi-transport story.** The same reducer can be driven by local, SSH, or distributed transports without any per-transport wiring changes — ExRatatui v0.7 already handles that, but the reducer shape keeps our surface area smaller.

References:

- `ExRatatui.App` — both runtime entrypoints
- `ExRatatui.Command` — declarative side effects (message, async, batch, send_after)
- `ExRatatui.Subscription` — interval / once / none declarations
- `ExRatatui.Runtime` — snapshot / trace / inject_event, unchanged across runtimes

The pure `BB.TUI.State` module is already shaped for this — most transitions are `state -> state` or `state -> {state, effect}` today, so the migration is mostly re-routing effects from `BB.TUI.App.handle_event/2` into `update/2` returning `{state, Command.t()}`.

## License

Apache-2.0 — see [LICENSE](LICENSE).
