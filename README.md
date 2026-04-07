# BB.TUI

> **Proposal** — This package is a proposal and has **not** been reviewed or accepted by the author of [Beam Bots](https://github.com/beam-bots). It is published here for discussion and feedback.

Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots. Built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

Provides a full-featured dashboard — safety controls, joint control with direct position adjustment, real-time event stream, command execution, parameter monitoring, and a consistent theme — within terminal environments: over SSH, on headless systems, or in low-bandwidth scenarios.

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
- **Mix task** — `mix bb.tui --robot MyApp.Robot` for standalone launch
- **Headless test suite** — full coverage using Mimic + ExRatatui test backend

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

When the robot is running on a different BEAM node — e.g. a Nerves
device on the network — you can render the dashboard on your local dev
terminal while pulling all data from the robot node. The TUI process,
keyboard input, and rendering live locally; every BB call is routed
across distribution via `:rpc.call/4`, and PubSub messages are relayed
back through a small process spawned on the remote node.

There are two equivalent entry points.

**1. Spawn the TUI on the robot node (renders on the robot's terminal):**

```elixir
# On the dev node, after Node.connect/1
:rpc.call(:"robot@192.168.1.42", BB.TUI, :run, [MyApp.Robot])
```

This is the simplest variant — the entire TUI runs on the robot node
and binds to whatever stdio that node has. Useful when you SSH into the
device.

**2. Spawn the TUI locally and pull data from the robot node (renders here):**

```elixir
# On the dev node, after Node.connect/1
BB.TUI.run(MyApp.Robot, node: :"robot@192.168.1.42")
```

This renders on your local terminal but every robot call goes to the
remote node. The dev node needs `bb_tui` (and the BB modules it depends
on) loaded so the rendering layer has its types available, but no robot
supervision tree is started locally.

The same `--node` flag is available on the mix task:

```sh
iex --name dev@127.0.0.1 --cookie secret -S mix bb.tui \
    --robot MyApp.Robot --node robot@192.168.1.42
```

These two approaches are the **first starting point** for distributing
the dashboard. A proper SSH transport — where ExRatatui itself binds
crossterm to an SSH channel instead of local stdio — is being explored
in [ex_ratatui#33](https://github.com/mcass19/ex_ratatui/issues/33) and
will eventually replace the relay-based path for production use on
Nerves devices.

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

BB stores state in ETS and publishes changes over PubSub. The TUI subscribes to `[:state_machine]`, `[:sensor]`, and `[:param]` paths. `mount/1` takes a one-time ETS snapshot, then `handle_info/2` keeps state fresh via PubSub messages. Keyboard events in `handle_event/2` call BB APIs directly (safety, actuator, command execution). No optimistic updates — the TUI is a faithful reflection of the robot's actual state.

All state transitions live in `BB.TUI.State` as pure functions — no side effects, no process communication — making the dashboard easy to test headlessly.

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

## License

Apache-2.0 — see [LICENSE](LICENSE).
