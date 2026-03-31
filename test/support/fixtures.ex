defmodule BB.TUI.Test.Fixtures do
  @moduledoc false

  @doc """
  Returns a default State struct with mocked robot data for testing.
  """
  def sample_state(overrides \\ %{}) do
    defaults = %{
      robot: BB.TUI.TestRobot,
      robot_struct: sample_robot_struct(),
      safety_state: :disarmed,
      runtime_state: :disarmed,
      joints: sample_joints(),
      events: [],
      parameters: [],
      commands: [],
      active_panel: :safety,
      scroll_offset: 0,
      show_help: false,
      confirm_force_disarm: false,
      throbber_step: 0,
      events_paused: false,
      command_selected: 0,
      command_result: nil,
      executing_command: nil,
      joint_selected: 0
    }

    struct!(BB.TUI.State, Map.merge(defaults, overrides))
  end

  @doc """
  Returns a sample robot struct with shoulder and elbow joints.
  """
  def sample_robot_struct do
    %{
      name: BB.TUI.TestRobot,
      joints: [
        %{name: :shoulder, type: :revolute, limit: %{lower: -90.0, upper: 90.0}},
        %{name: :elbow, type: :revolute, limit: %{lower: 0.0, upper: 135.0}}
      ]
    }
  end

  @doc """
  Returns sample joint data.
  """
  def sample_joints do
    %{
      shoulder: %{
        joint: %{name: :shoulder, type: :revolute, limit: %{lower: -90.0, upper: 90.0}},
        position: 0.0
      },
      elbow: %{
        joint: %{name: :elbow, type: :revolute, limit: %{lower: 0.0, upper: 135.0}},
        position: 45.0
      }
    }
  end

  @doc """
  Returns the list of sample joints used by mount.
  """
  def sample_joint_list do
    [
      %{name: :shoulder, type: :revolute, limit: %{lower: -90.0, upper: 90.0}},
      %{name: :elbow, type: :revolute, limit: %{lower: 0.0, upper: 135.0}}
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
    Mimic.stub(BB.Dsl.Info, :commands, fn _robot -> [] end)

    :ok
  end
end
