# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Unit-typed parameters are readable and adjustable.** `bb` 0.31.0 converts a unit-typed parameter into its declared unit on every write, so a `{:unit, :meter}` parameter's value is reliably a `Localize.Unit` in a known unit — which the TUI previously rendered through `inspect` (`Localize.Unit.new!(0.5, "meter")` in a 30%-wide table cell) and silently refused to adjust, because the `h`/`l` handlers only matched plain numbers. The Value column now renders the magnitude the way a bare number would, followed by the canonical unit name (`0.500 meter`), the Type column renders `unit:meter` (matching `bb_liveview`'s convention), and `h`/`l`/`H`/`L` step the magnitude with the same 1%/10%-of-range scaling numeric parameters get. Bounds need one extra move: the DSL deliberately keeps a bound in the unit it was declared in, so a `max` of 100 centimeter can bound a meter parameter — `BB.TUI.State.unit_bounds_in/2` converts each bound into the value's own unit before step sizing and clamping, and opens a side it cannot convert rather than guessing (bb still validates the write server-side).

- **String and atom parameters are editable, and fixed-set parameters cycle.** Enter on a string or plain-atom parameter opens an inline editor in the value cell — typed characters append to the buffer (shown with a cursor mark), backspace deletes, enter commits, and esc cancels. A committed buffer with a leading `:` reads as an atom, which is also how an atom value is prefilled, so it round-trips; bb validates the written value against the parameter's schema, so a wrong type comes back as a refused set rather than a crash. While the editor is open the TUI is modal: the edit keys are matched ahead of the global ones, so a `q`, `a`, or `t` lands in the buffer instead of quitting, arming, or switching tabs, and the status bar swaps to commit/cancel hints. A parameter declared with an `{:in, values}` type doesn't free-text edit at all — `h`/`l` cycles it through its allowed values with wrap-around, whatever their type. Bridge tabs are untouched: a bridge's parameter types are its own contract, and numeric stepping plus boolean toggling remain the remote surface.

- **The dev robot demos every parameter shape.** Every parameter now carries a `doc`, and three joined so each panel feature has a live fixture: `motion.cruise_speed` (`{:unit, :meter_per_second}`), `controller.trim` (`{:unit, :degree}` whose bounds are declared in radians, exercising cross-unit clamping), and `identity.label` (a string for the inline editor). A new `Dev.GaitSelector` component registers a hand-written `param_schema/0` with a `{:in, [:walk, :trot, :crawl]}` `gait.pattern` parameter — the fixed-set shape the robot DSL cannot declare — so `h`/`l` cycling is demoable too.

- **The selected parameter's `doc` shows in the panel.** `BB.Parameter.list/2` has always carried each parameter's `doc` string and the TUI already stored it, but the panel's three columns never showed it. It now renders as a dim title on the panel's bottom border while the panel is focused — the table is too narrow for a fourth column, and the bottom border was unused. The doc follows the selection through the sorted row order; parameters without a doc, unfocused panels, and bridge tabs (whose parameters carry no schema doc) leave the border unadorned. Mirrors `bb_liveview`, which renders the doc under each parameter name.

### Fixed

- **Shift+tab works from browser transports.** Terminal transports report shift+tab as crossterm's `back_tab` code, which is all the panel-cycling and argument-focus clauses matched; `phoenix_ex_ratatui` reports the same chord as `tab` with a `"shift"` modifier, so in a browser it fell through to the plain-tab clauses and cycled *forward*. The modifier form now normalizes to `back_tab` before any tab clause can match.

- **Parameter bounds work again against `bb` 0.30+.** `bb` 0.30.0 changed what `BB.Parameter.list/2` reports: the generated validator tuple (`{:integer, [min: 0, max: 100]}`) became the declared type (`:integer`) with `min`/`max` as separate metadata keys. `BB.TUI.State.parameter_bounds/2` still dug bounds out of the old tuple shape, which no longer occurs, so every bounded parameter lost its range-scaled `h`/`l` step (falling back to 1 / 0.1) and its clamping — and since `bb` 0.30 also started rejecting out-of-range writes, stepping into a bound produced a silently refused set instead of a clamp. Bounds now come from the `min`/`max` metadata keys, which `BB.TUI.State.update_parameters/2` previously discarded.

## [0.5.0] - 2026-08-25

### Added

- **Actuator refusals from jog keys now surface in the event log.** `BB.TUI.Robot.set_actuator/4` uses `set_position/4`'s default `:pubsub` delivery instead of `delivery: :direct`, so the actuator's answer comes back — and because that answer arrives via a `GenServer.call`, the call moves off the event loop into an `ExRatatui.Command.async/2` whose result maps to `{:actuator_result, actuator, result}`. An `:ok` is dropped without a render (there is one per key autorepeat); a `{:error, reason}` — including the `{:exit, _}` the async runner traps when an actuator is dead or wedged, which previously had nowhere to go — is appended to the event log as `joint ✗ reason`, debounced per actuator like any other event. The call waits 250ms rather than `set_position/4`'s default five seconds — a jog is a stream of targets of which only the latest matters, and the long wait would let tasks pile up under key autorepeat against a wedged actuator (matching `BB.LiveView.Components.JointControl`). The joint's target keeps the asked-for value; position still moves only on sensor feedback. As a side effect of `:pubsub` delivery, jog commands themselves now appear in the event log, since the command is published for observers and the TUI already subscribes to `[:actuator]`.

### Changed

- **Follows the removal of `BB.Actuator.set_position!/4` in `bb` core (breaking).** `bb` made `set_position/4` synchronous and dropped both `set_position!/4` and `set_position_sync/5`; the `!` cast is now `set_position(robot, target, position, delivery: :direct)`. `BB.TUI.Robot.set_actuator/4` sends that, locally and over `:rpc`, so behaviour is unchanged — a cast, no publication, `:ok` regardless of whether the actuator accepted it. The synchronous default was considered and rejected for this caller: `set_actuator/4` is invoked inline from `BB.TUI.App.update/2` on a keypress, and a `GenServer.call` there would stall the process that owns the terminal for the round trip and exit it on timeout. Surfacing refusals would need the call moved off the event loop and somewhere in the UI to put the error, which is worth doing separately. The `mix.exs` requirement moves from `~> 0.28 and >= 0.28.1` to `~> 0.30` to encode this: `set_position/4` also exists in `bb` 0.28/0.29, as a publish that ignores options it doesn't recognise, so against an older `bb` this code compiles clean and quietly publishes where it means to cast. An ignored option fails silently at runtime where a removed function fails loudly at compile time, which makes the floor load-bearing rather than housekeeping.

## [0.4.0] - 2026-08-10

### Added

- **Trajectory commands read properly in the event log.** A `BB.Message.Actuator.Command.Trajectory` published on `[:actuator | joint]` has `waypoints` rather than a `position`, so it missed the actuator summary clause and fell through to the generic `inspect` — a truncated blob of waypoint keyword lists. It now summarizes as `shoulder ← trajectory 4 waypoints over 2400ms` (with `×5` / `×∞` appended when the trajectory repeats), and the detail pane collapses each waypoint to `position@time` instead of listing the `velocity: nil, acceleration: nil` that `bb` 0.29 made optional. The dev robot gains a `trajectory` command that publishes a real trajectory per joint and then sweeps `shoulder` and `elbow` through its waypoints over ~2.4s, so the 3D view shows motion passing *through* the waypoints instead of snapping between targets.

### Changed

- **Follows the `positions` → `configurations` rename in `bb` core (breaking).** `bb` 0.27.0's multi-DoF joint work renamed `BB.Robot.Runtime`'s `positions/1` to `configurations/1` — a joint's configuration is only a float when it has one degree of freedom — so the TUI crashed with an `UndefinedFunctionError` during dashboard init against `bb` >= 0.27. `BB.TUI.Robot`'s `positions/2` is now `configurations/2` and routes to the new accessor both locally and over `:rpc`. The joints panel and the visualization drive single-DoF joints, so values remain floats and behaviour is otherwise unchanged. The `mix.exs` requirement moves from `~> 0.20` to `~> 0.28 and >= 0.28.1` to encode the new API — the floor is 0.28.1 rather than 0.27.0 because `bb` 0.27.0 and 0.28.0 close a compile-time cycle (`BB.Message.Option` pattern-matches the geometry structs whose modules import it back) that deadlocks Elixir 1.19's parallel compiler; `bb` broke that cycle in 0.28.1, so the `~> 1.19` floor and the two-cell CI matrix stay as they are. Mirrors `bb_liveview` v0.3.0's migration.

- **Multi-DoF joints flow through the TUI (breaking).** Joint configurations are stored verbatim, shaped to the joint's type — a float for single-DoF joints, a `BB.Math.Transform2D` for planar, a `BB.Math.Transform` for floating — so `BB.TUI.State`'s `update_positions/2` is renamed `update_configurations/2` and dashboard init seeds missing joints with their type's identity. Planar and floating joints appear in the joints panel as read-only rows with a compact pose (`(x, y, θ°)` / translation `(x, y, z)`), target-adjust keys skip them, and event details render their transform entries compactly. Driving them is not possible by design: `BB.Actuator.set_position!/4` takes a single number, and bb has no command API for a transform target.

- **`BB.TUI.Viz.RobotScene` delegates forward kinematics to bb core.** The scene is built from `BB.Robot.Kinematics.all_link_transforms/2` — one flat node per visual link carrying its base-frame transform — instead of a hand-rolled single-DoF FK walk, so planar and floating joints pose correctly in the 3D view and the local FK code is deleted. Requires `robot.topology` (every runtime-built `BB.Robot` has it).

## [0.3.1] - 2026-07-31

### Added

- **`usage-rules.md`, shipped in the package.** Matches the convention `bb` and `bb_liveview` already follow, so an agent working in a Beam Bots workspace picks up rules for the TUI layer alongside the framework's own (`mix usage_rules.sync <file> bb_tui`). Covers the entry points and how to pick between them, the full option table, `BB.TUI.Renderer` for consumer-owned payloads, command cancellation, and the anti-patterns that actually bite — declaring the dashboard in `topology`, calling the blocking `run/2` from a supervision tree, or setting `:node` without connecting first. Added `{:usage_rules, "~> 1.2", only: [:dev]}` for the sync tooling.

### Fixed

- **Continuous commands are no longer reported as timed out while they are still running.** Commands dispatched from the UI were awaited with a UI-side deadline (`:bb_tui, :command_timeout`, default 30s), so a continuous command — one that only returns when it stops or is cancelled — surfaced `{:error, :timeout}` in the result panel after 30 seconds even though it was running normally, with no way to stop it. `BB.Command.await/2` is now called with `:infinity`; runaways stay bounded by the command's own DSL `timeout`. Matches `BB.LiveView.Components.Command`, which bb_tui mirrors.

### Added

- **Cancel a running command with `c` in the commands panel.** Command execution is now two-phase — one async starts the command and reports `{:command_started, _}`, a second awaits it and reports `{:command_result, _}` — so the running command's pid reaches state (`BB.TUI.State.Commands.executing_pid`) and can be cancelled. `BB.TUI.Robot.cancel_command/2` routes locally or over `:rpc` like every other runtime call. Cancelling resolves the pending await, so the result panel shows the cancellation instead of hanging on the throbber.

### Removed

- **The `:bb_tui, :command_timeout` config key.** It no longer has anything to bound now that the await is `:infinity` — the DSL `timeout` and the new cancel key cover both cases. Setting it is now a no-op and can be deleted from consumer config.

## [0.3.0] - 2026-06-23

### Added

- **Configurable subscription paths.** `BB.TUI.run/2` (and `start/2` / `start_ssh/2`) now accept a `:subscribe_paths` option that overrides the default control-plane set the dashboard subscribes to — e.g. `[[:state_machine], [:command]]` to narrow it, or a downsampled observability topic instead of the high-rate sensor firehose. Threaded through both the local and SSH transports; default behaviour is unchanged when the option is omitted. Thanks to [@lostbean](https://github.com/lostbean).
- **Consumer-supplied renderers.** `BB.TUI.run/2` (and `start/2` / `start_ssh/2`) now accept a `:renderers` option — a `%{path_prefix => module}` map that lets a consumer teach the dashboard how to render a payload on a PubSub path it owns, without bb_tui knowing the payload's struct. A module implements the new `BB.TUI.Renderer` behaviour: `summarize/2` returns the event-log line (or `nil` to fall back to the generic `inspect/2`), and the optional `observed/2` feeds an at-a-glance status-bar slot. Messages route to a renderer by longest-matching prefix, like a routing table. Fully additive — with no `:renderers`, dispatch is unchanged. Threaded through both the local and SSH transports. Thanks to [@lostbean](https://github.com/lostbean).

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

[Unreleased]: https://github.com/mcass19/bb_tui/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/mcass19/bb_tui/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mcass19/bb_tui/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/mcass19/bb_tui/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/mcass19/bb_tui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcass19/bb_tui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mcass19/bb_tui/releases/tag/v0.1.0
