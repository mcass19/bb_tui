if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbTui.Install do
    @shortdoc "Installs BB.TUI into a project"
    @moduledoc """
    #{@shortdoc}

    Imports the package's formatter rules and prints a notice with the
    `mix bb.tui` invocation for launching the dashboard against the robot
    module configured by `bb.install`.

    When no robot module is present yet, the installer offers to compose
    `bb.install` to scaffold one. Pass `--auto-bb` to skip the prompt in
    non-interactive contexts.

    ## Example

    ```bash
    mix igniter.install bb_tui
    mix igniter.install bb_tui --robot MyApp.Arm
    mix igniter.install bb_tui --auto-bb
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    * `--auto-bb` - When the robot module is missing, compose `bb.install`
      without prompting.
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Formatter

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: ["bb.install"],
        schema: [robot: :string, auto_bb: :boolean],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      auto_bb? = Keyword.get(options, :auto_bb, false)
      igniter = Formatter.import_dep(igniter, :bb_tui)
      robot_module = BB.Igniter.robot_module(igniter)
      {robot_exists?, igniter} = Igniter.Project.Module.module_exists(igniter, robot_module)

      cond do
        robot_exists? ->
          Igniter.add_notice(igniter, launch_notice(robot_module))

        auto_bb? or prompt_bb_install?() ->
          igniter
          |> Igniter.compose_task("bb.install", bb_install_argv(options))
          |> Igniter.add_notice(launch_notice(robot_module))

        true ->
          Igniter.add_notice(igniter, manual_install_notice(robot_module))
      end
    end

    defp bb_install_argv(options) do
      case Keyword.get(options, :robot) do
        nil -> []
        robot -> ["--robot", robot]
      end
    end

    defp prompt_bb_install? do
      Mix.shell().yes?("bb_tui needs a BB robot module. Scaffold one with bb.install now?")
    end

    defp launch_notice(robot_module) do
      """
      bb_tui: launch the dashboard with

          mix bb.tui --robot #{inspect(robot_module)}

      or from IEx via `BB.TUI.run(#{inspect(robot_module)})`. See the BB.TUI
      moduledoc for supervised and remote-attach options.
      """
    end

    defp manual_install_notice(robot_module) do
      """
      bb_tui: no robot module found (looked for #{inspect(robot_module)}).

      Run `mix igniter.install bb` first to scaffold one, or re-run with
      `--auto-bb` to compose it now:

          mix igniter.install bb_tui --auto-bb
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
