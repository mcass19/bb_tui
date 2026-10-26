# Driving

An extension that declares a `drive` (see the [Extensions guide](extensions.md)) turns the arrow keys into a hold-to-drive pad. bb_tui owns the generic part — noticing which keys are held, ticking, stopping — and calls the functions the extension names for the robot-specific part:

```elixir
drive do
  publish {BB.NSK.Drive, :command}   # command(robot, throttle, turn)
  stop {BB.NSK.Drive, :stop}         # stop(robot)
  turn_scale param([:yaw, :turn_rate])
  rate 20
end
```

## The Drive tab

The extension's Drive tab shows the pad: the arrows light while held, two bars show the throttle and turn being published, and the mode and tick rate sit underneath. Panels the extension declares with `tab :drive` sit beside it, so the readings that matter while driving stay in view.

Driving only happens on this tab. Elsewhere the arrows keep their usual jobs, and switching away from the Drive tab while a key is held stops the robot.

## Taking the wheel

Only one dashboard session drives a robot at a time. On the Drive tab, `t` takes the wheel — the pilot lease — and `t` again hands it back, stopping first; without it the arrows don't drive and the pad says so. Another session holding it shows as "driven by <node> since <time>" (the time this session first saw it there), checked every second while the tab is up.

The lease is a `:global` name registered to the session that holds it (`BB.TUI.Pilot`), so it reaches every connected node — a laptop on `node:`, an SSH session on the robot, an attached terminal — and goes away with its session, however that ends. After a network split heals, two sessions may both believe they hold it for a moment; the one that loses is told, and stops at once. Every drive tick checks the lease too, so a session whose lease went elsewhere stops within a tick.

The lease coordinates bb_tui sessions only. Other ways of driving the same robot — a badge, a phone pad — don't take it, and the robot's own command handling decides between them.

## What gets published

Up and down set the throttle to 1 and -1, left and right the turn to 1 and -1 (left positive, counter-clockwise), one direction per axis: pressing the opposite arrow takes over. Each is multiplied by its scale — a number, or a `param(path)` read on every tick, so retuning the parameter changes the next command — and handed to `publish` as floats.

While a key is held, `publish` is called once straight away and then `rate` times a second. When the last key is let go, `stop` is called once. Under `node:` both are cast to the robot's node, so a slow link never holds up the tick.

## Holding a key, with and without key releases

Most terminals only report a key going down; holding it repeats the press after the operating system's autorepeat delay, around half a second. That is longer than a balancing robot's dead-man timeout, so the pad can't wait for the repeats to start before driving:

- **Repeat mode** (the start). A key counts as held for 600 ms after its first press, covering the autorepeat delay, and then for 150 ms after each repeat. When the repeats stop, so does the robot, within 150 ms of letting go.
- **Release mode**. The first key release the dashboard sees switches the session over: a key is held until its release arrives. A one-second safety window, refreshed by the key's repeats, still lets go of a key whose release got lost.

The pad shows which mode is on. Key releases come from terminals speaking the kitty keyboard protocol (kitty, Ghostty, WezTerm, foot, Alacritty, iTerm2) and from the browser; GNOME Terminal and other VTE-based terminals, and most tmux setups, stay in repeat mode.

## When driving stops

Besides letting go of the keys, bb_tui calls `stop` when the dashboard quits, when the Drive tab is left, when the wheel is handed back or lost, when the terminal window loses focus (the dashboard asks for focus reports whenever an extension declares a drive), and when the session ends for any reason. The robot's own dead-man timeout (`drive_timeout` on a balance bot) stays the backstop for everything bb_tui can't see, such as a dropped SSH connection or a frozen laptop.

## Transports

Driving works on every transport: the local terminal, SSH, the browser, `:node` and `Distributed.attach/3`. What differs is whether key releases arrive (release mode) or not (repeat mode); the stops above apply on all of them.
