defmodule BB.TUI.Test.Fixtures do
  @moduledoc false

  alias BB.TUI.State.Commands
  alias BB.TUI.State.Events
  alias BB.TUI.State.Joints
  alias BB.TUI.State.Parameters
  alias BB.TUI.State.Power
  alias BB.TUI.State.Safety
  alias BB.TUI.State.Throttle
  alias BB.TUI.State.UI

  # Legacy flat override keys → {substruct, field}. As `BB.TUI.State` is split
  # into substructs, tests keep passing flat overrides (e.g.
  # `%{event_debounce_ms: 0}`) and `sample_state/1` routes them into the right
  # nested struct. Grows one group per refactor chunk.
  @nested_overrides %{
    event_debounce_ms: {:throttle, :debounce_ms},
    event_last_seen: {:throttle, :last_seen},
    sensor_flush_ms: {:throttle, :flush_ms},
    render_pending?: {:throttle, :render_pending?},
    safety_state: {:safety, :state},
    runtime_state: {:safety, :runtime},
    confirm_force_disarm: {:safety, :confirm_force_disarm?},
    battery: {:power, :battery},
    power_reading: {:power, :power},
    joints: {:joints, :entries},
    joint_selected: {:joints, :selected},
    events: {:events, :list},
    scroll_offset: {:events, :scroll_offset},
    events_paused: {:events, :paused?},
    show_event_detail: {:events, :show_detail?},
    active_panel: {:ui, :active_panel},
    show_help: {:ui, :show_help?},
    help_scroll_offset: {:ui, :help_scroll_offset},
    throbber_step: {:ui, :throbber_step},
    parameters: {:parameters, :list},
    parameter_metadata: {:parameters, :metadata},
    parameter_tabs: {:parameters, :tabs},
    parameter_tab_selected: {:parameters, :tab_selected},
    remote_parameters: {:parameters, :remote},
    param_selected: {:parameters, :selected},
    commands: {:commands, :available},
    command_selected: {:commands, :selected},
    command_result: {:commands, :result},
    executing_command: {:commands, :executing},
    command_edit_mode: {:commands, :edit_mode?},
    command_focused_arg: {:commands, :focused_arg},
    command_form_values: {:commands, :form_values}
  }

  @doc """
  Returns a default State struct with mocked robot data for testing.

  Accepts flat overrides; keys belonging to a substruct (see
  `@nested_overrides`) are routed into it automatically.
  """
  def sample_state(overrides \\ %{}) do
    defaults = %{
      robot: BB.TUI.TestRobot,
      robot_struct: sample_robot_struct(),
      node: nil
    }

    {nested, flat} = Map.split(overrides, Map.keys(@nested_overrides))

    substructs =
      Enum.reduce(nested, substruct_defaults(), fn {key, value}, acc ->
        {group, field} = Map.fetch!(@nested_overrides, key)
        Map.update!(acc, group, &Map.put(&1, field, value))
      end)

    struct!(BB.TUI.State, defaults |> Map.merge(flat) |> Map.merge(substructs))
  end

  # Test-friendly substruct defaults. Debounce is off by default so
  # timing-agnostic tests stay deterministic; debounce tests opt in with
  # `%{event_debounce_ms: 1000}`. Production state (App.init/1) uses the
  # struct defaults.
  defp substruct_defaults do
    %{
      throttle: %Throttle{debounce_ms: 0},
      safety: %Safety{state: :disarmed, runtime: :disarmed},
      joints: %Joints{entries: sample_joints()},
      events: %Events{},
      ui: %UI{},
      parameters: %Parameters{},
      commands: %Commands{},
      power: %Power{}
    }
  end

  @doc """
  Returns a sample `%BB.Robot{}` with a base and a shoulder/elbow chain.

  This is a valid topology (links with box visuals, revolute joints) so the
  3D visualization render path works in tests, not just the joint table.
  """
  def sample_robot_struct do
    %BB.Robot{
      name: :test_robot,
      root_link: :base,
      actuators: %{},
      links: %{
        base: %BB.Robot.Link{
          name: :base,
          parent_joint: nil,
          child_joints: [:shoulder],
          visual:
            sample_box(%{x: 0.06, y: 0.06, z: 0.04}, %{
              red: 0.3,
              green: 0.3,
              blue: 0.3,
              alpha: 1.0
            })
        },
        upper: %BB.Robot.Link{
          name: :upper,
          parent_joint: :shoulder,
          child_joints: [:elbow],
          visual:
            sample_box(%{x: 0.04, y: 0.04, z: 0.2}, %{
              red: 0.7,
              green: 0.7,
              blue: 0.75,
              alpha: 1.0
            })
        },
        fore: %BB.Robot.Link{
          name: :fore,
          parent_joint: :elbow,
          child_joints: [],
          visual:
            sample_box(%{x: 0.04, y: 0.04, z: 0.18}, %{
              red: 0.7,
              green: 0.7,
              blue: 0.75,
              alpha: 1.0
            })
        }
      },
      joints: %{
        shoulder: %BB.Robot.Joint{
          name: :shoulder,
          type: :revolute,
          parent_link: :base,
          child_link: :upper,
          origin: %{position: {0.0, 0.0, 0.04}, orientation: {0.0, 0.0, 0.0}},
          axis: {0.0, 1.0, 0.0},
          limits: %{lower: -1.5, upper: 1.5}
        },
        elbow: %BB.Robot.Joint{
          name: :elbow,
          type: :revolute,
          parent_link: :upper,
          child_link: :fore,
          origin: %{position: {0.0, 0.0, 0.2}, orientation: {0.0, 0.0, 0.0}},
          axis: {0.0, 1.0, 0.0},
          limits: %{lower: 0.0, upper: 2.3}
        }
      }
    }
  end

  defp sample_box(dims, color) do
    %{
      origin: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}},
      geometry: {:box, dims},
      material: %{name: :grey, color: color}
    }
  end

  @doc """
  Returns sample joint data.
  """
  def sample_joints do
    %{
      shoulder: %{
        joint: %{name: :shoulder, type: :revolute, limits: %{lower: -90.0, upper: 90.0}},
        position: 0.0
      },
      elbow: %{
        joint: %{name: :elbow, type: :revolute, limits: %{lower: 0.0, upper: 135.0}},
        position: 45.0
      }
    }
  end

  @doc """
  Returns the list of sample joints used by mount.
  """
  def sample_joint_list do
    [
      %{name: :shoulder, type: :revolute, limits: %{lower: -90.0, upper: 90.0}},
      %{name: :elbow, type: :revolute, limits: %{lower: 0.0, upper: 135.0}}
    ]
  end

  @doc """
  Returns sample commands for testing.
  """
  def sample_commands do
    [
      %{name: :home, allowed_states: [:idle], arguments: [], handler: SomeHandler},
      %{name: :calibrate, allowed_states: [:idle, :armed], arguments: [], handler: SomeHandler}
    ]
  end

  @doc """
  Sets up Mimic stubs for all BB modules with sensible defaults.
  Call this in test setup blocks.
  """
  def stub_bb_modules(overrides \\ []) do
    safety_state = Keyword.get(overrides, :safety_state, :disarmed)
    runtime_state = Keyword.get(overrides, :runtime_state, :disarmed)

    Mimic.stub(BB, :subscribe, fn _robot, _path -> :ok end)
    Mimic.stub(BB, :publish, fn _robot, _path, _msg -> :ok end)
    Mimic.stub(BB.Safety, :state, fn _robot -> safety_state end)
    Mimic.stub(BB.Safety, :in_error?, fn _robot -> safety_state == :error end)
    Mimic.stub(BB.Safety, :arm, fn _robot -> :ok end)
    Mimic.stub(BB.Safety, :disarm, fn _robot -> :ok end)
    Mimic.stub(BB.Safety, :force_disarm, fn _robot -> :ok end)
    Mimic.stub(BB.Actuator, :set_position!, fn _robot, _actuator, _pos -> :ok end)
    Mimic.stub(BB.Robot, :joints_in_order, fn _robot -> sample_joint_list() end)
    Mimic.stub(BB.Robot.Joint, :movable?, fn _joint -> true end)
    Mimic.stub(BB.Robot.Runtime, :get_robot, fn _robot -> sample_robot_struct() end)
    Mimic.stub(BB.Robot.Runtime, :positions, fn _robot -> %{shoulder: 0.0, elbow: 45.0} end)
    Mimic.stub(BB.Robot.Runtime, :state, fn _robot -> runtime_state end)
    Mimic.stub(BB.Parameter, :list, fn _robot, _opts -> [] end)
    Mimic.stub(BB.Parameter, :set, fn _robot, _path, _value -> :ok end)
    Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> [] end)

    :ok
  end
end
