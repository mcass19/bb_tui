<!--
SPDX-FileCopyrightText: 2026 Mauricio Cassola

SPDX-License-Identifier: Apache-2.0
-->

# BB.TUI Usage Rules

`bb_tui` provides `BB.TUI.run/2` and friends — a terminal dashboard for a
running [Beam Bots](https://hexdocs.pm/bb) robot, with live joint state, a 3D
model, command execution, a PubSub event stream, and arm/disarm safety
controls. It is the terminal counterpart to
[`bb_liveview`](https://hexdocs.pm/bb_liveview).

For BB framework basics see `bb`'s rules (`mix usage_rules.sync <file> bb:all`);
for the rendering layer see `ex_ratatui`'s
(`mix usage_rules.sync <file> ex_ratatui:all`). This file covers only how to
start and extend the dashboard.

## Core principles

1. **The dashboard is an entry point, not a DSL component.** It is *not* a
   `BB.Sensor`/`BB.Actuator`/`BB.Controller` and it does *not* belong in the
   robot's `topology`. Start it from IEx, a mix task, a supervision tree, an
   SSH daemon, or a Phoenix router.
2. **It observes a robot that is already running.** On start it subscribes to
   the robot's PubSub and reads live state over the local node or `:rpc`. The
   robot's supervision tree must be started separately — the dashboard neither
   starts nor supervises the robot.
3. **Pick the entry point by lifecycle, not by transport.** `run/2` blocks and
   owns the terminal until `q`; `start/2` returns a supervised pid; `start_ssh/2`
   runs a daemon; `subsystem/1` registers under `nerves_ssh`; `use BB.TUI.Live`
   defines a LiveView the router mounts per browser tab. Reaching for `run/2`
   inside a supervision tree is the usual mistake.
4. **Rendering is a pure projection of state.** Panels read `BB.TUI.State` and
   return widgets; every transition lives in `BB.TUI.State` and every effect is
   dispatched from `BB.TUI.App.update/2`. Extensions should follow the same
   split rather than reaching for the runtime directly.
5. **Multi-DoF joints are display-only.** Planar and floating joints (bb 0.27+)
   render as read-only rows — a compact pose in the joints panel, `(x, y, θ°)`
   in event details — and target-adjust keys skip them. This is by design:
   `BB.Actuator.set_position/4` takes a single number, so there is no command
   path for a transform target. The 3D view poses them correctly via
   `BB.Robot.Kinematics`.

## Starting it

Local terminal, blocking — the common case from IEx or `mix bb.tui`:

```elixir
BB.TUI.run(MyApp.Robot)
```

Supervised, for an app that should serve the dashboard for its lifetime:

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  {BB.TUI, robot: MyApp.Robot, transport: :ssh, port: 2222, auto_host_key: true}
]
```

Attached to a robot on another node — rendering happens locally, data comes from
there. The nodes must already be connected:

```elixir
Node.connect(:"robot@192.168.1.42")
BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")
```

On Nerves, plug into the existing `nerves_ssh` daemon rather than starting a
second one:

```elixir
# config/runtime.exs
config :nerves_ssh,
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    BB.TUI.subsystem(MyApp.Robot)
  ]
```

In the browser, as a Phoenix LiveView — requires the optional
`{:phoenix_ex_ratatui, "~> 0.2"}` dependency (without it `BB.TUI.Live` is not
compiled), plus its JS hook registered once in `app.js`:

```elixir
defmodule MyAppWeb.RobotLive do
  use BB.TUI.Live, robot: MyApp.Robot
end

# router.ex
live "/robot", MyAppWeb.RobotLive
```

The `use` options are the same mount keyword list as the other entry points;
override `tui_mount_opts/1` to derive them per session from the socket. Each
browser tab is an isolated dashboard session over the shared robot, like
concurrent SSH clients.

The igniter installer wires up the mix task and dev entry points:

```bash
mix igniter.install bb_tui --robot MyApp.Robot
```

## Options

`run/2`, `start/2` and `start_ssh/2` share the same keyword list. `use BB.TUI.Live`
(and an overridden `tui_mount_opts/1`) takes the same list minus `:transport` and
`:test_mode`, which the LiveView transport owns.

| Option | Default | Meaning |
|---|---|---|
| `:robot` | — | The robot module. Must `use BB` (passed positionally to `run/2`) |
| `:transport` | `:local` | `:local` for the OS terminal, `:ssh` for a daemon. `:ssh` also accepts every `ExRatatui.SSH.Daemon` option |
| `:node` | `nil` | Connected remote node. All robot data is fetched from it via `:rpc.call/4` and PubSub is relayed back |
| `:subscribe_paths` | control-plane set | PubSub paths to subscribe to. Narrow it (`[[:state_machine], [:command]]`) to avoid a high-rate sensor firehose |
| `:renderers` | `%{}` | `%{path_prefix => module}` map of `BB.TUI.Renderer` implementations |
| `:test_mode` | `nil` | `{width, height}` for headless testing |

## Rendering custom payloads

The dashboard summarises the message types it knows. For a payload on a path the
consumer owns, register a `BB.TUI.Renderer` instead of teaching bb_tui about the
struct — messages route by longest-matching prefix, like a routing table:

```elixir
defmodule MyApp.GripperRenderer do
  @behaviour BB.TUI.Renderer

  @impl true
  def summarize([:sensor, :gripper], %{force_n: n}), do: "gripper #{n} N"
  def summarize(_path, _payload), do: nil

  @impl true
  def observed([:sensor, :gripper], %{force_n: n}), do: {"grip", "#{n} N"}
  def observed(_path, _payload), do: nil
end

BB.TUI.run(MyApp.Robot, renderers: %{[:sensor, :gripper] => MyApp.GripperRenderer})
```

`summarize/2` returns the event-log line, or `nil` to fall back to the generic
`inspect/2`. `observed/2` is optional and feeds an at-a-glance status-bar slot.

## Running commands

Commands are awaited with `:infinity`, so a continuous command — one that only
returns when it stops or is cancelled — is never reported as timed out while it
is still running. Runaways stay bounded by the command's own DSL `timeout`.
Press `c` in the commands panel to cancel the running command.

## Anti-patterns

- **Don't declare the dashboard in `topology`.** There is no component to
  supervise — it is an entry point driven purely by the robot's PubSub.
- **Don't call `run/2` from a supervision tree.** It blocks and takes over the
  terminal. Use `start/2`, which returns `{:ok, pid}`.
- **Don't start it against a robot that isn't running.** The module must `use BB`
  *and* have its supervision tree started; otherwise the dashboard renders but
  shows no live state and controls do nothing.
- **Don't set `:node` without connecting first.** `Node.connect/1` must succeed
  before the remote node is usable, or every `:rpc` call fails.
- **Don't subscribe to the full firehose when only control-plane traffic
  matters.** The event log debounces and renders are coalesced, but
  `:subscribe_paths` avoids the traffic altogether.
- **Don't reach into the runtime from a panel.** Panels project state to
  widgets; effects belong in `BB.TUI.App.update/2` and transitions in
  `BB.TUI.State`.

## Further reading

- [bb_tui docs](https://hexdocs.pm/bb_tui) — including the
  [Transports](https://hexdocs.pm/bb_tui/transports.html) and
  [Keybindings](https://hexdocs.pm/bb_tui/keybindings.html) guides
- `bb`'s rules (`mix usage_rules.sync <file> bb:all`) and the
  [bb docs](https://hexdocs.pm/bb)
- `ex_ratatui`'s rules (`mix usage_rules.sync <file> ex_ratatui:all`) for the
  reducer runtime and widget layer
