defmodule BB.TUI.Panels.StatusBarTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.StatusBar

  alias BB.Message.Actuator.Command.Stop
  alias BB.Message.Actuator.Command.Velocity
  alias BB.TUI.Panels.StatusBar
  alias BB.TUI.State
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Paragraph

  # Flatten the rich-text Line back to a single string for substring
  # assertions. Each pill / dim segment carries its own color, but the
  # text content is what users actually read.
  defp text(%Paragraph{text: %Line{spans: spans}}) do
    Enum.map_join(spans, "", & &1.content)
  end

  # The first sample joint (`elbow`, sorted) driven by an actuator that takes
  # only `payloads`.
  defp state_with_payloads(payloads) do
    robot = %{Fixtures.sample_robot_struct() | actuators: %{elbow_motor: %{joint: :elbow}}}

    %{active_panel: :joints, safety_state: :armed, simulation: nil, robot_struct: robot}
    |> Fixtures.sample_state()
    |> State.put_command_payloads(:elbow_motor, payloads)
  end

  describe "render/1" do
    test "shows robot module name" do
      state = Fixtures.sample_state(%{robot: MyApp.Robot})
      widget = StatusBar.render(state)

      assert %Paragraph{} = widget
      assert text(widget) =~ "MyApp.Robot"
    end

    test "shows safety badge for armed state" do
      state = Fixtures.sample_state(%{safety_state: :armed})
      assert text(StatusBar.render(state)) =~ "ARMED"
    end

    test "shows runtime state pill" do
      state = Fixtures.sample_state(%{runtime_state: :idle})
      assert text(StatusBar.render(state)) =~ "idle"
    end

    test "shows global key pills (Tab / ? / q)" do
      state = Fixtures.sample_state()
      txt = text(StatusBar.render(state))

      assert txt =~ " Tab "
      assert txt =~ " panel"
      assert txt =~ " ? "
      assert txt =~ " help"
      assert txt =~ " q "
      assert txt =~ " quit"
    end

    test "shows safety panel hints (arm / disarm)" do
      state = Fixtures.sample_state(%{active_panel: :safety})
      txt = text(StatusBar.render(state))

      assert txt =~ " a "
      assert txt =~ " arm "
      assert txt =~ " d "
      assert txt =~ " disarm "
    end

    test "shows events panel hints (scroll / pause / clear / detail)" do
      state = Fixtures.sample_state(%{active_panel: :events})
      txt = text(StatusBar.render(state))

      assert txt =~ "scroll"
      assert txt =~ "pause"
      assert txt =~ "clear"
      assert txt =~ "detail"
    end

    test "shows commands panel hints (select / execute)" do
      state = Fixtures.sample_state(%{active_panel: :commands})
      txt = text(StatusBar.render(state))

      assert txt =~ "select"
      assert txt =~ "execute"
    end

    test "uses no paragraph background — pills carry the visual identity" do
      widget = StatusBar.render(Fixtures.sample_state())
      # A `bg: :dark_gray` strip would clash with the dim-gray descriptor
      # spans next to each pill (dark-on-dark renders blank). Each pill
      # sets its own bg, so the paragraph stays unstyled.
      assert widget.style == %ExRatatui.Style{}
    end

    test "shows DISARMING safety badge" do
      state = Fixtures.sample_state(%{safety_state: :disarming})
      assert text(StatusBar.render(state)) =~ "DISARMING"
    end

    test "shows ERROR safety badge" do
      state = Fixtures.sample_state(%{safety_state: :error})
      assert text(StatusBar.render(state)) =~ "ERROR"
    end

    test "renders unknown safety state as plain text" do
      state = Fixtures.sample_state(%{safety_state: :custom_state})
      assert text(StatusBar.render(state)) =~ "custom_state"
    end

    test "shows joints panel hints when not armed (select only)" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :disarmed})
      txt = text(StatusBar.render(state))

      assert txt =~ "j/k"
      assert txt =~ "select"
      refute txt =~ "adjust"
    end

    test "shows joints adjustment hints when armed" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :armed})
      txt = text(StatusBar.render(state))

      assert txt =~ "h/l"
      assert txt =~ "adjust"
      assert txt =~ "H/L"
      assert txt =~ "10×"
    end

    test "says why a read-only joint doesn't jog on hardware" do
      state =
        Fixtures.sample_state(%{active_panel: :joints, safety_state: :armed, simulation: nil})

      txt = text(StatusBar.render(state))

      assert txt =~ "read-only: no actuator"
      refute txt =~ "adjust"
    end

    test "offers to take the wheel for a velocity-only joint" do
      txt = state_with_payloads([Velocity, Stop]) |> StatusBar.render() |> text()

      assert txt =~ "take the wheel to spin"
      refute txt =~ "adjust"
    end

    test "offers the spin keys for a velocity-only joint with the wheel" do
      state = state_with_payloads([Velocity, Stop])
      txt = put_in(state.drive.lease, :mine) |> StatusBar.render() |> text()

      assert txt =~ "spin"
      assert txt =~ "5×"
      assert txt =~ "wheel"
    end

    test "says who drives a velocity-only joint's robot" do
      state = state_with_payloads([Velocity, Stop])
      lease = {:other, :pilot@host, ~N[2026-10-26 10:00:00]}
      txt = put_in(state.drive.lease, lease) |> StatusBar.render() |> text()

      assert txt =~ "driven by pilot@host"
    end

    test "says a joint taking no position or velocity commands doesn't jog" do
      txt = state_with_payloads([Stop]) |> StatusBar.render() |> text()

      assert txt =~ "takes no position commands"
      refute txt =~ "adjust"
    end

    test "offers the jog keys when no joint is selected" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :armed, joints: %{}})
      assert text(StatusBar.render(state)) =~ "adjust"
    end

    test "on an extension tab offers tab switching and the bound keys" do
      binds = [
        %BB.TUI.Extension.Bind{key: "s", command: :stand, label: "stand up"},
        %BB.TUI.Extension.Bind{key: "w", command: :wobble}
      ]

      state = %{
        Fixtures.sample_state(%{active_panel: :joints})
        | extensions: %BB.TUI.State.Extensions{binds: binds}
      }

      txt = text(StatusBar.render(put_in(state.ui.active_tab, {:extension, :yaw})))

      assert txt =~ "[ ]"
      assert txt =~ " s "
      assert txt =~ "stand up"
      assert txt =~ "wobble"
      refute txt =~ "select"

      plain = %{state | extensions: %BB.TUI.State.Extensions{}}
      refute text(StatusBar.render(put_in(plain.ui.active_tab, {:extension, :yaw}))) =~ "stand"
    end

    test "shows joints adjustment hints when disarming" do
      state = Fixtures.sample_state(%{active_panel: :joints, safety_state: :disarming})
      txt = text(StatusBar.render(state))

      assert txt =~ "h/l"
      assert txt =~ "adjust"
    end

    test "shows parameters panel hints (select / adjust / toggle) without tab pill on single tab" do
      state = Fixtures.sample_state(%{active_panel: :parameters})
      txt = text(StatusBar.render(state))

      assert txt =~ "select"
      assert txt =~ "adjust"
      assert txt =~ "toggle"
      refute txt =~ " tab "
    end

    test "shows commit / cancel hints while a parameter is being edited" do
      state = Fixtures.sample_state(%{active_panel: :parameters})

      state = %{
        state
        | parameters: %{state.parameters | editing: %{path: [:name], buffer: "arm"}}
      }

      txt = text(StatusBar.render(state))

      assert txt =~ "commit"
      assert txt =~ "cancel"
      refute txt =~ "adjust"
    end

    test "shows t / tab pill on parameters panel when bridge tabs are present" do
      state =
        Fixtures.sample_state(%{
          active_panel: :parameters,
          parameter_tabs: [:local, {:bridge, :mavlink}]
        })

      txt = text(StatusBar.render(state))

      assert txt =~ " t "
      assert txt =~ " tab "
    end

    test "shows Disarmed dim badge" do
      state = Fixtures.sample_state(%{safety_state: :disarmed})
      assert text(StatusBar.render(state)) =~ "Disarmed"
    end

    test "still shows global pills for an unknown panel" do
      state = Fixtures.sample_state(%{active_panel: :unknown_panel})
      assert text(StatusBar.render(state)) =~ " q "
    end
  end

  describe "battery / power segment" do
    alias BB.Message.Sensor.BatteryState
    alias BB.Message.Sensor.PowerState

    test "shows battery charge percentage when battery telemetry is present" do
      battery = %BatteryState{voltage: 12.0, percentage: 0.87}
      state = Fixtures.sample_state(%{battery: battery})

      assert text(StatusBar.render(state)) =~ "87%"
    end

    test "marks a charging battery with a bolt" do
      battery = %BatteryState{voltage: 12.0, percentage: 0.5, power_supply_status: :charging}
      state = Fixtures.sample_state(%{battery: battery})
      txt = text(StatusBar.render(state))

      assert txt =~ "50%"
      assert txt =~ "⚡"
    end

    test "falls back to battery voltage when percentage is unmeasured" do
      battery = %BatteryState{voltage: 12.4, percentage: nil}
      state = Fixtures.sample_state(%{battery: battery})

      assert text(StatusBar.render(state)) =~ "12.4V"
    end

    test "shows power-bus voltage when only a PowerState reading is present" do
      reading = %PowerState{voltage: 11.5, current: 2.0}
      state = Fixtures.sample_state(%{power_reading: reading})

      assert text(StatusBar.render(state)) =~ "11.5V"
    end

    test "prefers battery over a bare power reading when both are present" do
      battery = %BatteryState{voltage: 12.0, percentage: 0.9}
      reading = %PowerState{voltage: 11.5, current: 2.0}
      state = Fixtures.sample_state(%{battery: battery, power_reading: reading})
      txt = text(StatusBar.render(state))

      assert txt =~ "90%"
      refute txt =~ "11.5V"
    end

    test "omits the segment entirely when no electrical telemetry has arrived" do
      txt = text(StatusBar.render(Fixtures.sample_state()))

      refute txt =~ "🔋"
      refute txt =~ "⚡"
    end
  end

  describe "observed (consumer-renderer) segment" do
    test "omits the segment entirely when no renderer has populated observed" do
      txt = text(StatusBar.render(Fixtures.sample_state()))

      refute txt =~ "👁"
      refute txt =~ "⚠"
    end

    test "shows the renderer-supplied label of the freshest entry" do
      observed = %{
        {:wheels, :imu} => %{display: %{label: "imu:7"}, meta: %{seq: 5, freshness: :fresh}}
      }

      state = Fixtures.sample_state(%{observed: observed})
      txt = text(StatusBar.render(state))

      assert txt =~ "👁"
      assert txt =~ "imu:7"
    end

    test "picks the entry with the maximum meta.seq as freshest" do
      observed = %{
        {:wheels, :imu} => %{display: %{label: "old"}, meta: %{seq: 1, freshness: :fresh}},
        {:wheels, :pose} => %{display: %{label: "new"}, meta: %{seq: 9, freshness: :fresh}}
      }

      state = Fixtures.sample_state(%{observed: observed})
      txt = text(StatusBar.render(state))

      assert txt =~ "new"
      refute txt =~ "old"
    end

    test "dims a stale entry with a warning glyph" do
      observed = %{
        {:wheels, :imu} => %{display: %{label: "imu:7"}, meta: %{seq: 5, freshness: :stale}}
      }

      state = Fixtures.sample_state(%{observed: observed})
      txt = text(StatusBar.render(state))

      assert txt =~ "⚠"
      refute txt =~ "👁"
    end

    test "inspects a display map with no string label" do
      observed = %{
        bare: %{display: %{foo: :bar}, meta: %{seq: 1, freshness: :fresh}}
      }

      state = Fixtures.sample_state(%{observed: observed})
      txt = text(StatusBar.render(state))

      assert txt =~ "foo: :bar"
    end
  end
end
