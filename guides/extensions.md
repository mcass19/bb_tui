# Extensions

A robot or kit can extend the dashboard with what only it knows about: how to drive it, which numbers matter while it runs, the commands worth a key of their own, and what to tell the operator in each state. bb_tui renders all of it with its own widgets and theme; the extension only declares.

An extension is a module of its own, apart from the robot module, so the robot stays a plain bb robot and the same robot can be watched with or without it.

## Declaring an extension

```elixir
defmodule Goatbot.TUI do
  use BB.TUI.Extension

  drive do
    publish {BB.NSK.Drive, :command}
    stop {BB.NSK.Drive, :stop}
    turn_scale param([:yaw, :turn_rate])
  end

  panels do
    panel :balance do
      title "Balance"
      tab :drive
      readout "lean", joint(:lean), unit: :degree, decimals: 1
      readout "setpoint", controller(:pid_balancer, :setpoint), unit: :degree
      plot "lean vs target", [joint(:lean), controller(:pid_balancer, :target)]
    end
  end

  keys do
    bind "s", command: :stand, label: "stand"
  end

  hints do
    state :idle, "hold it upright, then s to stand"
  end
end
```

Four sections, all optional:

- **`drive`** — hold-to-drive with the arrow keys. While a key is held, bb_tui calls `publish(robot, throttle, turn)` at `rate` Hz, with throttle and turn of -1, 0 or 1 scaled by `throttle_scale` and `turn_scale`; letting go calls `stop(robot)`. bb_tui never needs to know the kit: the extension names the functions.
- **`panels`** — boxes of `readout`s (a labelled value) and `plot`s (a live chart), each on a tab of its own unless `tab` groups it; `tab :drive` puts a panel beside the drive pad.
- **`keys`** — `bind` a key to a robot command. bb_tui's own keys (`BB.TUI.Extension.reserved_keys/0`) can't be bound, and the compiler says so.
- **`hints`** — a banner under the title bar for each robot runtime state.

## Sources

Readouts, plots and drive scales read their values from sources:

| Source | Value |
|---|---|
| `joint(:lean)` | a joint's position, as the joints panel shows it |
| `controller(:pid_balancer, :setpoint)` | a field of the map a controller answers `handle_call(:inspect, ...)` with; a list reaches into nested maps |
| `topic([:sensor, :wheel], :velocity)` | a field of the latest message under a path; a list reaches into the payload |
| `param([:yaw, :turn_rate])` | a robot parameter's current value |

A `topic` source keeps the latest payload published on its path. Sensors and actuators publish under their full topology path (`[:sensor, :base_link, …, :imu]`), so a two-segment path `[root, name]` also matches any path that starts with `root` and ends with `name` — the same short name the event log shows.

A `controller` source reads the map the controller answers `handle_call(:inspect, ...)` with. Controllers publish nothing, so the dashboard polls them, four times a second and never more than one call per controller at a time; one that isn't running, doesn't answer `:inspect` or takes longer than 200 ms shows its readouts as `-` until it answers again. Any map works, missing keys included.

## Units and formatting

`unit:` names the unit a readout is shown in, as a bb unit atom (`:degree`, `:centimeter_per_second`, `:volt`). A plain number is taken to be in SI units, the way bb works — radians, metres, metres per second — so `joint(:lean), unit: :degree` shows degrees; a unit-typed parameter converts from its own unit. An unknown unit fails at compile time.

`scale:` multiplies the value before the conversion, for a source in some other unit (wheel radians per second to metres per second, say). `decimals:` rounds; floats otherwise show two. A value that isn't there yet shows as `-`, and one that isn't a number as plain text.

The full option reference, generated from the DSL itself, is [the Extension DSL](DSL-BB.TUI.Extension.md).

## Wiring it in

Every way of starting the dashboard takes the same `:extensions` list:

| Transport | Where the option goes |
|---|---|
| IEx / scripts | `BB.TUI.run(MyApp.Robot, extensions: [MyApp.TUI])` |
| Supervised | `{BB.TUI, robot: MyApp.Robot, extensions: [MyApp.TUI]}` |
| SSH daemon | `BB.TUI.start_ssh(MyApp.Robot, port: 2222, extensions: [MyApp.TUI])` |
| `nerves_ssh` subsystem | `BB.TUI.subsystem(MyApp.Robot, extensions: [MyApp.TUI])` |
| Browser | `use BB.TUI.Live, robot: MyApp.Robot, extensions: [MyApp.TUI]` |
| Distributed attach | `{ExRatatui.Distributed.Listener, mod: BB.TUI.App, app_opts: [robot: MyApp.Robot, extensions: [MyApp.TUI]]}` |
| Mix task | `mix bb.tui --robot MyApp.Robot --extension MyApp.TUI` |

Several extensions can be combined, a kit's and a robot's say: their panels, binds and hints are merged in the order given. Only one may declare a `drive`, and two can't bind the same key or name the same panel; the session refuses to start rather than guess.

The dashboard subscribes to the topics the extensions' `topic/2` sources read, unless a subscription already covers them (`[:sensor]` covers `[:sensor, :imu]`).

A drive's functions are checked when the session starts, where they will run: under `node:`, on the robot's node. A module that only exists on the robot passes the compile-time check and is caught there instead.
