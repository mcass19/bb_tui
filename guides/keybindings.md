# Keybindings

The dashboard is fully keyboard-driven. Global keys work from any panel; the rest are scoped to the focused panel. The help overlay (`?`) shows the same reference in-app.

## Global

| Key | Action |
|---|---|
| `q` | Quit |
| `[` `]` | Switch top-level tab (Control Panel / Visualization) |
| `Tab` | Cycle to the next panel (Control Panel tab) |
| `Shift+Tab` | Cycle to the previous panel (Control Panel tab) |
| `1` `2` `3` `4` `5` | Jump directly to the panel whose title shows `[N]` |
| `?` | Toggle help overlay |
| `a` | Arm robot |
| `d` | Disarm robot |
| `f` | Force disarm (error state only) |

Each panel's title carries a bold-cyan `[N]` badge that mirrors the number key for that panel: `[1]` Safety, `[2]` Commands, `[3]` Joints, `[4]` Events, `[5]` Parameters.

## Visualization tab

The Visualization tab renders the live robot in 3D from its URDF topology and joint positions. The camera orbits the robot and reposes in real time as sensor data arrives.

| Key | Action |
|---|---|
| `Left` / `Right` or `h` / `l` | Orbit the camera |
| `Up` / `Down` or `k` / `j` | Tilt the camera |
| `+` / `-` | Zoom in / out |
| `r` | Reset the camera |
| `m` | Cycle render mode (auto / kitty / sixel / iterm2 / half-block / braille / ascii) |

## Events panel

| Key | Action |
|---|---|
| `j` / `Down` | Scroll down |
| `k` / `Up` | Scroll up |
| `Enter` | Show event details |
| `p` | Pause / resume |
| `c` | Clear events |

## Commands panel

| Key | Action |
|---|---|
| `j` / `Down` | Select next |
| `k` / `Up` | Select previous |
| `Enter` | Execute (or enter argument edit mode when the command declares arguments) |

### Command edit mode

Active when the selected command declares arguments and `Enter` is pressed.

| Key | Action |
|---|---|
| `Tab` / `Down` | Focus next argument |
| `Shift+Tab` / `Up` | Focus previous argument |
| Printable key | Append to focused argument |
| `Backspace` | Delete last char of focused arg |
| `←` / `h` | Cycle to previous value (enum args only) |
| `→` / `l` | Cycle to next value (enum args only) |
| `Enter` | Execute with current values |
| `Esc` | Exit edit mode (keeps values) |

Enum-typed args (`{:in, [...]}` in the Spark schema) render as `‹ value ›` chevrons and respond to `←`/`→` (or `h`/`l`) instead of needing the atom typed literally. For non-enum args, `h`/`l` continue to append to the buffer; `←`/`→` are no-ops outside of enum picks. Values are parsed before dispatch: `"true"`/`"false"` become booleans, `":foo"` an atom, numeric an integer or float, otherwise a string.

## Joints panel

| Key | Action |
|---|---|
| `j` / `Down` | Select next joint |
| `k` / `Up` | Select previous joint |
| `l` / `Right` | Increase position (1% step) |
| `h` / `Left` | Decrease position (1% step) |
| `L` | Increase position (10% step) |
| `H` | Decrease position (10% step) |

## Parameters panel

| Key | Action |
|---|---|
| `j` / `Down` | Select next parameter |
| `k` / `Up` | Select previous parameter |
| `l` / `Right` | Increase value by one step (cycles a fixed-set parameter forward) |
| `h` / `Left` | Decrease value by one step (cycles a fixed-set parameter backward) |
| `L` | Increase value by ten steps |
| `H` | Decrease value by ten steps |
| `Enter` | Toggle a boolean parameter, or open the inline editor on a string / atom parameter |
| `t` | Cycle to the next bridge tab (Local → bridges → Local) |

Step size is 1% of the declared range when min / max are known — the `min` / `max` metadata `BB.Parameter.list/2` reports on the Local tab (bb 0.30+), or the bridge's flat `:min` / `:max` keys on a bridge tab — and the new value is clamped to the bounds. Parameters without bounds use an absolute step of `+1` for integers and `+0.1` for floats. Unit-typed parameters (`{:unit, :meter}` and friends) render as magnitude plus canonical unit name (`0.500 meter`) and step in that unit; a bound declared in a different unit is converted before sizing and clamping. The same keys dispatch through `BB.Parameter.set` on the Local tab and `BB.Parameter.set_remote` on a bridge tab; a successful remote set refetches that bridge's parameter list so the cached values stay in sync.

A parameter declared with an `{:in, values}` type doesn't free-text edit — `h`/`l` cycle it through its allowed values with wrap-around, whatever their type. While the panel is focused, the selected parameter's `doc` renders as a dim title on the panel's bottom border.

### Parameter edit mode

Active when `Enter` is pressed on a string or plain-atom parameter on the Local tab. The value cell turns into a text buffer (prefilled with the current value; an atom is prefilled with its leading `:`), and the status bar swaps to commit / cancel hints.

| Key | Action |
|---|---|
| Printable key | Append to the buffer |
| `Backspace` | Delete last char of the buffer |
| `Enter` | Commit — a leading `:` reads as an atom, anything else as a string |
| `Esc` | Cancel, keeping the current value |

The editor is modal: its keys are matched ahead of the global ones, so `q`, `a`, `t`, and the number keys land in the buffer instead of quitting, arming, or switching tabs. bb validates the committed value against the parameter's schema, so a wrong type surfaces as a refused set in the event log rather than a crash. Bridge tabs don't open the editor — numeric stepping and boolean toggling remain the remote surface.
