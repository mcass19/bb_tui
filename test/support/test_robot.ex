defmodule BB.TUI.TestRobot do
  @moduledoc false

  @doc false
  def robot do
    %{
      name: __MODULE__,
      joints: [
        %{name: :shoulder, type: :revolute, limits: %{lower: -90.0, upper: 90.0}},
        %{name: :elbow, type: :revolute, limits: %{lower: 0.0, upper: 135.0}}
      ]
    }
  end

  @doc false
  def spark_dsl_config, do: %{}
end
