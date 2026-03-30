# BB.TUI

[![Hex.pm](https://img.shields.io/hexpm/v/bb_tui.svg)](https://hex.pm/packages/bb_tui)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/bb_tui)
[![CI](https://github.com/beam-bots/bb_tui/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_tui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/bb_tui.svg)](https://github.com/beam-bots/bb_tui/blob/main/LICENSE)

Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots. Built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

Provides equivalent core functionality to `bb_liveview` — safety controls, joint display, event stream, command execution — while operating entirely within terminal environments: over SSH, on headless systems, or in low-bandwidth scenarios.

## Features

- Safety controls (arm / disarm / force disarm)
- Real-time joint position table
- Scrollable event stream
- Available commands display
- Runtime state monitoring
- Keyboard-driven panel navigation
- Help overlay with keybinding reference
- Force disarm confirmation popup
- Mix task for standalone launch
- Headless test suite with Mimic + ExRatatui test backend

## Layout

```
┌─────────────────────────────────────────────────────────┐
│ Safety (20%)     │ Runtime (20%)    │ Joints (60%)      │  40% height
├─────────────────────────────────────────────────────────┤
│ Events (50%)                  │ Commands (50%)          │  remaining
├─────────────────────────────────────────────────────────┤
│ Status Bar                                              │  1 line
└─────────────────────────────────────────────────────────┘
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

### Panel-scoped

| Key        | Panel    | Action         |
|------------|----------|----------------|
| `j` / `k`  | Events   | Scroll down/up |
| Arrow keys | Commands | Select command |
| `Enter`    | Commands | Execute        |

## How It Works

BB stores state in ETS and publishes changes over PubSub. The TUI subscribes to `[:state_machine]`, `[:sensor]`, and `[:param]` paths. `mount/1` takes a one-time ETS snapshot, then `handle_info/2` keeps state fresh via PubSub messages. Keyboard events in `handle_event/2` call BB APIs directly. No optimistic updates — the TUI is a faithful reflection of the robot's actual state.

## License

Apache-2.0 — see [LICENSE](LICENSE).
