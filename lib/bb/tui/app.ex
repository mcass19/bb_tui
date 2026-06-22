defmodule BB.TUI.App do
  @moduledoc """
  Main TUI application using the `ExRatatui.App` **reducer runtime**.

  Renders the dashboard layout and handles every keyboard event,
  PubSub message, and side effect through a single `update/2` arrow.
  Pure state transitions live in `BB.TUI.State`; this module's job is
  to wire input and async results to those transitions and return
  declarative `ExRatatui.Command` values for IO.

  ## Layout

      ┌ Safety ────────┬─ Joint Control ──────────────────────────────┐
      │ ● ARMED        │ Joint       Type  Position  Range           │
      │ Runtime: Idle  │ elbow       rev   -63.8°    ████████░░░░░░  │
      │ [a] Arm        │ gripper SIM pri    30.6mm   ███░░░░░░░░░░░  │
      │ [d] Disarm     │ ...                                         │
      ├ Commands ──────┤                                             │
      │ ▶ home   Ready │                                             │
      │   calibrate    │                                             │
      ├ Events (47) ───┴── Parameters ───────────────────────────────┤
      │ 18:23:12 sensor.sim  │ speed              100               │
      │ 18:23:11 state_m...  │ controller.kp      0.5               │
      └──────────────────────┴───────────────────────────────────────┘
       Robot | ● Armed | idle | [q]Quit [Tab]Panel [?]Help

  ## Reducer callbacks

    * `init/1` — validates the robot module, subscribes to PubSub
      (`{:bb, _, _}` messages flow into `update/2` as `{:info, _}`
      automatically), and snapshots ETS state. No `Task.Supervisor`
      is required: long-running command execution is owned by the
      runtime via `ExRatatui.Command.async/2`.
    * `render/2` — composes panel functions into a flat
      `[{widget, rect}]` list (the events panel contributes two panes:
      the list and an overlay `ExRatatui.Widgets.Scrollbar`).
    * `update/2` — the single dispatch arrow. Receives `{:event, ev}`
      for terminal input and `{:info, msg}` for everything else
      (PubSub, async results, subscription ticks, `send_after`
      messages). Returns `{:noreply, state}` for pure transitions or
      `{:noreply, state, commands: [cmd]}` when an effect should fire.
    * `subscriptions/1` — declares the throbber tick interval whenever
      the dashboard has something animating (a `:disarming` safety
      state or a command currently executing), and a one-shot
      `:sensor_flush` tick whenever a sensor render is pending (see
      *High-rate sensor handling*). The runtime diffs the result
      against the previous one, so timers only run when needed. This
      replaces the previously-dormant `Process.send_after`-style
      throbber tick.

  ## High-rate sensor handling

  Robot sensor readings arrive on the `[:sensor | _]` path and can be
  very fast. Two mechanisms keep the UI responsive without dropping
  meaningful information:

    * `BB.TUI.State.append_event/3` debounces the event log — a repeat
      of the same `{path, payload-type}` within `throttle.debounce_ms`
      (default 1s) is dropped, so one fast sensor cannot evict every
      other event from the 100-entry log.
    * Sensor messages update state but suppress their immediate render
      (`render?: false`); a one-shot `:sensor_flush` tick
      (`throttle.flush_ms`, default ~33ms / 30fps) armed by
      `subscriptions/1` performs a single coalesced redraw. Every other
      message — key presses, command results, safety/param/state
      events — still renders immediately.

  Both intervals live in the `BB.TUI.State.Throttle` substruct, so tests
  can shrink or disable them (a debounce window of `0` disables it).

  ## Async commands

  Pressing Enter on a Ready command executes it when the command has
  no arguments, or enters an inline argument-edit mode when the
  command declares arguments. From edit mode, Tab/Shift+Tab cycle
  fields, typing edits the focused field, Enter executes with the
  parsed values, and Esc exits without executing.

  Execution returns a `Command.async/2` that calls
  `BB.Command.await/2`, which waits on the spawned command via
  `GenServer.call`, falls back to bb's `ResultCache` if the handler
  finishes before we can await, and enforces the timeout internally.
  The result arrives as a single `{:command_result, _}` info message
  (success, error, or `{:error, :timeout}`).

  ## Side-effect convention

  Fast, fire-and-forget calls (`Robot.arm/2`, `Robot.disarm/2`,
  `Robot.set_actuator/4`, `Robot.set_parameter/4`,
  `Robot.publish/4`, `Robot.force_disarm/2`) are invoked inline from
  `update/2` rather than wrapped in a `Command.async/2`. They are
  effectively constant-time PubSub publishes; the boilerplate of
  routing through a no-op result mapper would dwarf the call. Only
  `Robot.execute_command/4`, which monitors a spawned command process
  and waits for its `:DOWN`, goes through `Command.async/2`.

  ## Configuration

  The wait window for `BB.Command.await/2` is compile-time configurable
  via `Application.compile_env/3`:

      # config/config.exs
      config :bb_tui, command_timeout: 30_000

  Default is `30_000` ms. The test suite overrides this to `100` ms in
  `config/test.exs` to keep timeout assertions snappy. Because the
  value is read with `compile_env`, downstream apps need to recompile
  `:bb_tui` after changing the config (`mix deps.compile bb_tui
  --force`).
  """

  use ExRatatui.App, runtime: :reducer

  alias BB.Robot.Joint
  alias BB.TUI.Panels
  alias BB.TUI.Robot
  alias BB.TUI.State
  alias ExRatatui.Command
  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Subscription

  @command_timeout Application.compile_env(:bb_tui, :command_timeout, 30_000)

  # Visualization-tab camera step sizes (radians / world units per keypress).
  @viz_orbit 0.15
  @viz_zoom 0.1

  # ── Init ──────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    robot = Keyword.fetch!(opts, :robot)
    node = Keyword.get(opts, :node)

    unless Code.ensure_loaded?(robot) and
             function_exported?(robot, :robot, 0) and
             function_exported?(robot, :spark_dsl_config, 0) do
      raise ArgumentError, "#{inspect(robot)} is not a valid BB robot module"
    end

    paths =
      Keyword.get(opts, :subscribe_paths, [
        [:state_machine],
        [:sensor],
        [:param],
        [:actuator],
        [:command],
        [:safety],
        [:estimator]
      ])

    Robot.subscribe(robot, paths, node)

    renderers = Keyword.get(opts, :renderers, %{})

    robot_struct = Robot.get_robot(robot, node)
    positions = Robot.positions(robot, node)

    joints =
      robot_struct
      |> BB.Robot.joints_in_order()
      |> Enum.filter(&Joint.movable?/1)
      |> Map.new(&{&1.name, %{joint: &1, position: positions[&1.name] || 0.0, target: nil}})

    commands = Robot.discover_commands(robot, node)
    bridges = Robot.list_bridges(robot, node)

    state =
      %State{
        robot: robot,
        robot_struct: robot_struct,
        node: node,
        safety: %State.Safety{
          state: Robot.safety_state(robot, node),
          runtime: Robot.runtime_state(robot, node)
        },
        joints: %State.Joints{entries: joints},
        commands: %State.Commands{available: commands},
        renderers: renderers
      }
      |> State.update_parameters(Robot.list_parameters(robot, [], node))
      |> State.set_parameter_tabs(bridges)

    # Probe the terminal once on mount so the Visualization tab's pixel
    # render modes (Kitty / Sixel / iTerm2) and `render_mode: :auto` pick up
    # the real protocol and cell pixel size. Without this the font size
    # defaults to 8x16, sizing the rendered image far too small and anchoring
    # it in the pane's corner. Soft-fails (no TTY) and is skipped under
    # test_mode, so it has no effect on the suite.
    {:ok, state, probe_image_protocol: true}
  end

  # ── Render ────────────────────────────────────────────────────

  @impl true
  def render(state, frame) do
    full = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Title bar + main area + status bar
    [title_bar_area, main, status_bar_area] =
      Layout.split(full, :vertical, [
        {:length, 1},
        {:min, 0},
        {:length, 1}
      ])

    # Title bar: brand on the left, top-level tabs on the right
    [brand_area, tabs_area] =
      Layout.split(title_bar_area, :horizontal, [
        {:min, 0},
        {:length, 32}
      ])

    chrome = [
      {Panels.TitleBar.render(state), brand_area},
      {Panels.TabBar.render(state.ui.active_tab), tabs_area},
      {Panels.StatusBar.render(state), status_bar_area}
    ]

    maybe_add_popup(chrome ++ render_body(state, main), state, full)
  end

  defp render_body(%{ui: %{active_tab: :visualization}} = state, main) do
    Panels.Visualization.render_panes(state, main)
  end

  defp render_body(state, main) do
    # Top section (60%) + bottom section (40%)
    [top, bottom] =
      Layout.split(main, :vertical, [
        {:percentage, 60},
        {:percentage, 40}
      ])

    # Top: left sidebar (25%) + joints (75%)
    [left_col, joints_area] =
      Layout.split(top, :horizontal, [
        {:percentage, 25},
        {:percentage, 75}
      ])

    # Left sidebar: safety (55%) + commands (45%)
    [safety_area, commands_area] =
      Layout.split(left_col, :vertical, [
        {:percentage, 55},
        {:percentage, 45}
      ])

    # Bottom: events (55%) + parameters (45%)
    [events_area, params_area] =
      Layout.split(bottom, :horizontal, [
        {:percentage, 55},
        {:percentage, 45}
      ])

    [
      {Panels.Safety.render(state, state.ui.active_panel == :safety), safety_area},
      {Panels.Commands.render(state, state.ui.active_panel == :commands), commands_area},
      {Panels.Joints.render(state, state.ui.active_panel == :joints), joints_area}
    ] ++
      Panels.Events.render_panes(state, state.ui.active_panel == :events, events_area) ++
      [{Panels.Parameters.render(state, state.ui.active_panel == :parameters), params_area}]
  end

  # ── Update — popup intercepts ────────────────────────────────

  @impl true
  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{show_help?: true}} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.scroll_help_down(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{show_help?: true}} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.scroll_help_up(state)}
  end

  def update({:event, %Event.Key{kind: "press"}}, %{ui: %{show_help?: true}} = state) do
    {:noreply, State.toggle_help(state)}
  end

  def update(
        {:event, %Event.Key{code: "y", kind: "press"}},
        %{safety: %{confirm_force_disarm?: true}} = state
      ) do
    Robot.force_disarm(state.robot, state.node)
    {:noreply, State.dismiss_force_disarm(state)}
  end

  def update(
        {:event, %Event.Key{code: "n", kind: "press"}},
        %{safety: %{confirm_force_disarm?: true}} = state
      ) do
    {:noreply, State.dismiss_force_disarm(state)}
  end

  def update(
        {:event, %Event.Key{kind: "press"}},
        %{safety: %{confirm_force_disarm?: true}} = state
      ) do
    {:noreply, state}
  end

  def update({:event, %Event.Key{kind: "press"}}, %{events: %{show_detail?: true}} = state) do
    {:noreply, State.dismiss_event_detail(state)}
  end

  # ── Update — global keys ─────────────────────────────────────

  def update({:event, %Event.Key{code: "q", kind: "press"}}, state) do
    {:stop, state}
  end

  def update({:event, %Event.Key{code: "]", kind: "press"}}, state) do
    {:noreply, State.next_tab(state)}
  end

  def update({:event, %Event.Key{code: "[", kind: "press"}}, state) do
    {:noreply, State.prev_tab(state)}
  end

  # Visualization-tab camera controls.
  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      )
      when code in ["left", "h"] do
    {:noreply, State.orbit_camera(state, -@viz_orbit, 0.0)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      )
      when code in ["right", "l"] do
    {:noreply, State.orbit_camera(state, @viz_orbit, 0.0)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      )
      when code in ["up", "k"] do
    {:noreply, State.orbit_camera(state, 0.0, @viz_orbit)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      )
      when code in ["down", "j"] do
    {:noreply, State.orbit_camera(state, 0.0, -@viz_orbit)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      )
      when code in ["+", "="] do
    {:noreply, State.zoom_camera(state, -@viz_zoom)}
  end

  def update(
        {:event, %Event.Key{code: "-", kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      ) do
    {:noreply, State.zoom_camera(state, @viz_zoom)}
  end

  def update(
        {:event, %Event.Key{code: "r", kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      ) do
    {:noreply, State.reset_camera(state)}
  end

  def update(
        {:event, %Event.Key{code: "m", kind: "press"}},
        %{ui: %{active_tab: :visualization}} = state
      ) do
    {:noreply, State.cycle_render_mode(state)}
  end

  def update(
        {:event, %Event.Key{code: "tab", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    {:noreply, State.focus_next_arg(state)}
  end

  def update(
        {:event, %Event.Key{code: "back_tab", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    {:noreply, State.focus_prev_arg(state)}
  end

  def update(
        {:event, %Event.Key{code: "tab", kind: "press"}},
        %{ui: %{active_tab: :control}} = state
      ) do
    {:noreply, State.cycle_panel(state)}
  end

  def update(
        {:event, %Event.Key{code: "back_tab", kind: "press"}},
        %{ui: %{active_tab: :control}} = state
      ) do
    {:noreply, State.cycle_panel_back(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :control}, commands: %{edit_mode?: false}} = state
      )
      when code in ["1", "2", "3", "4", "5"] do
    panel = State.panel_at(String.to_integer(code))
    {:noreply, State.jump_to_panel(state, panel)}
  end

  def update({:event, %Event.Key{code: "?", kind: "press"}}, state) do
    {:noreply, State.toggle_help(state)}
  end

  def update({:event, %Event.Key{code: "a", kind: "press"}}, state) do
    Robot.arm(state.robot, state.node)
    {:noreply, state}
  end

  def update({:event, %Event.Key{code: "d", kind: "press"}}, state) do
    Robot.disarm(state.robot, state.node)
    {:noreply, state}
  end

  def update({:event, %Event.Key{code: "f", kind: "press"}}, state) do
    if state.safety.state == :error do
      {:noreply, State.show_force_disarm(state)}
    else
      {:noreply, state}
    end
  end

  # ── Update — events panel keys ───────────────────────────────

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :events}} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.scroll_down(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :events}} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.scroll_up(state)}
  end

  def update(
        {:event, %Event.Key{code: "p", kind: "press"}},
        %{ui: %{active_panel: :events}} = state
      ) do
    {:noreply, State.toggle_events_pause(state)}
  end

  def update(
        {:event, %Event.Key{code: "c", kind: "press"}},
        %{ui: %{active_panel: :events}} = state
      ) do
    {:noreply, State.clear_events(state)}
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{ui: %{active_panel: :events}} = state
      ) do
    if State.selected_event(state) do
      {:noreply, State.toggle_event_detail(state)}
    else
      {:noreply, state}
    end
  end

  # ── Update — commands panel: argument-edit mode ──────────────
  # These clauses run only when the user has entered edit mode on a
  # command with arguments (Enter from the list view enters edit mode
  # when the selected command has args). Keep them above the list-view
  # clauses so they take precedence.

  def update(
        {:event, %Event.Key{code: "esc", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    {:noreply, State.exit_command_edit_mode(state)}
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    execute_selected_command(state)
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      )
      when code in ["tab", "down"] do
    {:noreply, State.focus_next_arg(state)}
  end

  def update(
        {:event, %Event.Key{code: "up", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    {:noreply, State.focus_prev_arg(state)}
  end

  def update(
        {:event, %Event.Key{code: "backspace", kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      ) do
    {:noreply, State.backspace_focused_arg(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      )
      when code in ["left", "right", "h", "l"] do
    handle_arg_horizontal_key(state, code)
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :commands}, commands: %{edit_mode?: true}} = state
      )
      when byte_size(code) == 1 do
    {:noreply, State.append_to_focused_arg(state, code)}
  end

  # ── Update — commands panel: list view ───────────────────────

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :commands}} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_command(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :commands}} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_command(state)}
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{ui: %{active_panel: :commands}} = state
      ) do
    case State.selected_command(state) do
      %{arguments: [_ | _]} -> {:noreply, State.enter_command_edit_mode(state)}
      _ -> execute_selected_command(state)
    end
  end

  # ── Update — joints panel keys ───────────────────────────────

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_joint(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_joint(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["l", "right"] do
    adjust_selected_joint(state, :increase, 1)
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["h", "left"] do
    adjust_selected_joint(state, :decrease, 1)
  end

  def update(
        {:event, %Event.Key{code: "L", kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      ) do
    adjust_selected_joint(state, :increase, 10)
  end

  def update(
        {:event, %Event.Key{code: "H", kind: "press"}},
        %{ui: %{active_panel: :joints}} = state
      ) do
    adjust_selected_joint(state, :decrease, 10)
  end

  # ── Update — parameters panel keys ───────────────────────────

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      )
      when code in ["j", "down"] do
    {:noreply, State.select_next_param(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      )
      when code in ["k", "up"] do
    {:noreply, State.select_prev_param(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      )
      when code in ["l", "right"] do
    adjust_selected_param(state, :increase, 1)
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      )
      when code in ["h", "left"] do
    adjust_selected_param(state, :decrease, 1)
  end

  def update(
        {:event, %Event.Key{code: "L", kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      ) do
    adjust_selected_param(state, :increase, 10)
  end

  def update(
        {:event, %Event.Key{code: "H", kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      ) do
    adjust_selected_param(state, :decrease, 10)
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      ) do
    toggle_selected_param(state)
  end

  def update(
        {:event, %Event.Key{code: "t", kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      ) do
    state = State.cycle_parameter_tab(state)
    {:noreply, refresh_selected_tab(state)}
  end

  # ── Update — PubSub + async info messages ────────────────────

  def update({:info, {:bb, [:state_machine | _] = path, msg}}, state) do
    safety_state = Robot.safety_state(state.robot, state.node)
    runtime_state = Robot.runtime_state(state.robot, state.node)

    state =
      state
      |> State.update_safety(safety_state, runtime_state)
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  # Sensor messages are the high-rate path. Update state but suppress the
  # immediate render (render?: false) and flag a pending render; the
  # :sensor_flush tick armed by subscriptions/1 performs one coalesced frame.
  def update({:info, {:bb, [:sensor | _] = path, %{payload: payload} = msg}}, state) do
    positions =
      case payload do
        %{names: names, positions: pos} -> Enum.zip(names, pos) |> Map.new()
        _ -> %{}
      end

    state =
      state
      |> State.update_positions(positions)
      |> State.update_power(payload)
      |> State.append_event(path, msg)
      |> State.mark_render_pending()

    {:noreply, state, render?: false}
  end

  def update({:info, {:bb, [:param | _] = path, msg}}, state) do
    parameters = Robot.list_parameters(state.robot, [], state.node)

    state =
      state
      |> State.update_parameters(parameters)
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  # Consumer-renderer seam: a path matching a registered renderer prefix
  # (longest-prefix match, like a routing table) is handed off to the consumer's
  # module rather than pattern-matched here — bb_tui never inspects the payload's
  # struct. The renderer's `observed/2` (if exported) feeds the at-a-glance
  # status-bar readout; the event row is rendered later from the same renderer
  # (see `BB.TUI.Panels.Events`). The render is coalesced like sensors
  # (render?: false + the :sensor_flush tick) so a fast consumer stays smooth.
  # Falls through to the catch-all below when no renderer matches.
  def update({:info, {:bb, path, %{payload: payload} = msg}}, state) do
    case State.renderer_for(state, path) do
      nil ->
        {:noreply, State.append_event(state, path, msg)}

      renderer ->
        state =
          state
          |> maybe_put_observed(renderer, path, payload)
          |> State.append_event(path, msg)
          |> State.mark_render_pending()

        {:noreply, state, render?: false}
    end
  end

  # Everything else we subscribe to but don't model in dedicated state —
  # notably `[:safety, :error]` hardware-error reports and `[:estimator | _]`
  # odometry/pose — lands here and is surfaced in the event log. Safety *state*
  # transitions arrive separately on `[:state_machine]` (see above), so the
  # badge already reflects an error before its detail shows up here.
  def update({:info, {:bb, path, msg}}, state) do
    {:noreply, State.append_event(state, path, msg)}
  end

  def update({:info, {:command_result, result}}, state) do
    {:noreply, State.set_command_result(state, result)}
  end

  def update({:info, :throbber_tick}, state) do
    {:noreply, State.tick_throbber(state)}
  end

  # Coalesced sensor render: clear the pending flag and let the default
  # render?: true draw the single freshest frame. The next subscriptions/1
  # reconcile then drops :sensor_flush until the next sensor message.
  def update({:info, :sensor_flush}, state) do
    {:noreply, State.clear_render_pending(state)}
  end

  # ── Update — catch-all ───────────────────────────────────────

  def update(_msg, state), do: {:noreply, state}

  # ── Subscriptions ────────────────────────────────────────────

  @impl true
  def subscriptions(state) do
    throbber_subscriptions(state) ++ sensor_flush_subscriptions(state)
  end

  defp throbber_subscriptions(state) do
    if needs_throbber?(state) do
      [Subscription.interval(:throbber, 100, :throbber_tick)]
    else
      []
    end
  end

  # A one-shot armed only while a sensor render is pending. Repeated sensor
  # messages don't reset the armed timer (the reducer reconciles an equal
  # :once subscription as a no-op); once it fires and clears the flag, the
  # next reconcile removes it — so an idle TUI carries no flush timer.
  defp sensor_flush_subscriptions(%State{throttle: %{render_pending?: true, flush_ms: ms}}) do
    [Subscription.once(:sensor_flush, ms, :sensor_flush)]
  end

  defp sensor_flush_subscriptions(_state), do: []

  # ── Helpers ──────────────────────────────────────────────────

  # Feed the status-bar readout from the consumer's optional `observed/2`. The
  # callback is optional (`@optional_callbacks observed: 2`), so skip the call
  # entirely when the renderer doesn't export it. A `nil` return (or a
  # non-tuple) means "no slot for this payload" — leave `state.observed` as is.
  defp maybe_put_observed(state, renderer, path, payload) do
    # `observed/2` is optional. Force the module loaded before checking — under
    # Elixir 1.19+ module loading is lazier, so `function_exported?/3` can return
    # false for a not-yet-loaded module and the optional callback would be silently
    # skipped (it passed on 1.18 only because the module happened to be loaded).
    if Code.ensure_loaded?(renderer) and function_exported?(renderer, :observed, 2) do
      case renderer.observed(path, payload) do
        {slot_key, display, meta} ->
          State.put_observed(state, slot_key, %{display: display, meta: meta})

        _ ->
          state
      end
    else
      state
    end
  end

  defp needs_throbber?(%State{safety: %{state: :disarming}}), do: true
  defp needs_throbber?(%State{commands: %{executing: marker}}) when marker != nil, do: true
  defp needs_throbber?(_), do: false

  defp maybe_add_popup(panels, %{ui: %{show_help?: true, help_scroll_offset: offset}}, full) do
    panels ++ [{Panels.Help.render(offset), full}]
  end

  defp maybe_add_popup(panels, %{safety: %{confirm_force_disarm?: true}}, full) do
    panels ++ [{Panels.ForceDisarm.render(), full}]
  end

  defp maybe_add_popup(panels, %{events: %{show_detail?: true}} = state, full) do
    case State.selected_event(state) do
      nil -> panels
      event -> panels ++ [{Panels.EventDetail.render(event), full}]
    end
  end

  defp maybe_add_popup(panels, %{commands: %{edit_mode?: true}} = state, full) do
    case Panels.CommandEdit.render(state) do
      nil -> panels
      popup -> panels ++ [{popup, full}]
    end
  end

  defp maybe_add_popup(panels, _state, _full), do: panels

  defp adjust_selected_joint(state, _direction, _multiplier)
       when state.safety.state not in [:armed, :disarming] do
    {:noreply, state}
  end

  defp adjust_selected_joint(state, direction, multiplier) do
    name = State.selected_joint_name(state)

    case name && Map.get(state.joints.entries, name) do
      nil ->
        {:noreply, state}

      %{position: nil} ->
        {:noreply, state}

      %{position: pos, joint: joint} ->
        step = State.joint_step(joint) * multiplier

        new_pos =
          case direction do
            :increase -> pos + step
            :decrease -> pos - step
          end
          |> State.clamp_position(joint)

        actuator = find_actuator_for_joint(state.robot_struct, name)
        state = State.set_joint_target(state, name, new_pos)

        if actuator do
          Robot.set_actuator(state.robot, actuator, new_pos, state.node)
          {:noreply, state}
        else
          publish_simulated_position(state.robot, name, new_pos, state.node)
          {:noreply, State.set_joint_position(state, name, new_pos)}
        end
    end
  end

  defp publish_simulated_position(robot, joint_name, position, node) do
    {:ok, msg} =
      BB.Message.new(BB.Message.Sensor.JointState, :simulated,
        names: [joint_name],
        positions: [position * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    Robot.publish(robot, [:sensor, :simulated], msg, node)
  end

  defp find_actuator_for_joint(%{actuators: actuators}, joint_name) do
    actuators
    |> Enum.find(fn {_name, info} -> info.joint == joint_name end)
    |> case do
      {actuator_name, _info} -> actuator_name
      nil -> nil
    end
  end

  defp find_actuator_for_joint(_, _joint_name), do: nil

  defp refresh_selected_tab(state) do
    case State.selected_parameter_tab(state) do
      :local ->
        state

      {:bridge, name} ->
        payload =
          case Robot.list_remote_parameters(state.robot, name, state.node) do
            {:ok, params} -> params
            {:error, _} = error -> error
          end

        State.put_remote_parameters(state, name, payload)
    end
  end

  defp adjust_selected_param(state, direction, multiplier) do
    case State.selected_parameter_tab(state) do
      :local -> adjust_local_param(state, direction, multiplier)
      {:bridge, name} -> adjust_remote_param(state, name, direction, multiplier)
    end
  end

  defp adjust_local_param(state, direction, multiplier) do
    case State.selected_param(state) do
      {path, value} when is_integer(value) ->
        bounds = State.parameter_bounds(state, path)
        step = integer_step(bounds) * multiplier
        new_value = State.clamp_to_bounds(apply_step(value, direction, step), bounds)
        Robot.set_parameter(state.robot, path, new_value, state.node)
        {:noreply, state}

      {path, value} when is_float(value) ->
        bounds = State.parameter_bounds(state, path)
        step = float_step(bounds) * multiplier
        new_value = State.clamp_to_bounds(apply_step(value, direction, step), bounds)
        Robot.set_parameter(state.robot, path, new_value, state.node)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp adjust_remote_param(state, bridge_name, direction, multiplier) do
    case State.selected_remote_param(state) do
      %{value: value} = param when is_integer(value) ->
        bounds = State.remote_param_bounds(param)
        step = integer_step(bounds) * multiplier
        new_value = State.clamp_to_bounds(apply_step(value, direction, step), bounds)
        dispatch_remote_set(state, bridge_name, param, new_value)

      %{value: value} = param when is_float(value) ->
        bounds = State.remote_param_bounds(param)
        step = float_step(bounds) * multiplier
        new_value = State.clamp_to_bounds(apply_step(value, direction, step), bounds)
        dispatch_remote_set(state, bridge_name, param, new_value)

      _ ->
        {:noreply, state}
    end
  end

  defp dispatch_remote_set(state, bridge_name, param, new_value) do
    id = State.remote_param_id(param)

    case Robot.set_remote_parameter(state.robot, bridge_name, id, new_value, state.node) do
      :ok -> {:noreply, refresh_selected_tab(state)}
      {:error, _reason} -> {:noreply, state}
    end
  end

  defp integer_step({min, max}) when is_integer(min) and is_integer(max),
    do: max(div(max - min, 100), 1)

  defp integer_step(_), do: 1

  defp float_step({min, max}) when is_number(min) and is_number(max), do: (max - min) / 100
  defp float_step(_), do: 0.1

  defp apply_step(value, :increase, step), do: value + step
  defp apply_step(value, :decrease, step), do: value - step

  defp toggle_selected_param(state) do
    case State.selected_parameter_tab(state) do
      :local -> toggle_local_param(state)
      {:bridge, name} -> toggle_remote_param(state, name)
    end
  end

  defp toggle_local_param(state) do
    case State.selected_param(state) do
      {path, value} when is_boolean(value) ->
        Robot.set_parameter(state.robot, path, !value, state.node)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp toggle_remote_param(state, bridge_name) do
    case State.selected_remote_param(state) do
      %{value: value} = param when is_boolean(value) ->
        dispatch_remote_set(state, bridge_name, param, !value)

      _ ->
        {:noreply, state}
    end
  end

  defp handle_arg_horizontal_key(state, code) do
    case State.focused_arg_enum_values(state) do
      [_ | _] ->
        direction = if code in ["right", "l"], do: :next, else: :prev
        {:noreply, State.cycle_focused_enum(state, direction)}

      _ when byte_size(code) == 1 ->
        {:noreply, State.append_to_focused_arg(state, code)}

      _ ->
        {:noreply, state}
    end
  end

  defp execute_selected_command(%State{commands: %{available: commands, selected: idx}} = state) do
    case Enum.at(commands, idx) do
      nil ->
        {:noreply, state}

      cmd ->
        if Panels.Commands.command_ready?(cmd, state.safety.runtime) and
             state.commands.executing == nil do
          args = State.parsed_args_for_selected(state)

          {:noreply, State.start_command(State.exit_command_edit_mode(state), :running),
           commands: [execute_command_command(state, cmd, args)]}
        else
          {:noreply, state}
        end
    end
  end

  defp execute_command_command(%State{robot: robot, node: node}, cmd, args) do
    name = cmd.name

    Command.async(
      fn -> wait_for_command_result(robot, name, args, node) end,
      fn result -> {:command_result, result} end
    )
  end

  defp wait_for_command_result(robot, name, args, node) do
    case Robot.execute_command(robot, name, args, node) do
      {:ok, cmd_pid} -> await_command(cmd_pid)
      {:error, reason} -> {:error, reason}
    end
  end

  # BB.Command.await/2 traps `:exit, {:noproc, _}` and falls back to the
  # command's ResultCache, so it survives the race where a fast handler
  # (e.g. a synchronous {:stop, :normal, _}) terminates between
  # `Robot.execute_command/4` returning the pid and us awaiting on it.
  # The earlier Process.monitor approach surfaced that race as a
  # spurious {:error, :noproc}; await also enforces a timeout, so we no
  # longer need a separate Command.send_after backstop.
  #
  # Unwrap {:command_failed, reason} at the boundary so the panel shows
  # the bare reason (`:timeout`, `:noproc`, etc.) consistently.
  defp await_command(cmd_pid) do
    case BB.Command.await(cmd_pid, @command_timeout) do
      {:ok, result} -> {:ok, result}
      {:ok, result, _opts} -> {:ok, result}
      {:error, {:command_failed, reason}} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end
end
