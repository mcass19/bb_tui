if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbTui.Install do
    @shortdoc "Installs BB.TUI into a project"
    @moduledoc """
    #{@shortdoc}

    Imports the package's formatter rules and prints a launch notice for
    the configured robot module.

    When no robot module is present yet, the installer offers to compose
    `bb.install` to scaffold one. Pass `--auto-bb` to skip the prompt in
    non-interactive contexts.

    With `--supervise`, the installer also appends `{BB.TUI, robot: …}`
    to the consumer's application supervision tree. Pair it with `--ssh`
    to boot an SSH daemon on application start.

    With `--nerves`, the installer registers `BB.TUI.subsystem/1` under
    `config :nerves_ssh, :subsystems` in `config/runtime.exs`. Use this
    on Nerves devices that already run `nerves_ssh` so the dashboard
    rides on the existing daemon instead of opening a second SSH port.

    ## Examples

    ```bash
    mix igniter.install bb_tui
    mix igniter.install bb_tui --robot MyApp.Arm
    mix igniter.install bb_tui --auto-bb
    mix igniter.install bb_tui --supervise
    mix igniter.install bb_tui --supervise --ssh --port 2222
    mix igniter.install bb_tui --supervise --ssh --user pilot --password secret
    mix igniter.install bb_tui --nerves
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    * `--auto-bb` - When the robot module is missing, compose `bb.install`
      without prompting.
    * `--supervise` - Append `{BB.TUI, robot: …}` to the application's
      supervision tree. Idempotent.
    * `--ssh` - When supervising, configure the child for an SSH daemon
      (`transport: :ssh`).
    * `--port` - SSH daemon port (default `2222`). Ignored without `--ssh`.
    * `--user` - SSH username (default `admin`). Ignored without `--ssh`.
    * `--password` - SSH password (default `admin`). Ignored without `--ssh`.
    * `--nerves` - Append `BB.TUI.subsystem(<Robot>)` to
      `config :nerves_ssh, :subsystems` in `config/runtime.exs`. Idempotent.
    """

    use Igniter.Mix.Task

    alias Igniter.Code.List, as: AstList
    alias Igniter.Project.{Application, Config, Formatter, Module}

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: ["bb.install"],
        schema: [
          robot: :string,
          auto_bb: :boolean,
          supervise: :boolean,
          ssh: :boolean,
          port: :integer,
          user: :string,
          password: :string,
          nerves: :boolean
        ],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      auto_bb? = Keyword.get(options, :auto_bb, false)
      supervise? = Keyword.get(options, :supervise, false)
      nerves? = Keyword.get(options, :nerves, false)
      igniter = Formatter.import_dep(igniter, :bb_tui)
      robot_module = BB.Igniter.robot_module(igniter)
      {robot_exists?, igniter} = Module.module_exists(igniter, robot_module)

      cond do
        robot_exists? ->
          run_install(igniter, robot_module, supervise?, nerves?, options)

        auto_bb? or prompt_bb_install?() ->
          igniter
          |> Igniter.compose_task("bb.install", bb_install_argv(options))
          |> run_install(robot_module, supervise?, nerves?, options)

        true ->
          Igniter.add_notice(igniter, manual_install_notice(robot_module))
      end
    end

    defp run_install(igniter, robot_module, supervise?, nerves?, options) do
      igniter
      |> maybe_supervise(supervise?, robot_module, options)
      |> maybe_nerves(nerves?, robot_module)
      |> Igniter.add_notice(launch_notice(robot_module, supervise?, nerves?, options))
    end

    defp maybe_supervise(igniter, false, _robot_module, _options), do: igniter

    defp maybe_supervise(igniter, true, robot_module, options) do
      Application.add_new_child(
        igniter,
        {BB.TUI, {:code, child_opts_ast(robot_module, options)}}
      )
    end

    defp maybe_nerves(igniter, false, _robot_module), do: igniter

    defp maybe_nerves(igniter, true, robot_module) do
      subsystem_ast = subsystem_ast(robot_module)

      Config.configure(
        igniter,
        "runtime.exs",
        :nerves_ssh,
        [:subsystems],
        {:code, Sourceror.parse_string!("[#{Macro.to_string(subsystem_ast)}]")},
        updater: fn zipper ->
          AstList.append_new_to_list(zipper, subsystem_ast, &same_ast?/2)
        end
      )
    end

    defp subsystem_ast(robot_module) do
      Sourceror.parse_string!("BB.TUI.subsystem(#{inspect(robot_module)})")
    end

    defp same_ast?(%Sourceror.Zipper{} = left, right) do
      same_ast?(Sourceror.Zipper.node(left), right)
    end

    defp same_ast?(left, right) do
      strip_meta(left) == strip_meta(right)
    end

    defp strip_meta(ast) do
      Macro.prewalk(ast, fn
        {form, _meta, args} -> {form, [], args}
        other -> other
      end)
    end

    defp child_opts_ast(robot_module, options) do
      robot_module
      |> child_opts_string(options)
      |> Sourceror.parse_string!()
    end

    defp child_opts_string(robot_module, options) do
      if Keyword.get(options, :ssh, false) do
        port = Keyword.get(options, :port, 2222)
        user = Keyword.get(options, :user, "admin")
        password = Keyword.get(options, :password, "admin")

        """
        [
          robot: #{inspect(robot_module)},
          transport: :ssh,
          port: #{port},
          auto_host_key: true,
          auth_methods: ~c"password",
          user_passwords: [{~c"#{user}", ~c"#{password}"}]
        ]
        """
      else
        "[robot: #{inspect(robot_module)}]"
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

    defp launch_notice(robot_module, supervise?, nerves?, options) do
      cond do
        nerves? ->
          """
          bb_tui: registered as an SSH subsystem under :nerves_ssh.

          From any SSH client with access to the device:

              ssh -t <device.local> -s Elixir.BB.TUI.App

          The -t flag is required — the dashboard needs PTY allocation
          for interactive input.
          """

        supervise? and Keyword.get(options, :ssh, false) ->
          port = Keyword.get(options, :port, 2222)
          user = Keyword.get(options, :user, "admin")

          """
          bb_tui: the dashboard is supervised as part of the application and
          will serve over SSH on application start.

              ssh #{user}@localhost -p #{port}

          Adjust the credentials in the child spec before deploying.
          """

        supervise? ->
          """
          bb_tui: the dashboard is supervised as part of the application and
          will take over the terminal when the app starts.

          For an interactive session against #{inspect(robot_module)}, use
          `BB.TUI.run(#{inspect(robot_module)})` from a separate IEx shell.
          """

        true ->
          """
          bb_tui: launch the dashboard with

              mix bb.tui --robot #{inspect(robot_module)}

          or from IEx via `BB.TUI.run(#{inspect(robot_module)})`. See the BB.TUI
          moduledoc for supervised and remote-attach options.
          """
      end
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
