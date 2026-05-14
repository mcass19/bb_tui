if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbTui.Install do
    @shortdoc "Installs BB.TUI into a project"
    @moduledoc """
    #{@shortdoc}

    Imports the package's formatter rules and prints a notice with the
    `mix bb.tui` invocation for launching the dashboard against the robot
    module configured by `bb.install`.

    ## Example

    ```bash
    mix igniter.install bb_tui
    mix igniter.install bb_tui --robot MyApp.Arm
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Formatter

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [robot: :string],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      robot_module = BB.Igniter.robot_module(igniter)

      igniter
      |> Formatter.import_dep(:bb_tui)
      |> Igniter.add_notice(launch_notice(robot_module))
    end

    defp launch_notice(robot_module) do
      """
      bb_tui: launch the dashboard with

          mix bb.tui --robot #{inspect(robot_module)}

      or from IEx via `BB.TUI.run(#{inspect(robot_module)})`. See the BB.TUI
      moduledoc for supervised and remote-attach options.
      """
    end
  end
else
  defmodule Mix.Tasks.BbTui.Install do
    @shortdoc "Installs BB.TUI into a project"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_tui.install task requires igniter.

          mix igniter.install bb_tui
      """)

      exit({:shutdown, 1})
    end
  end
end
