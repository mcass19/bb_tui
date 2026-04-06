## Acceptance Criteria Coverage

### Must Have — All Complete

| Criterion | Status | Notes |
|---|---|---|
| Full-screen terminal application | Done | ExRatatui (ratatui/crossterm), not Ratatouille |
| Safety panel with arm/disarm controls | Done | + force-disarm confirmation popup |
| State display (state machine state) | Done | Embedded in Safety panel |
| Joints table with current positions | Done | + Gauge bars, SIM tags, keyboard control |
| Real-time updates via PubSub | Done | Subscribes to state_machine, sensor, param |
| Keyboard navigation between panels | Done | Tab cycling, 5 panels |
| Basic keyboard shortcuts (quit, arm, disarm) | Done | 32+ keybindings across contexts |
| `mix bb.tui` task for launching | Done | `mix bb.tui --robot Dev.TestRobot` |
| Documentation with usage examples | Done | README with layout diagrams, keyboard reference |
| Tests for model and update logic | Done | 133 doctests + 233 unit tests, 100% coverage |

### Should Have — All Complete

| Criterion | Status | Notes |
|---|---|---|
| Event stream panel with scrolling | Done | + pause/resume, clear, detail popup |
| Command execution | Done | Ready/Blocked indicators, timeout, results |
| Parameter viewing | Done | Grouped by path, real-time via PubSub |
| Parameter editing (simple types) | Done | Integer (±1/±10), float (±0.1/±1.0), boolean toggle |
| Help overlay (`?` key) | Done | Scrollable, all keybindings documented |
| Colour-coded status indicators | Done | Full theme system (21 style functions) |
| Joint limit warnings | Done | Warning (◆ !) at 15%, danger (◉ !!) at 5% of limit |

### Could Have — Not Yet Implemented

| Criterion | Status | Notes |
|---|---|---|
| ASCII art joint diagram | Not started | Would need custom widget |
| Command history | Not started | Could store last N executed commands |
| Log file export | Not started | Could dump events to file |
| Configuration file for keybindings | Not started | Keybindings currently hardcoded |
| Multiple robot support | Not started | Would need robot picker / switcher |
| Mouse support | Not started | ExRatatui supports mouse events already |

### Won't Have — Confirmed Out of Scope

- 3D visualisation
- Complex parameter types (use bb_liveview)
- Video/camera display
- Touch screen support

---

## Known Limitations (vs bb_liveview)

These are intentional differences due to TUI constraints, documented here for transparency.

### Parameter editing uses fixed step sizes

Integer parameters adjust by ±1 (h/l) or ±10 (H/L). Float parameters adjust by ±0.1 or ±1.0. Unlike bb_liveview, which builds sliders with min/max from the parameter definition, bb_tui does not enforce parameter bounds during editing — values are sent to `BB.Parameter.set/3` without clamping. The robot's parameter system is expected to handle out-of-range values.

### Command execution does not support arguments

Commands are executed with an empty goal (`%{}`). bb_liveview has dynamic forms for command arguments (boolean, enum, number, text inputs). Building interactive input forms in a TUI is significantly more complex and was deferred. Commands that require arguments will execute but receive no input.

### No remote/bridge parameters

bb_liveview supports `BB.Parameter.list_remote/2` for bridge parameters (MAVLink, Phoenix, etc.). bb_tui only uses `BB.Parameter.list/1` for local parameters. Adding bridge parameter support would require a tab-like interface similar to bb_liveview's.

### No parameter type units

bb_liveview renders unit labels (`mm`, `kg`, etc.) for `{:unit, type}` parameters and adjusts slider steps accordingly. bb_tui shows raw numeric values without unit awareness.

### Layout ratios are fixed

The dashboard layout (60/40 vertical, 25/75 horizontal, etc.) is not configurable. Terminal size changes are handled via constraint-based layout, but the proportions are hardcoded.

---

## Bonus Features (Beyond Proposal)

These were not in the original proposal but are implemented:

1. **Throbber animation** — Animated spinner during DISARMING state
2. **Event detail popup** — Enter on any event shows full message payload
3. **Event pause/resume** — Freeze the event stream with `p`
4. **Dev test robot** — Simulated WidowX-200 with parameters (motion, controller PID, safety, grip)
5. **Headless test backend** — Full rendering tests without a real TTY
6. **Pure state architecture** — All state in `BB.TUI.State` as pure functions, no side effects
7. **Joint position control** — Keyboard-driven joint nudging (1% and 10% steps)
8. **Force disarm confirmation** — Modal popup for dangerous operations

---

## Open Questions — All Answered

| # | Question | Answer |
|---|---|---|
| 1 | Library choice | ExRatatui (Rust ratatui via NIFs, crossterm backend, precompiled binaries) |
| 2 | Terminal compatibility | crossterm handles capability detection; 3 color tiers (16/256/RGB); `border_type: :plain` for ASCII-only |
| 3 | Joint control via keyboard | Implemented: h/l for 1% step, H/L for 10% step, clamped to limits |
| 4 | Screen size and resize | `Event.Resize` handled, constraint-based layout adapts automatically |
| 5 | Nerves integration | crossterm works on any real PTY (SSH, HDMI, UART). `nerves_ssh` dev shell caveat noted. SSH transport being explored (ex_ratatui#33) |

---

## James's Integration Concerns

These were raised in the PR comment and need discussion.

### 1. "Don't want it to take over the terminal in a release"

**Current behavior:** bb_tui binds to local stdio, so it does take over the terminal.

**How it's handled:** bb_tui is never auto-started. It's launched explicitly via:
- `BB.TUI.run(robot)` from IEx (blocks until quit)
- `BB.TUI.start(robot)` (linked process for supervision)
- `mix bb.tui --robot MyRobot` (mix task)

In a released system, bb_tui would only run if a user explicitly invokes it.

**Question for James:** Is "opt-in from IEx" sufficient, or do we need a separate daemon mode?

### 2. "Attach remotely via distribution"

**Current status:** Not implemented yet.

**Short-term option:** Use `:rpc.call(robot_node, BB.TUI, :run, [MyRobot])` where the TUI renders on the *calling* node's terminal. This should work if the caller has a real PTY, but needs testing.

**Long-term option:** SSH transport in ExRatatui. Instead of reading/writing to local stdio, the TUI connects to an SSH channel. The rendering engine and application code stay the same — only the I/O transport changes. This is tracked in [ex_ratatui#33](https://github.com/mcass19/ex_ratatui/issues/33).

The transport layer is planned as a behaviour in ExRatatui, so adding new transports (SSH, distribution, websocket) is just implementing the behaviour.

**Question for James:** Which approach does he prefer? Is remote distribution the priority, or is SSH-based access more aligned with the Nerves use case?

### 3. "Rust CLI with erl_rpc (like neonfs-cli)"

**Current status:** Out of scope for bb_tui itself.

This is a fundamentally different approach — a standalone Rust binary using `erl_rpc` to connect as a C node. It could coexist with bb_tui but would be a separate project.

The ExRatatui transport behaviour could eventually enable a hybrid: the Rust rendering engine with Elixir application code communicating over distribution.

**Question for James:** Is this an alternative to bb_tui or a complement? Should we prioritize one approach?

---

## Exploration Guide: Remote Call / Distribution

This section outlines how to explore and prototype the remote TUI attachment approach.

### Goal

Enable `BB.TUI` to render on a developer's local terminal while the robot runs on a different BEAM node (e.g. a Nerves device on the network).

### Approach 1: `:rpc.call` (quick experiment)

The simplest thing to try first. The hypothesis is that if the calling node has a real PTY, `ExRatatui` will bind to *that* node's stdio.

**Steps to explore:**

1. **Start two nodes** — a "robot" node and a "dev" node connected via distribution:
   ```
   # Terminal 1 — robot node (could be Nerves, or just a local node)
   iex --name robot@127.0.0.1 --cookie secret -S mix

   # Terminal 2 — dev node (your laptop terminal)
   iex --name dev@127.0.0.1 --cookie secret
   ```

2. **Connect the nodes:**
   ```elixir
   # On the dev node
   Node.connect(:"robot@127.0.0.1")
   ```

3. **Try the naive RPC call:**
   ```elixir
   # On the dev node — does the TUI render HERE or on the robot node?
   :rpc.call(:"robot@127.0.0.1", BB.TUI, :run, [Dev.TestRobot])
   ```

4. **Observe:** Does the TUI render on the dev terminal? Does input work? Does PubSub data flow across nodes? This will likely fail because ExRatatui's NIF binds to the stdio of the node where the NIF is loaded — i.e. the robot node's stdio, not the caller's.

5. **If RPC fails (expected):** Try spawning the TUI process on the *dev* node but subscribing to PubSub on the *robot* node:
   ```elixir
   # On the dev node — TUI runs locally, but data comes from the remote robot
   # This requires the dev node to have bb_tui as a dependency
   BB.TUI.run(Dev.TestRobot, node: :"robot@127.0.0.1")
   ```
   This would need a small change to `BB.TUI.App` to subscribe to the remote node's PubSub. The key question: can `Phoenix.PubSub` subscribe across nodes? (Yes — PubSub uses `pg` which is distribution-aware.)

### Approach 2: SSH transport (ex_ratatui level)

This is the proper long-term solution tracked in [ex_ratatui#33](https://github.com/mcass19/ex_ratatui/issues/33).

**Key questions to research:**

1. **How does `:ssh` in Erlang/OTP handle PTY channels?** Look at `:ssh_connection.ptty_alloc/4` and `:ssh_connection.shell/3`. The SSH daemon can allocate a pseudo-terminal for the connecting client.

2. **How does crossterm (the Rust terminal backend) bind to a file descriptor?** Currently it reads/writes to `/dev/tty` or stdin/stdout. Can it be pointed at an arbitrary fd (e.g. the SSH channel's fd)?

3. **Explore the Erlang `:ssh` daemon API:**
   ```elixir
   # Start an SSH daemon that accepts connections and launches the TUI
   :ssh.daemon(2222, [
     system_dir: ~c"/path/to/host/keys",
     user_dir: ~c"/path/to/authorized_keys",
     shell: fn user -> BB.TUI.ssh_shell(user) end
   ])
   ```

4. **The transport behaviour shape** — ExRatatui would define something like:
   ```elixir
   @callback init(opts) :: {:ok, state}
   @callback read_input(state) :: {:ok, binary(), state}
   @callback write_output(binary(), state) :: :ok
   @callback terminal_size(state) :: {width, height}
   ```
   The default implementation uses crossterm/stdio. An SSH implementation would read/write to the SSH channel instead.

5. **Reference:** Look at how [tui-rs-ssh](https://github.com/examples) or Python's `paramiko` + `blessed` handle SSH-based TUI rendering for inspiration.

### Approach 3: Rust CLI with `erl_rpc` (separate project)

This is a standalone Rust binary — completely decoupled from the BEAM.

**Key questions to research:**

1. **What is `erl_rpc`?** It implements the Erlang distribution protocol in Rust, allowing a Rust process to connect as a hidden node and call Erlang/Elixir functions.

2. **Data flow:** The Rust CLI would call `BB.Robot.Runtime.positions/1`, `BB.Robot.Runtime.state/1` etc. via RPC, render locally using ratatui directly (no NIF), and send commands back via RPC.

3. **Tradeoffs vs. the BEAM approach:**
   - (+) No BEAM needed on the developer machine
   - (+) Native ratatui performance, no NIF overhead
   - (-) Must reimplement all rendering logic in Rust
   - (-) Must maintain two codebases (Elixir panels + Rust panels)
   - (-) No PubSub — must poll or implement a subscription protocol

4. **Verdict:** Likely only worth it if there's a strong requirement for a standalone binary distribution. The SSH transport approach gets most of the benefits with far less duplication.

### Recommended exploration order

1. **Start with Approach 1** — 30 minutes to validate whether cross-node PubSub + local TUI rendering works. This gives remote access with zero changes to ExRatatui.
2. **If Approach 1 works**, ship it as the "dev mode" remote solution.
3. **In parallel, prototype Approach 2** for the production/Nerves use case where SSH is the natural access method.
4. **Defer Approach 3** unless James has a strong preference for a standalone binary.

