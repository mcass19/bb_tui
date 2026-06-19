# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-19

### Added

- **3D visualization tab.** A new top-level tab (`[` / `]` to switch) renders the live robot in the terminal in 3D, built from its URDF topology and joint positions via forward kinematics. The camera orbits, tilts, zooms, and resets (`←`/`→`/`h`/`l`, `↑`/`↓`/`k`/`j`, `+`/`-`, `r`), and the arm reposes in real time as sensor data arrives. Built on `ExRatatui`'s `Viewport3D` and `ThreeD.Node` scene-graph.
- **Battery / power readout in the status bar.** When the robot publishes `BB.Message.Sensor.BatteryState` or `BB.Message.Sensor.PowerState`, the status bar shows an at-a-glance segment — charge percentage (colored green / yellow / red by remaining charge, with a bolt while charging), falling back to bus voltage when percentage is unmeasured. Latest-reading-wins; the event log keeps the history. Especially useful when driving a headless robot over SSH.
- **Hardware-error and estimator events.** The dashboard now also subscribes to `[:safety]` and `[:estimator]`, so `BB.Safety.HardwareError` detail (the component and reason behind an error badge) and estimator output (`Odometry` / `Pose`) surface in the event log. Safety *state* transitions already arrived via `[:state_machine]`, so the badge was already accurate — this adds the missing diagnostic detail.
- **Dev demo commands.** `Dev.TestRobot` gains `power` (drains a simulated battery so the status-bar readout shifts green → yellow → red) and `diagnostics` (publishes a hardware-error report and an estimator pose so both surface in the event log).

## [0.1.0] - 2026-06-04

Initial release — a terminal dashboard for [Beam Bots](https://github.com/beam-bots) robots, built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

### Added

- **Dashboard layout.** A multi-panel terminal UI — title bar, Safety, Joint Control, Commands, Events, Parameters, and a status bar — composed through ExRatatui's reducer runtime. Pure state transitions live in `BB.TUI.State`; `BB.TUI.App` wires input and async results to those transitions.
- **Safety panel.** Arm / disarm / force-disarm controls with a confirmation popup for force-disarm, plus an animated throbber while disarming. Reflects the robot's live safety state (`:armed` / `:disarmed` / `:disarming` / `:error`).
- **Joint control panel.** Position table showing joint type (revolute / prismatic / continuous), units (degrees / mm), visual range bars, last-commanded target markers, and simulated-joint tags. Direct keyboard position adjustment in 1%-of-range and 10%-of-range steps.
- **Commands panel.** Lists available robot commands with Ready / Blocked indicators based on runtime state. Argument-less commands execute on Enter; commands with declared arguments open an inline edit mode (Tab / Shift+Tab to cycle fields, type-to-edit, Enter to run, Esc to cancel). Argument types — boolean, integer, float, atom, enum (`{:in, [...]}`), and string — are parsed before dispatch. Entered values are preserved per command across executions.
- **Parameters panel.** Live parameter table grouped by path with real-time updates and schema-aware editing (min / max bounds drive 1%-of-range stepping). Bridge tabs surface remote-parameter lists fetched per bridge, editable through the same keys; press `t` to cycle tabs.
- **Event stream.** Scrollable, color-coded event log with summaries and timestamps taken from `BB.Message.wall_time` (publish time, not arrival time). Pause / resume, clear, and Enter to open a detail popup showing the full payload.
- **High-rate sensor handling.** The event log debounces repeats of the same `{path, payload-type}` within a one-second window so a fast sensor can't flood it, and sensor-driven re-renders are coalesced to ~30fps — keeping the UI responsive under high-rate telemetry while key presses, command results, and safety / parameter / state changes still render immediately. Both windows are tunable.
- **Status bar, help overlay, and theme system.** Status bar shows robot name, safety indicator, runtime state, and contextual key hints; a scrollable help overlay lists the full keybinding reference; a consistent color palette provides semantic styles (safety colors, focus borders, panel headers).
- **Keyboard-driven navigation.** Tab / Shift+Tab to cycle panels, number keys to jump directly to a panel, and vim-style `j`/`k`/`h`/`l` within panels.
- **SSH transport.** Serve the dashboard over SSH; multiple operators can connect simultaneously, each with an isolated session (built on ExRatatui's `:ssh` transport).
- **Distribution attach.** Run the TUI on the robot node and attach a thin renderer from any connected BEAM node (built on ExRatatui's `:distributed` transport).
- **Nerves support.** Register the dashboard as a `nerves_ssh` subsystem so operators can attach over SSH on-device.
- **Runtime inspection.** Snapshot, trace, and inject events into a running TUI via `ExRatatui.Runtime` — useful for debugging SSH sessions that aren't otherwise observable.
- **`mix bb.tui` task.** Standalone launch — `mix bb.tui --robot MyApp.Robot`, with `--ssh` and distribution options.
- **`mix bb_tui.install` Igniter task.** Adds `bb_tui` to a project, imports formatter rules, optionally scaffolds a `BB` robot, and wires up launch for the default, `--ssh`, or `--nerves` install shapes.
- **Headless test suite.** Full coverage using Mimic and ExRatatui's test backend, including end-to-end tests that drive a real server via `ExRatatui.Runtime.inject_event/2`.

[Unreleased]: https://github.com/mcass19/bb_tui/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/mcass19/bb_tui/releases/tag/v0.2.0...0.1.0
[0.1.0]: https://github.com/mcass19/bb_tui/releases/tag/v0.1.0
