# BB.TUI

[![Hex.pm](https://img.shields.io/hexpm/v/bb_tui.svg)](https://hex.pm/packages/bb_tui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/bb_tui)
[![CI](https://github.com/mcass19/bb_tui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/bb_tui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/bb_tui.svg)](https://github.com/mcass19/bb_tui/blob/main/LICENSE)

Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots. Built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

![BB.TUI Demo](https://raw.githubusercontent.com/mcass19/bb_tui/main/assets/demo.png)

## Features

- **Safety controls** — arm / disarm / force disarm with confirmation popup
- **Joint control panel** — position table with type (revolute/prismatic/continuous), units (degrees/mm), visual range bars, target tracking, simulated joint markers, and direct position adjustment via keyboard (1% and 10% steps)
- **Event stream** — scrollable, color-coded event list with formatted timestamps and message summaries; pause/resume, clear, and Enter to open a detail popup showing full payload. Surfaces hardware-error detail (`[:safety, :error]`) and estimator output (`[:estimator]`) alongside state, sensor, parameter, and command events
- **Commands panel** — lists available robot commands with Ready/Blocked indicators based on runtime state. Argument-less commands execute on Enter; commands with declared arguments open an inline edit mode (Tab to cycle fields, type-to-edit, Enter to run, Esc to cancel). Argument types — boolean, integer, float, atom, enum (`{:in, [...]}`), string — are parsed before dispatch
- **Parameters panel** — live parameter table grouped by path with real-time updates, plus bridge tabs for editing remote parameters
- **3D visualization tab** — renders the live robot in the terminal from its URDF topology and joint positions, with an orbitable/zoomable camera. Built on `ExRatatui`'s `Viewport3D`: crisp pixel graphics on capable terminals (Ghostty/WezTerm/Kitty) with automatic braille fallback over SSH; the arm reposes in real time as sensor data arrives
- **High-rate-safe** — the event log debounces repeated sensor messages and renders coalesce to ~30fps, so fast telemetry never floods the log or stalls the UI
- **Status bar, help overlay, and theming** — robot name / safety / runtime indicators, a battery / power readout when the robot reports it (colored by remaining charge), a scrollable keybinding reference, and a consistent semantic color palette
- **Keyboard-driven navigation** — `[`/`]` to switch between the Control Panel and Visualization tabs, Tab to cycle panels, number keys to jump, vim-style `j`/`k`/`h`/`l` within panels
- **Three transports** — local terminal, SSH (multiple isolated operator sessions), and Erlang distribution (attach a thin renderer to a TUI running on the robot node)
- **Runtime inspection** — snapshot, trace, and inject events into a running TUI via `ExRatatui.Runtime`
- **Mix task** — `mix bb.tui --robot MyApp.Robot` for standalone launch
- **Headless test suite** — full coverage using Mimic and ExRatatui's test backend

## Layout

```
 🤖 BB.TUI · MyApp.Robot                                                  ← title bar
╭ Safety ────────╮╭ Joint Control ────────────────────────────────────╮
│ ● ARMED        ││ Joint       Type  Position    Target              │
│ Runtime: Idle  ││ elbow       rev   -63.8°      -90 ─────●────── 90 │  60%
│ a  arm         ││ gripper SIM pri    30.6 mm      0 ─────●────── 50 │  height
│ d  disarm      ││ wrist       rev    87.0° !    -90 ──────────◆─ 90 │
├ Commands (2) ──┤│ ...                                               │
│ ▶ home  ● Ready││                                                   │
│   calibrate    ││                                                   │
╰────────────────╯╰───────────────────────────────────────────────────╯
╭ Events (47) ───╮╭ Parameters ───────────────────────────────────────╮
│ 18:23:12 sensor.sim       JointState 2 joint(s)                    ││
│ 18:23:11 state_machine    disarmed → armed                         ││
╰────────────────────────────────────────────────────────────────────╯╯
 MyApp.Robot │ ● ARMED │ idle │ 🔋 78%   Tab panel  ? help  q quit  a arm  d disarm
```

## Installation

Use [Igniter](https://hex.pm/packages/igniter) to add `bb_tui` to a project. The installer imports formatter rules and prints a launch notice tailored to the chosen install shape. If the project already has a `BB` robot module (typically scaffolded by `mix igniter.install bb`):

```sh
mix igniter.install bb_tui
mix igniter.install bb_tui --robot MyApp.Arm
```

The install shape can be tuned with flags:

- `--auto-bb` — scaffold a `BB` robot via `bb.install` when none is present (skips the interactive prompt).
- `--ssh` — append a supervised `{BB.TUI, …}` child wired for an SSH daemon, so the dashboard is reachable as soon as the app boots. Accepts `--port`, `--user`, `--password`. Idempotent; change the generated credentials before deploying.
- `--nerves` — register `BB.TUI.subsystem(<Robot>)` under `config :nerves_ssh, :subsystems` so the dashboard rides on an existing `nerves_ssh` daemon.

Local dashboards are not supervised — a child that claims the terminal on boot would fight an IEx session for stdin/stdout — so the local entry points are `mix bb.tui` and `BB.TUI.run/1`. See `mix help bb_tui.install` for the full option reference, and the [Transports guide](guides/transports.md) for SSH and distribution setups.

To skip Igniter, add the dep directly:

```elixir
def deps do
  [
    {:bb_tui, "~> 0.2"}
  ]
end
```

## Quick Start

Standalone, via the mix task:

```sh
mix bb.tui --robot MyApp.Robot
```

From IEx:

```elixir
BB.TUI.start(MyApp.Robot)
```

Under a supervision tree:

```elixir
children = [
  {BB.Supervisor, MyApp.Robot},
  {BB.TUI, robot: MyApp.Robot}
]
```

Serving the dashboard over SSH or attaching to a robot on another BEAM node is covered in the [Transports guide](guides/transports.md). The full key reference lives in the [Keybindings guide](guides/keybindings.md) (and in the in-app `?` overlay).

## How It Works

BB stores state in ETS and publishes changes over PubSub. The TUI subscribes to the `[:state_machine]`, `[:sensor]`, `[:param]`, `[:actuator]`, `[:command]`, `[:safety]`, and `[:estimator]` paths, takes a one-time ETS snapshot on mount, then keeps state fresh from PubSub messages. Most paths drive dedicated panels; `[:safety, :error]` hardware-error reports and `[:estimator]` output flow into the event log. Keyboard events call BB APIs directly (safety, actuator, command execution) — there are no optimistic updates, so the dashboard is a faithful reflection of the robot's actual state.

All state transitions live in `BB.TUI.State` as pure functions — no side effects, no process communication — which makes the dashboard easy to test headlessly. `BB.TUI.App` wires input and async results to those transitions through ExRatatui's reducer runtime.

Robots can publish sensor data faster than a terminal can usefully redraw, so the event log debounces repeats of the same `{path, payload-type}` within a one-second window, and sensor-driven renders coalesce to at most one frame every ~33ms (~30fps). Key presses, command results, and safety/parameter/state changes still render immediately. Both windows are fields on `BB.TUI.State.Throttle`.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `:bb_tui, :command_timeout` | `30_000` ms | Wait window for `BB.Command.await/2` on commands dispatched from the UI. Compile-time only — downstream apps need `mix deps.compile bb_tui --force` after changing it. |

```elixir
# config/config.exs
config :bb_tui, command_timeout: 30_000
```

## Development

The project ships a simulated WidowX-200 robot arm that starts automatically in dev:

```sh
mix deps.get
mix bb.tui --robot Dev.TestRobot
```

`Dev.TestRobot` exercises every panel feature end-to-end:

- Commands with all argument shapes — `home` (no args), `move` (enum + float), `log` (string + integer), `wobble` (always returns `{:error, :wobble_failed}`), `calibrate` (sleeps ~2s so the throbber is visible), and `stream` (emits a high-rate `JointState` burst to show debounce + render coalescing).
- Telemetry demos — `power` (drains a simulated battery so the status-bar readout shifts green → yellow → red) and `diagnostics` (publishes a `[:safety, :error]` hardware-error report and an `[:estimator]` pose so both surface in the event log).
- Parameter groups covering every primitive type — float, integer, boolean, atom — most with `:min` / `:max` so 1%-of-range stepping applies.
- A `:mavlink` bridge (`Dev.MockBridge`) with a fixed remote-parameter list and in-memory writes — press `t` in the Parameters panel to cycle to the Bridge tab.

Exercising the SSH and Erlang-distribution transports against the simulated robot is covered in the [Transports guide](guides/transports.md#testing-transports-locally).

## Guides

| Guide | Description |
|---|---|
| [Transports](guides/transports.md) | Serve the dashboard over SSH or attach over Erlang distribution, inspect a running session, and test both locally |
| [Keybindings](guides/keybindings.md) | Full per-panel key reference, including command argument editing and parameter stepping |
| [Telemetry](guides/telemetry.md) | `:telemetry` events for mount, input, dispatch, and frames — logging and `Telemetry.Metrics` |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

BB.TUI is built on [ExRatatui](https://github.com/mcass19/ex_ratatui) - a general-purpose terminal UI library for Elixir, and [Beam Bots](https://github.com/beam-bots) - robotics framework. Contributions to underlying libraries are very welcome too.

## License

Apache-2.0 — see [LICENSE](https://github.com/mcass19/bb_tui/blob/main/LICENSE).
