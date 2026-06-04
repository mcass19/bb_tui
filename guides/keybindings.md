# Keybindings

The dashboard is fully keyboard-driven. Global keys work from any panel; the rest are scoped to the focused panel. The help overlay (`?`) shows the same reference in-app.

## Global

| Key | Action |
|---|---|
| `q` | Quit |
| `Tab` | Cycle to the next panel |
| `Shift+Tab` | Cycle to the previous panel |
| `1` `2` `3` `4` `5` | Jump directly to the panel whose title shows `[N]` |
| `?` | Toggle help overlay |
| `a` | Arm robot |
| `d` | Disarm robot |
| `f` | Force disarm (error state only) |

Each panel's title carries a bold-cyan `[N]` badge that mirrors the number key for that panel: `[1]` Safety, `[2]` Commands, `[3]` Joints, `[4]` Events, `[5]` Parameters.

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
| `l` / `Right` | Increase value by one step |
| `h` / `Left` | Decrease value by one step |
| `L` | Increase value by ten steps |
| `H` | Decrease value by ten steps |
| `Enter` | Toggle boolean parameter |
| `t` | Cycle to the next bridge tab (Local → bridges → Local) |

Step size is 1% of the declared range when min / max are known — the Spark schema's `{:float, min: 0.0, max: 1.0}` form on the Local tab, or the bridge's flat `:min` / `:max` keys on a bridge tab — and the new value is clamped to the bounds. Parameters without bounds use an absolute step of `+1` for integers and `+0.1` for floats. The same keys dispatch through `BB.Parameter.set` on the Local tab and `BB.Parameter.set_remote` on a bridge tab; a successful remote set refetches that bridge's parameter list so the cached values stay in sync.
