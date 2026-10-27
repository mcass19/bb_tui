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
    * `subscriptions/1` — declares the throbber tick interval while
      the safety panel's disarming spinner animates, and a one-shot
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

  ex_ratatui also merges renders while the runtime's mailbox is busy,
  which covers bursts and backlogs. The flush tick still matters for a
  sensor stream the dashboard keeps up with: there the mailbox is empty
  between messages and the runtime would draw one frame per message.

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

  Every call that waits on one of the robot's processes runs through
  `Command.async/2`, so the process that owns the terminal never blocks
  on it: arming, disarming and force-disarming (`{:robot_write, _, _}`),
  which may run a whole arm/disarm command; parameter writes
  (`{:robot_write, _, _}`) and bridge reads and writes
  (`{:remote_param_set, _, _, _}`, `{:remote_parameters, _, _}`); command
  execution, awaiting and cancelling; and jogs via
  `Robot.set_actuator/4`, whose `:pubsub` delivery blocks on the
  actuator's answer (`{:actuator_result, _, _}`). An accepted write is
  reported by the robot's own events; a refusal lands in the event log
  under the path the write was aimed at. Only `Robot.publish/4` (the
  simulated-joint fallback) and reads backed by ETS or the runtime stay
  inline.
  Each actuator has at most one jog in flight: targets that arrive
  meanwhile are parked, latest wins, and sent once it is answered
  (see `BB.TUI.State.request_jog/3`).

  ## Cancelling a running command

  `BB.Command.await/2` is called with `:infinity`, so a continuous
  command — one that only returns when it stops or is cancelled — is
  never reported as timed out while it is still running. Runaways stay
  bounded by the command's own DSL `timeout`. The escape hatch is `c`
  in the commands panel, which cancels the selected command's newest
  execution and resolves the await.

  The panel shows every command running on the robot, not only the one
  this dashboard started — automation, another SSH session or a browser
  tab can start commands too — so `c` works on those as well. The listing
  comes from `BB.Command.list/1` and is refreshed on every `[:command | _]`
  event and when this dashboard's own command starts or finishes;
  cancellation goes by execution id through `BB.Command.cancel/2`.
  """

  use ExRatatui.App, runtime: :reducer

  alias BB.Error.State.UnsupportedCommand
  alias BB.Math.Transform
  alias BB.Math.Transform2D
  alias BB.Robot.Joint
  alias BB.TUI.Errors
  alias BB.TUI.Panels
  alias BB.TUI.Pilot
  alias BB.TUI.Robot
  alias BB.TUI.State
  alias ExRatatui.Command
  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Subscription

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

    extensions = build_extensions!(opts, node)

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

    Robot.subscribe(robot, paths ++ State.Extensions.subscribe_paths(extensions, paths), node)

    renderers = Keyword.get(opts, :renderers, %{})

    robot_struct = Robot.get_robot(robot, node)
    configurations = Robot.configurations(robot, node)

    joints =
      robot_struct
      |> BB.Robot.joints_in_order()
      |> Enum.filter(&Joint.movable?/1)
      |> Map.new(
        &{&1.name,
         %{joint: &1, position: configurations[&1.name] || default_configuration(&1), target: nil}}
      )

    commands = Robot.discover_commands(robot, node)
    bridges = Robot.list_bridges(robot, node)
    simulation = Robot.simulation_mode(robot, node)
    controllers = Robot.list_controllers(robot, node)

    # In simulation every actuator runs as `BB.Sim.Actuator`, which takes
    # position commands whatever its declared driver accepts.
    payloads = if simulation, do: %{}, else: Robot.command_payloads(robot, node)

    state =
      %State{
        robot: robot,
        robot_struct: robot_struct,
        node: node,
        simulation: simulation,
        safety: %State.Safety{
          state: Robot.safety_state(robot, node),
          runtime: Robot.runtime_state(robot, node)
        },
        joints: %State.Joints{entries: joints, payloads: payloads},
        extensions: extensions,
        commands: %State.Commands{available: commands},
        controllers: %State.Controllers{
          list: controllers,
          alive: Robot.controllers_alive(robot, Enum.map(controllers, & &1.name), node)
        },
        renderers: renderers
      }
      |> State.put_running_commands(Robot.running_commands(robot, node))
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

  # The `:extensions` option, merged. A drive's functions are checked where
  # they will run — on the robot's node under `:node` — since the compile-time
  # check skips modules it can't load.
  defp build_extensions!(opts, node) do
    with {:ok, extensions} <- State.Extensions.build(Keyword.get(opts, :extensions, [])),
         :ok <- drive_exported(extensions.drive, node) do
      extensions
    else
      {:error, message} -> raise ArgumentError, "invalid :extensions — " <> message
    end
  end

  defp drive_exported(nil, _node), do: :ok

  defp drive_exported(%{publish: {pmod, pfun}, stop: {smod, sfun}}, node) do
    missing =
      for {mod, fun, arity} <- [{pmod, pfun, 3}, {smod, sfun, 1}],
          not Robot.exported?(mod, fun, arity, node),
          do: "#{inspect(mod)}.#{fun}/#{arity}"

    case missing do
      [] -> :ok
      _ -> {:error, "drive functions not found on the robot's node: #{Enum.join(missing, ", ")}"}
    end
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
    tabs = State.tab_labels(state)

    [brand_area, tabs_area] =
      Layout.split(title_bar_area, :horizontal, [
        {:min, 0},
        {:length, Panels.TabBar.width(tabs)}
      ])

    chrome = [
      {Panels.TitleBar.render(state), brand_area},
      {Panels.TabBar.render(tabs, state.ui.active_tab), tabs_area},
      {Panels.StatusBar.render(state), status_bar_area}
    ]

    {hint, main} = split_hint(state, main)
    maybe_add_popup(chrome ++ hint ++ render_body(state, main), state, full)
  end

  # An extension's hint for the robot's runtime state takes a line under the
  # title bar; without one the layout is unchanged.
  defp split_hint(state, main) do
    case State.Extensions.hint(state.extensions, state.safety.runtime) do
      nil ->
        {[], main}

      hint ->
        [hint_area, rest] = Layout.split(main, :vertical, [{:length, 1}, {:min, 0}])
        {[{Panels.Hint.render(hint), hint_area}], rest}
    end
  end

  defp render_body(
         %{ui: %{active_tab: {:extension, :drive}}, extensions: %{drive: %{}}} = state,
         main
       ) do
    Panels.Drive.render(state, main, now_ms())
  end

  defp render_body(%{ui: %{active_tab: {:extension, tab}}} = state, main) do
    Panels.Extension.render_tab(state, tab, main, now_ms())
  end

  defp render_body(%{ui: %{active_tab: :controllers}} = state, main) do
    [{Panels.Controllers.render(state), main}]
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
    {:noreply, State.dismiss_force_disarm(state),
     commands: [safety_write(state, :force_disarm, &Robot.force_disarm/2)]}
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

  # The inspect popup: Enter asks again, any other key closes it.
  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{controllers: %{detail: %{name: name}}} = state
      ) do
    inspect_controller(state, name)
  end

  def update({:event, %Event.Key{kind: "press"}}, %{controllers: %{detail: %{}}} = state) do
    {:noreply, put_in(state.controllers.detail, nil)}
  end

  def update({:event, %Event.Key{kind: "press"}}, %{events: %{show_detail?: true}} = state) do
    {:noreply, State.dismiss_event_detail(state)}
  end

  # ── Update — parameters inline edit (modal while open) ───────
  # These sit ahead of the global keys on purpose: a letter typed into
  # the buffer must append, not quit, arm, or switch panels.

  def update(
        {:event, %Event.Key{code: "esc", kind: "press"}},
        %{parameters: %{editing: %{}}} = state
      ) do
    {:noreply, State.cancel_param_edit(state)}
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{parameters: %{editing: %{path: path, buffer: buffer}}} = state
      ) do
    {:noreply, State.cancel_param_edit(state),
     commands: [parameter_write(state, path, State.parse_param_input(buffer))]}
  end

  def update(
        {:event, %Event.Key{code: "backspace", kind: "press"}},
        %{parameters: %{editing: %{}}} = state
      ) do
    {:noreply, State.backspace_param_buffer(state)}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{parameters: %{editing: %{}}} = state
      )
      when byte_size(code) == 1 do
    {:noreply, State.append_to_param_buffer(state, code)}
  end

  def update({:event, %Event.Key{kind: "press"}}, %{parameters: %{editing: %{}}} = state) do
    {:noreply, state}
  end

  # ── Update — global keys ─────────────────────────────────────

  def update({:event, %Event.Key{code: "q", kind: "press"}}, state) do
    {:stop, halt_motion(state)}
  end

  # Leaving the Drive tab lets go of the drive keys: driving is only ever
  # done with the pad in view.
  def update({:event, %Event.Key{code: "]", kind: "press"}}, state) do
    {:noreply, state |> State.next_tab() |> halt_drive_off_tab()}
  end

  def update({:event, %Event.Key{code: "[", kind: "press"}}, state) do
    {:noreply, state |> State.prev_tab() |> halt_drive_off_tab()}
  end

  # The window lost focus: its key releases won't reach us.
  def update({:event, %Event.FocusLost{}}, state) do
    {:noreply, halt_motion(state)}
  end

  # ── Update — driving ─────────────────────────────────────────

  # Only the session holding the pilot lease drives; without it the pad
  # says how to take it.
  def update(
        {:event, %Event.Key{code: code, kind: kind}},
        %{ui: %{active_tab: {:extension, :drive}}, extensions: %{drive: %{}}} = state
      )
      when code in ["up", "down", "left", "right"] and kind in ["press", "repeat"] do
    state = observe_lease(state)

    case state.drive.lease do
      :mine ->
        state
        |> Map.update!(:drive, &State.Drive.press(&1, code, now_ms()))
        |> step_drive()

      _not_mine ->
        {:noreply, state}
    end
  end

  # `t` takes the wheel, or hands it back (stopping first).
  def update(
        {:event, %Event.Key{code: "t", kind: "press"}},
        %{ui: %{active_tab: {:extension, :drive}}, extensions: %{drive: %{}}} = state
      ) do
    toggle_lease(state)
  end

  # Another session won the lease after a network split healed: this one
  # stops at once.
  def update({:info, {:global_name_conflict, {Pilot, _robot}}}, state) do
    {:noreply, state |> halt_motion() |> observe_lease()}
  end

  # Keeps "driven by …" current while the Drive tab is on screen.
  def update({:info, :pilot_check}, state) do
    checked = observe_lease(state)
    {:noreply, checked, render?: checked.drive.lease != state.drive.lease}
  end

  def update(
        {:event, %Event.Key{code: code, kind: "release"}},
        %{ui: %{active_tab: {:extension, :drive}}, extensions: %{drive: %{}}} = state
      )
      when code in ["up", "down", "left", "right"] do
    state
    |> Map.update!(:drive, &State.Drive.release(&1, code))
    |> step_drive()
  end

  def update({:info, :drive_tick}, state), do: step_drive(state, render?: false)

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

  # Terminal transports report shift+tab as crossterm's "back_tab";
  # browser transports (phoenix_ex_ratatui) report it as "tab" with a
  # "shift" modifier. Normalize before any plain "tab" clause can match.
  def update(
        {:event, %Event.Key{code: "tab", modifiers: ["shift"], kind: "press"} = key},
        state
      ) do
    update({:event, %{key | code: "back_tab", modifiers: []}}, state)
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
    {:noreply, state, commands: [safety_write(state, :arm, &Robot.arm/2)]}
  end

  def update({:event, %Event.Key{code: "d", kind: "press"}}, state) do
    {:noreply, state, commands: [safety_write(state, :disarm, &Robot.disarm/2)]}
  end

  def update({:event, %Event.Key{code: "f", kind: "press"}}, state) do
    if state.safety.state == :error do
      {:noreply, State.show_force_disarm(state)}
    else
      {:noreply, state}
    end
  end

  # ── Update — extension keys ──────────────────────────────────

  # A key an extension bound runs its command from any tab, through the same
  # path as the commands panel; a refusal (wrong state, already running)
  # comes back as that command's result.
  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when is_map_key(state.extensions.bound, code) do
    run_bound_command(state, Map.fetch!(state.extensions.bound, code))
  end

  # Space freezes an extension tab's charts — and stops recording — so a
  # moment (a fall, a spike) stays on screen; space again lets them run.
  def update(
        {:event, %Event.Key{code: " ", kind: "press"}},
        %{ui: %{active_tab: {:extension, _}}} = state
      ) do
    {:noreply, %{state | extensions: State.Extensions.toggle_freeze(state.extensions, now_ms())}}
  end

  # The Control Panel's panel keys don't reach past their tab: on an
  # extension tab, `h`/`l` must not jog a joint nobody can see.
  def update({:event, %Event.Key{kind: "press"}}, %{ui: %{active_tab: {:extension, _}}} = state) do
    {:noreply, state}
  end

  # ── Update — controllers tab ─────────────────────────────────

  def update(
        {:event, %Event.Key{code: code, kind: "press"}},
        %{ui: %{active_tab: :controllers}} = state
      )
      when code in ["j", "down", "k", "up"] do
    delta = if code in ["j", "down"], do: 1, else: -1
    {:noreply, %{state | controllers: State.Controllers.move(state.controllers, delta)}}
  end

  def update(
        {:event, %Event.Key{code: "enter", kind: "press"}},
        %{ui: %{active_tab: :controllers}} = state
      ) do
    inspect_controller(state, State.Controllers.selected_name(state.controllers))
  end

  # As on an extension tab, the Control Panel's panel keys stay on their tab.
  def update({:event, %Event.Key{kind: "press"}}, %{ui: %{active_tab: :controllers}} = state) do
    {:noreply, state}
  end

  # A check only goes out while the tab is up; a reply arriving after it was
  # left still lands, so the tab is current when it comes back.
  def update({:info, :controllers_check}, state) do
    %{robot: robot, node: node} = state
    names = Enum.map(state.controllers.list, & &1.name)

    check =
      Command.async(
        fn -> Robot.controllers_alive(robot, names, node) end,
        &{:controllers_alive, &1}
      )

    {:noreply, state, commands: [check], render?: false}
  end

  def update({:info, {:controllers_alive, alive}}, state) do
    {:noreply, put_in(state.controllers.alive, alive), render?: alive != state.controllers.alive}
  end

  # A popup closed before its answer came back stays closed.
  def update({:info, {:controller_detail, name, result}}, state) do
    case state.controllers.detail do
      %{name: ^name} -> {:noreply, put_in(state.controllers.detail.result, result)}
      _closed -> {:noreply, state, render?: false}
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

  # Below the edit-mode clauses, so a `c` typed into an argument stays text:
  # a command started elsewhere can be running while this dashboard edits.
  # Cancels the selected command's newest execution, whoever started it; the
  # outcome arrives as that command's `[:command | _]` event.
  def update(
        {:event, %Event.Key{code: "c", kind: "press"}},
        %{ui: %{active_panel: :commands}} = state
      ) do
    case State.selected_running_execution(state) do
      %{execution_id: execution_id} ->
        {:noreply, state, commands: [cancel_command_command(state, execution_id)]}

      nil ->
        {:noreply, state}
    end
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

  # A repeat steps like a press: terminals that report autorepeat as its own
  # kind would otherwise jog once per hold.
  def update(
        {:event, %Event.Key{code: code, kind: kind}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["l", "right"] and kind in ["press", "repeat"] do
    adjust_selected_joint(state, :increase, 1)
  end

  def update(
        {:event, %Event.Key{code: code, kind: kind}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["h", "left"] and kind in ["press", "repeat"] do
    adjust_selected_joint(state, :decrease, 1)
  end

  def update(
        {:event, %Event.Key{code: "L", kind: kind}},
        %{ui: %{active_panel: :joints}} = state
      )
      when kind in ["press", "repeat"] do
    adjust_selected_joint(state, :increase, 10)
  end

  def update(
        {:event, %Event.Key{code: "H", kind: kind}},
        %{ui: %{active_panel: :joints}} = state
      )
      when kind in ["press", "repeat"] do
    adjust_selected_joint(state, :decrease, 10)
  end

  # Letting go of a jog key stops a spinning joint at once.
  def update(
        {:event, %Event.Key{code: code, kind: "release"}},
        %{ui: %{active_panel: :joints}} = state
      )
      when code in ["h", "l", "H", "L", "left", "right"] do
    state = put_in(state.drive.mode, :release)
    {:noreply, halt_velocity_jog(state)}
  end

  # A tick already queued when the jog stopped.
  def update({:info, :velocity_jog_tick}, %State{joints: %{velocity_jog: nil}} = state),
    do: {:noreply, state, render?: false}

  def update({:info, :velocity_jog_tick}, state) do
    {commands, jog} =
      if velocity_jog_valid?(state),
        do: State.VelocityJog.tick(state.joints.velocity_jog, state.drive.mode, now_ms()),
        else: State.VelocityJog.halt(state.joints.velocity_jog)

    send_jog_commands(state, commands)
    {:noreply, put_in(state.joints.velocity_jog, jog), render?: jog != state.joints.velocity_jog}
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

  # A velocity-only joint spins only for the session holding the wheel.
  def update(
        {:event, %Event.Key{code: "t", kind: "press"}},
        %{ui: %{active_tab: :control, active_panel: :joints}} = state
      ) do
    if velocity_joint_selected?(state), do: toggle_lease(state), else: {:noreply, state}
  end

  def update(
        {:event, %Event.Key{code: "t", kind: "press"}},
        %{ui: %{active_panel: :parameters}} = state
      ) do
    state = State.cycle_parameter_tab(state)
    {:noreply, state, commands: refresh_selected_tab(state)}
  end

  # ── Update — PubSub + async info messages ────────────────────

  # Every PubSub message first feeds the extensions' `topic` sources, then
  # takes its usual path (see `update_bb/2`).
  def update({:info, {:bb, path, msg}} = info, state) do
    update_bb(info, observe_extension_topics(state, path, msg))
  end

  # The command is registered by now, so the listing includes it even before
  # its `:started` event arrives (or when `[:command]` isn't subscribed).
  def update({:info, {:command_started, {:ok, cmd_pid}}}, state) do
    state = State.put_running_commands(state, Robot.running_commands(state.robot, state.node))
    {:noreply, state, commands: [await_command_command(state, cmd_pid)]}
  end

  def update({:info, {:command_started, {:error, reason}}}, state) do
    {:noreply, State.set_command_result(state, {:error, reason})}
  end

  def update({:info, {:command_result, result}}, state) do
    state =
      state
      |> State.set_command_result(result)
      |> State.put_running_commands(Robot.running_commands(state.robot, state.node))

    {:noreply, state}
  end

  # Either answer frees the actuator's jog slot, sending the position parked
  # behind it if there is one (see `continue_jog/2`).
  #
  # Jog commands succeed silently — under key autorepeat there is one of
  # these per repeat, so skip the render. The joint's displayed position
  # moves on sensor feedback, not on acceptance.
  def update({:info, {:actuator_result, actuator, :ok}}, state) do
    {state, commands} = continue_jog(state, actuator)
    {:noreply, state, [render?: false] ++ commands}
  end

  # Anything else lands in the event log: a refusal (`NotArmed`, `StaleEpoch`,
  # …), an actuator that isn't running, a late answer (`CommandPending`, a
  # warning — the command is queued and will most likely be applied), or the
  # async runner's trapped exit from an actuator that crashed while handling
  # the command. Only a late answer keeps the joint's target: the others mean
  # the joint isn't going there, so the next jog steps from where it is.
  def update({:info, {:actuator_result, actuator, {:error, reason}}}, state) do
    {state, commands} =
      state
      |> State.append_event([:actuator, actuator], %{payload: %{error: reason}})
      |> forget_refused_target(actuator, reason)
      |> learn_payloads(actuator, reason)
      |> continue_jog(actuator)

    {:noreply, state, commands}
  end

  # The cancel's own answer carries nothing: the command's `[:command | _]`
  # events report what happened.
  def update({:info, :command_cancel_sent}, state), do: {:noreply, state, render?: false}

  # A write the robot accepted is reported by its own event (`[:state_machine]`
  # for safety, `[:param | _]` for parameters), so the answer itself is dropped
  # without a render. A refusal has nowhere else to go: it lands in the event
  # log under the path the write was aimed at.
  def update({:info, {:robot_write, path, {:error, reason}}}, state) do
    {:noreply, State.append_event(state, path, %{payload: %{error: reason}})}
  end

  def update({:info, {:robot_write, _path, _result}}, state),
    do: {:noreply, state, render?: false}

  # A bridge publishes no event for a write, so an accepted one re-fetches the
  # bridge's list to show the new value.
  def update({:info, {:remote_param_set, bridge, _id, :ok}}, state) do
    {:noreply, state, commands: [fetch_remote_parameters(state, bridge)], render?: false}
  end

  def update({:info, {:remote_param_set, bridge, id, {:error, reason}}}, state) do
    {:noreply, State.append_event(state, [:bridge, bridge, id], %{payload: %{error: reason}})}
  end

  def update({:info, {:remote_parameters, bridge, payload}}, state) do
    {:noreply, State.put_remote_parameters(state, bridge, payload)}
  end

  def update({:info, :throbber_tick}, state) do
    {:noreply, State.tick_throbber(state)}
  end

  # Coalesced sensor render: clear the pending flag and let the default
  # render?: true draw the single freshest frame. The next subscriptions/1
  # reconcile then drops :sensor_flush until the next sensor message.
  # One `:inspect` per controller per tick, skipping any whose last poll is
  # still out, so a slow controller never piles polls up.
  def update({:info, :poll_controllers}, state) do
    {due, extensions} = State.Extensions.start_polls(state.extensions, visible_controllers(state))
    commands = Enum.map(due, &inspect_controller_command(state, &1))
    {:noreply, %{state | extensions: extensions}, commands: commands, render?: false}
  end

  def update({:info, {:controller_state, name, result}}, state) do
    extensions = State.Extensions.finish_poll(state.extensions, name, result)
    changed? = extensions.values != state.extensions.values

    state =
      record_extensions(
        %{state | extensions: extensions},
        &(&1.type == :controller and &1.target == name)
      )

    {:noreply, state, render?: changed?}
  end

  def update({:info, :sensor_flush}, state) do
    {:noreply, State.clear_render_pending(state)}
  end

  # ── Update — catch-all ───────────────────────────────────────

  def update(_msg, state), do: {:noreply, state}

  # ── Subscriptions ────────────────────────────────────────────

  @impl true
  def subscriptions(state) do
    throbber_subscriptions(state) ++
      sensor_flush_subscriptions(state) ++
      controller_poll_subscriptions(state) ++
      drive_subscriptions(state) ++
      velocity_jog_subscriptions(state) ++
      pilot_subscriptions(state) ++ controllers_subscriptions(state)
  end

  # Running or not, checked every second while the Controllers tab is up.
  defp controllers_subscriptions(%State{ui: %{active_tab: :controllers}}),
    do: [Subscription.interval(:controllers_check, 1_000, :controllers_check)]

  defp controllers_subscriptions(_state), do: []

  # Checks a spinning joint's key often enough to stop it promptly.
  defp velocity_jog_subscriptions(%State{joints: %{velocity_jog: nil}}), do: []

  defp velocity_jog_subscriptions(_state),
    do: [Subscription.interval(:velocity_jog_tick, 50, :velocity_jog_tick)]

  # Ticks at the drive's rate for as long as a key is held or a stop is owed.
  defp drive_subscriptions(%State{extensions: %{drive: %{rate: rate}}} = state) do
    if State.Drive.active?(state.drive),
      do: [Subscription.interval(:drive_tick, div(1000, rate), :drive_tick)],
      else: []
  end

  defp drive_subscriptions(_state), do: []

  defp pilot_subscriptions(%State{
         ui: %{active_tab: {:extension, :drive}},
         extensions: %{drive: %{}}
       }),
       do: [Subscription.interval(:pilot_check, 1_000, :pilot_check)]

  defp pilot_subscriptions(%State{ui: %{active_tab: :control, active_panel: :joints}} = state) do
    if velocity_joint_selected?(state),
      do: [Subscription.interval(:pilot_check, 1_000, :pilot_check)],
      else: []
  end

  defp pilot_subscriptions(_state), do: []

  @impl true
  def terminate(_reason, state) do
    state = halt_motion(state)
    Pilot.release(state.robot)
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

  # Extension readouts of controller state are polled — controllers publish
  # nothing — at 4 Hz, enough to read and gentle on a small board.
  @controller_poll_ms 250

  # Only while a tab reading controllers is on screen.
  defp controller_poll_subscriptions(state) do
    case visible_controllers(state) do
      [] -> []
      _ -> [Subscription.interval(:controller_poll, @controller_poll_ms, :poll_controllers)]
    end
  end

  defp visible_controllers(%State{ui: %{active_tab: {:extension, tab}}} = state),
    do: State.Extensions.controllers_on(state.extensions, tab)

  defp visible_controllers(_state), do: []

  # ── Helpers ──────────────────────────────────────────────────

  # ── PubSub messages ──────────────────────────────────────────

  defp update_bb({:info, {:bb, [:state_machine | _] = path, msg}}, state) do
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
  defp update_bb({:info, {:bb, [:sensor | _] = path, %{payload: payload} = msg}}, state) do
    configurations =
      case payload do
        %{names: names, positions: pos} -> Enum.zip(names, pos) |> Map.new()
        _ -> %{}
      end

    state =
      state
      |> State.update_configurations(configurations)
      |> record_extensions(&(&1.type == :joint and Map.has_key?(configurations, &1.target)))
      |> State.update_power(payload)
      |> State.append_event(path, msg)
      |> State.mark_render_pending()

    {:noreply, state, render?: false}
  end

  defp update_bb({:info, {:bb, [:param | _] = path, msg}}, state) do
    parameters = Robot.list_parameters(state.robot, [], state.node)

    state =
      state
      |> State.update_parameters(parameters)
      |> record_extensions(&(&1.type == :param))
      |> State.append_event(path, msg)

    {:noreply, state}
  end

  # A command started, finished, failed or was cancelled — by this dashboard or
  # anyone else — so re-read what is running. On a terminal status the event's
  # own execution is left out: bb publishes it while the command process is
  # still alive and registered.
  defp update_bb({:info, {:bb, [:command, _name, execution_id] = path, msg}}, state) do
    finished = if terminal_command_event?(msg), do: execution_id

    state
    |> State.put_running_commands(Robot.running_commands(state.robot, state.node), finished)
    |> route_message(path, msg)
  end

  # Consumer-renderer seam: a path matching a registered renderer prefix
  # (longest-prefix match, like a routing table) is handed off to the consumer's
  # module rather than pattern-matched here — bb_tui never inspects the payload's
  # struct. The renderer's `observed/2` (if exported) feeds the at-a-glance
  # status-bar readout; the event row is rendered later from the same renderer
  # (see `BB.TUI.Panels.Events`). The render is coalesced like sensors
  # (render?: false + the :sensor_flush tick) so a fast consumer stays smooth.
  # Falls through to the catch-all below when no renderer matches.
  defp update_bb({:info, {:bb, path, %{payload: _} = msg}}, state) do
    route_message(state, path, msg)
  end

  # Everything else we subscribe to but don't model in dedicated state —
  # notably `[:safety, :error]` hardware-error reports and `[:estimator | _]`
  # odometry/pose — lands here and is surfaced in the event log. Safety *state*
  # transitions arrive separately on `[:state_machine]` (see above), so the
  # badge already reflects an error before its detail shows up here.
  defp update_bb({:info, {:bb, path, msg}}, state) do
    {:noreply, State.append_event(state, path, msg)}
  end

  defp observe_extension_topics(state, path, %{payload: payload}) do
    state = %{state | extensions: State.Extensions.put_message(state.extensions, path, payload)}

    case State.Extensions.matching_topics(state.extensions, path) do
      [] -> state
      topics -> record_extensions(state, &(&1.type == :topic and &1.target in topics))
    end
  end

  defp observe_extension_topics(state, _path, _msg), do: state

  defp record_extensions(state, filter), do: State.Extensions.record(state, now_ms(), filter)

  # Steps the drive and does what it says: publish the held throttle and
  # turn, or stop once when the last key is let go. A tick only redraws the
  # pad when what is held changed.
  # A session that lost the lease since the last step — taken over after a
  # split healed, released elsewhere — stops instead of publishing.
  defp step_drive(state, opts \\ []) do
    checked = observe_lease(state)

    {action, drive} =
      case checked.drive.lease do
        :mine -> State.Drive.step(checked.drive, now_ms())
        _lost -> State.Drive.halt(checked.drive)
      end

    drive_action(checked, action)

    render? =
      Keyword.get(opts, :render?, true) or drive.held != state.drive.held or
        drive.lease != state.drive.lease

    {:noreply, %{checked | drive: drive}, render?: render?}
  end

  defp observe_lease(%State{} = state) do
    holder =
      case Pilot.holder(state.robot) do
        {:other, pid} -> {:other, node(pid)}
        mine_or_free -> mine_or_free
      end

    %{state | drive: State.Drive.observe_lease(state.drive, holder, NaiveDateTime.local_now())}
  end

  defp halt_drive(%State{} = state) do
    {action, drive} = State.Drive.halt(state.drive)
    drive_action(state, action)
    %{state | drive: drive}
  end

  defp inspect_controller(state, nil), do: {:noreply, state}

  defp inspect_controller(state, name) do
    %{robot: robot, node: node} = state

    ask =
      Command.async(
        fn -> Robot.inspect_controller(robot, name, node) end,
        &{:controller_detail, name, &1}
      )

    {:noreply, put_in(state.controllers.detail, %{name: name, result: :loading}), commands: [ask]}
  end

  # Everything this session keeps moving: the drive and a spinning joint.
  defp halt_motion(state), do: state |> halt_drive() |> halt_velocity_jog()

  defp toggle_lease(state) do
    case observe_lease(state) do
      %{drive: %{lease: :mine}} = state ->
        state = halt_motion(state)
        :ok = Pilot.release(state.robot)
        {:noreply, observe_lease(state)}

      state ->
        _ = Pilot.take(state.robot)
        {:noreply, observe_lease(state)}
    end
  end

  defp halt_drive_off_tab(%State{ui: %{active_tab: {:extension, :drive}}} = state), do: state
  defp halt_drive_off_tab(state), do: halt_drive(state)

  defp drive_action(%State{extensions: %{drive: drive}} = state, {:publish, throttle, turn}) do
    {throttle, turn} = State.Extensions.drive_command(state, throttle, turn)
    Robot.drive(drive.publish, [state.robot, throttle, turn], state.node)
  end

  defp drive_action(%State{extensions: %{drive: drive}} = state, :stop),
    do: Robot.drive(drive.stop, [state.robot], state.node)

  defp drive_action(_state, _idle), do: :ok

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp route_message(state, path, %{payload: payload} = msg) do
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

  defp route_message(state, path, msg), do: {:noreply, State.append_event(state, path, msg)}

  defp terminal_command_event?(%{payload: %{status: status}}),
    do: status in [:succeeded, :failed, :cancelled]

  defp terminal_command_event?(_msg), do: false

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

  # Only the safety panel's disarming spinner animates. A running command
  # shows a static `⏳ Running` badge, so ticking while one runs would only
  # redraw an unchanged screen ten times a second.
  defp needs_throbber?(%State{safety: %{state: :disarming}}), do: true
  defp needs_throbber?(_), do: false

  defp maybe_add_popup(
         panels,
         %{ui: %{show_help?: true, help_scroll_offset: offset}} = state,
         full
       ) do
    panels ++ [{Panels.Help.render(offset, state.extensions.binds), full}]
  end

  defp maybe_add_popup(panels, %{safety: %{confirm_force_disarm?: true}}, full) do
    panels ++ [{Panels.ForceDisarm.render(), full}]
  end

  defp maybe_add_popup(panels, %{controllers: %{detail: %{} = detail}}, full),
    do: panels ++ [{Panels.Controllers.detail(detail), full}]

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

  defguardp jog_allowed?(state) when state.safety.state in [:armed, :disarming]

  defp adjust_selected_joint(state, _direction, _multiplier) when not jog_allowed?(state) do
    {:noreply, state}
  end

  defp adjust_selected_joint(state, direction, multiplier) do
    name = State.selected_joint_name(state)

    case name && Map.get(state.joints.entries, name) do
      nil ->
        {:noreply, state}

      %{position: pos} when not is_number(pos) ->
        {:noreply, state}

      joint_data ->
        jog_joint(state, name, joint_data, State.jog_mode(state, name), direction, multiplier)
    end
  end

  # A read-only or position-refusing joint stays put: the status bar says why.
  defp jog_joint(state, name, %{joint: joint} = joint_data, mode, direction, multiplier)
       when mode in [:position, :simulated] do
    step = State.joint_step(joint) * multiplier
    base = State.jog_base(joint_data)

    new_pos =
      case direction do
        :increase -> base + step
        :decrease -> base - step
      end
      |> State.clamp_position(joint)

    state = State.set_joint_target(state, name, new_pos)

    case mode do
      :position ->
        jog(state, State.actuator_for_joint(state.robot_struct, name), new_pos)

      :simulated ->
        publish_simulated_position(state.robot, name, new_pos, state.node)
        {:noreply, State.set_joint_position(state, name, new_pos)}
    end
  end

  defp jog_joint(state, name, %{joint: joint}, :velocity_only, direction, multiplier) do
    case observe_lease(state) do
      %{drive: %{lease: :mine}} = state ->
        actuator = State.actuator_for_joint(state.robot_struct, name)
        velocity = State.VelocityJog.velocity(joint, direction, multiplier)

        {commands, jog} =
          State.VelocityJog.press(state.joints.velocity_jog, actuator, name, velocity, now_ms())

        send_jog_commands(state, commands)
        {:noreply, put_in(state.joints.velocity_jog, jog)}

      state ->
        {:noreply, state}
    end
  end

  defp jog_joint(state, _name, _joint_data, _mode, _direction, _multiplier), do: {:noreply, state}

  # A spinning joint keeps spinning only while it is still the selected joint
  # on the Joints panel, the robot is armed, and the wheel is this session's.
  defp velocity_jog_valid?(%State{joints: %{velocity_jog: %{joint: joint}}} = state) do
    state.ui.active_tab == :control and state.ui.active_panel == :joints and
      State.selected_joint_name(state) == joint and jog_allowed?(state) and
      Pilot.holder(state.robot) == :mine
  end

  defp velocity_joint_selected?(state) do
    case State.selected_joint_name(state) do
      nil -> false
      name -> State.jog_mode(state, name) == :velocity_only
    end
  end

  defp halt_velocity_jog(state) do
    {commands, nil} = State.VelocityJog.halt(state.joints.velocity_jog)
    send_jog_commands(state, commands)
    put_in(state.joints.velocity_jog, nil)
  end

  defp send_jog_commands(state, commands) do
    Enum.each(commands, fn
      {:velocity, actuator, velocity} ->
        Robot.set_velocity(state.robot, actuator, velocity, state.node)

      {:stop, actuator} ->
        Robot.stop_actuator(state.robot, actuator, state.node)
    end)
  end

  # The refusal carries the payloads the actuator really accepts, which beats
  # whatever its DSL declaration suggested on mount.
  defp learn_payloads(state, actuator, %UnsupportedCommand{supported: supported})
       when is_list(supported),
       do: State.put_command_payloads(state, actuator, supported)

  defp learn_payloads(state, _actuator, _reason), do: state

  defp forget_refused_target(state, actuator, reason) do
    joint = find_joint_for_actuator(state, actuator)

    if joint && Errors.severity(reason) != :warning,
      do: State.set_joint_target(state, joint, nil),
      else: state
  end

  defp find_joint_for_actuator(%State{robot_struct: %{actuators: actuators}}, actuator) do
    case Map.get(actuators, actuator) do
      %{joint: joint} -> joint
      _ -> nil
    end
  end

  defp find_joint_for_actuator(_state, _actuator), do: nil

  # One jog in flight per actuator. An actuator applies every command it is
  # sent, in order — one answered late (`CommandPending`) is still queued, not
  # dropped — so sending a target per autorepeat would leave a slow actuator
  # working through stale ones. Targets arriving while a jog is in flight are
  # parked, latest wins, and sent when it is answered.
  defp jog(state, actuator, position) do
    case State.request_jog(state, actuator, position) do
      {:send, state} ->
        {:noreply, state, commands: [set_actuator_command(state, actuator, position)]}

      {:queued, state} ->
        {:noreply, state}
    end
  end

  # A position parked while the robot was armed is dropped if it has since
  # been disarmed: sending it would only collect a refusal.
  defp continue_jog(state, actuator) do
    case State.finish_jog(state, actuator) do
      {nil, state} ->
        {state, []}

      {position, state} when jog_allowed?(state) ->
        {state, [commands: [set_actuator_command(state, actuator, position)]]}

      {_position, state} ->
        {_nil, state} = State.finish_jog(state, actuator)
        {state, []}
    end
  end

  # Off the event loop because `set_position/4`'s `:pubsub` delivery is a
  # `GenServer.call`: inline it would stall the terminal-owning process on
  # every jog keypress. The async runner traps the exit of an actuator that
  # crashes while handling the command and delivers it as
  # `{:error, {:exit, reason}}`.
  # Off the event loop: an `:inspect` is a `GenServer.call` into the robot.
  defp inspect_controller_command(%State{robot: robot, node: node}, name) do
    Command.async(
      fn -> Robot.inspect_controller(robot, name, node) end,
      fn result -> {:controller_state, name, result} end
    )
  end

  defp set_actuator_command(%State{robot: robot, node: node}, actuator, position) do
    Command.async(
      fn -> Robot.set_actuator(robot, actuator, position, node) end,
      fn result -> {:actuator_result, actuator, result} end
    )
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

  # A joint the runtime has no configuration for starts at its type's identity.
  defp default_configuration(%{type: :planar}), do: Transform2D.identity()
  defp default_configuration(%{type: :floating}), do: Transform.identity()
  defp default_configuration(_joint), do: 0.0

  defp refresh_selected_tab(state) do
    case State.selected_parameter_tab(state) do
      :local -> []
      {:bridge, name} -> [fetch_remote_parameters(state, name)]
    end
  end

  # ── Robot writes and bridge reads, off the event loop ─────────
  #
  # Each of these is a call into one of the robot's processes that can take a
  # while or exit: an arm or disarm may run a whole arm/disarm command and the
  # disarm callbacks (up to 5s each), a parameter write waits on the runtime,
  # and a bridge call crosses to the remote system with a 5s timeout. Inline,
  # they would freeze the dashboard for as long — and over `:rpc` a failed call
  # raises — so each runs through `Command.async/2`, and its answer comes back
  # as a message.

  defp safety_write(%State{robot: robot, node: node}, action, fun) do
    Command.async(fn -> fun.(robot, node) end, &{:robot_write, [:safety, action], &1})
  end

  defp parameter_write(%State{robot: robot, node: node}, path, value) do
    Command.async(
      fn -> Robot.set_parameter(robot, path, value, node) end,
      &{:robot_write, [:param | path], &1}
    )
  end

  defp fetch_remote_parameters(%State{robot: robot, node: node}, bridge) do
    Command.async(
      fn ->
        case Robot.list_remote_parameters(robot, bridge, node) do
          {:ok, params} -> params
          {:error, _} = error -> error
        end
      end,
      &{:remote_parameters, bridge, &1}
    )
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
        {:noreply, state, commands: [parameter_write(state, path, new_value)]}

      {path, value} when is_float(value) ->
        bounds = State.parameter_bounds(state, path)
        step = float_step(bounds) * multiplier
        new_value = State.clamp_to_bounds(apply_step(value, direction, step), bounds)
        {:noreply, state, commands: [parameter_write(state, path, new_value)]}

      # A unit-typed value arrives in its declared unit (bb 0.31), but its
      # bounds keep the unit they were declared in, so they are converted
      # into the value's unit before stepping the magnitude.
      {path, %Localize.Unit{value: magnitude} = value} when is_number(magnitude) ->
        bounds = State.unit_bounds_in(State.parameter_bounds(state, path), value.name)
        step = float_step(bounds) * multiplier
        new_magnitude = State.clamp_to_bounds(apply_step(magnitude, direction, step), bounds)

        {:noreply, state,
         commands: [parameter_write(state, path, %{value | value: new_magnitude})]}

      {path, value} ->
        cycle_in_values(state, path, value, direction)

      nil ->
        {:noreply, state}
    end
  end

  # A parameter declared with an {:in, values} type cycles through its
  # allowed set on h/l, whatever the values' type; the multiplier keys
  # deliberately still move one value at a time.
  defp cycle_in_values(state, path, value, direction) do
    case State.parameter_in_values(state, path) do
      [_ | _] = values ->
        step = if direction == :increase, do: :next, else: :prev

        {:noreply, state,
         commands: [parameter_write(state, path, State.cycle_value(values, value, step))]}

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

  defp dispatch_remote_set(%State{robot: robot, node: node} = state, bridge, param, new_value) do
    id = State.remote_param_id(param)

    write =
      Command.async(
        fn -> Robot.set_remote_parameter(robot, bridge, id, new_value, node) end,
        &{:remote_param_set, bridge, id, &1}
      )

    {:noreply, state, commands: [write]}
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
        {:noreply, state, commands: [parameter_write(state, path, !value)]}

      _ ->
        {:noreply, State.start_param_edit(state)}
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

  defp run_bound_command(state, %{command: name}) do
    case Enum.find(state.commands.available, &(&1.name == name)) do
      nil ->
        {:noreply,
         State.append_event(state, [:command, name], %{payload: %{error: :unknown_command}})}

      _cmd when state.commands.executing != nil ->
        {:noreply, state}

      cmd ->
        {:noreply, State.start_command(state, name),
         commands: [execute_command_command(state, cmd, %{})]}
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

          {:noreply, State.start_command(State.exit_command_edit_mode(state), cmd.name),
           commands: [execute_command_command(state, cmd, args)]}
        else
          {:noreply, state}
        end
    end
  end

  # Execution is two-phase: phase one starts the command and reports
  # `{:command_started, _}`, at which point it is registered and the running
  # list is refreshed; phase two awaits it and reports `{:command_result, _}`.
  defp execute_command_command(%State{robot: robot, node: node}, cmd, args) do
    name = cmd.name

    Command.async(
      fn -> Robot.execute_command(robot, name, args, node) end,
      fn result -> {:command_started, result} end
    )
  end

  # Off the event loop: cancelling is a `GenServer.stop/3`, which waits for the
  # command to terminate, and a handler busy inside a callback only gets to the
  # stop request once that callback returns — inline, the dashboard would
  # freeze for as long.
  defp cancel_command_command(%State{robot: robot, node: node}, execution_id) do
    Command.async(
      fn -> Robot.cancel_command(robot, execution_id, node) end,
      fn _ -> :command_cancel_sent end
    )
  end

  defp await_command_command(%State{node: node}, cmd_pid) do
    Command.async(
      fn -> await_command(cmd_pid, node) end,
      fn result -> {:command_result, result} end
    )
  end

  # BB.Command.await/2 traps `:exit, {:noproc, _}` and falls back to the
  # command's ResultCache, so it survives the race where a fast handler
  # (e.g. a synchronous {:stop, :normal, _}) terminates between
  # `Robot.execute_command/4` returning the pid and us awaiting on it.
  # The earlier Process.monitor approach surfaced that race as a
  # spurious {:error, :noproc}. The cache is node-local, so against a
  # remote robot `Robot.await_command/2` runs the await on its node.
  #
  # Awaits `:infinity` rather than a UI-side deadline: a continuous command
  # only returns when it stops or is cancelled, and the command's own DSL
  # `timeout` already bounds runaways. The user-facing escape hatch is `c`
  # in the commands panel, which cancels the command and resolves this
  # await. Matches `BB.LiveView.Components.Command`.
  #
  # Unwrap {:command_failed, reason} at the boundary so the panel shows
  # the bare reason (`:cancelled`, `:noproc`, etc.) consistently.
  defp await_command(cmd_pid, node) do
    case Robot.await_command(cmd_pid, node) do
      {:ok, result} -> {:ok, result}
      {:ok, result, _opts} -> {:ok, result}
      {:error, {:command_failed, reason}} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end
end
