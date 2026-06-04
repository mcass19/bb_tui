defmodule BB.TUI.Test.Fixtures do
  @moduledoc false

  alias BB.TUI.State.Events
  alias BB.TUI.State.Joints
  alias BB.TUI.State.Safety
  alias BB.TUI.State.Throttle

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
    joints: {:joints, :entries},
    joint_selected: {:joints, :selected},
    events: {:events, :list},
    scroll_offset: {:events, :scroll_offset},
    events_paused: {:events, :paused?},
    show_event_detail: {:events, :show_detail?}
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
      node: nil,
      parameters: [],
      commands: [],
      active_panel: :safety,
      show_help: false,
      throbber_step: 0,
      command_selected: 0,
      command_result: nil,
      executing_command: nil,
      param_selected: 0
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
      events: %Events{}
    }
  end

  @doc """
  Returns a sample robot struct with shoulder and elbow joints.
  """
  def sample_robot_struct do
    %{
      name: BB.TUI.TestRobot,
      joints: [
        %{name: :shoulder, type: :revolute, limits: %{lower: -90.0, upper: 90.0}},
        %{name: :elbow, type: :revolute, limits: %{lower: 0.0, upper: 135.0}}
      ]
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
