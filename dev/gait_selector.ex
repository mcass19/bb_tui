defmodule Dev.GaitSelector do
  @moduledoc """
  Minimal parameter-owning component for the dev robot.

  Registers a hand-written `param_schema/0` under `[:gait]`, the way a
  real locomotion component would. The schema's `{:in, values}` type
  cannot be declared through the robot DSL's `param` entity, and it is
  what drives the parameter panel's fixed-set cycling — `h`/`l` on the
  `gait.pattern` row steps through the allowed values with wrap-around.

  The process itself does nothing beyond the registration; the robot's
  runtime owns the parameter value once the schema is registered.
  """

  use GenServer

  @behaviour BB.Parameter

  @impl BB.Parameter
  def param_schema do
    Spark.Options.new!(
      pattern: [
        type: {:in, [:walk, :trot, :crawl]},
        default: :walk,
        doc: "Locomotion pattern; h/l cycles the allowed set"
      ]
    )
  end

  @doc """
  Starts the selector and registers its parameter schema with `:robot`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts) do
    robot = Keyword.fetch!(opts, :robot)
    :ok = BB.Parameter.register(robot, [:gait], __MODULE__)
    {:ok, %{robot: robot}}
  end
end
