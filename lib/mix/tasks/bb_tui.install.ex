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

    With `--ssh`, the installer appends a supervised `{BB.TUI, robot: …}`
    child to the application that boots an SSH daemon on application
    start. Use this when the dashboard should be reachable remotely.

    With `--nerves`, the installer registers `BB.TUI.subsystem/1` under
    `config :nerves_ssh, :subsystems` in `config/runtime.exs`. Use this
    on Nerves devices that already run `nerves_ssh` so the dashboard
    rides on the existing daemon instead of opening a second SSH port.

    With `--web`, the installer serves the dashboard in the browser through
    the optional `phoenix_ex_ratatui` dependency: it adds the dependency,
    generates a `use BB.TUI.Live` LiveView under the web namespace
    (`MyAppWeb.RobotLive` for `MyApp.Robot`), mounts it with a `live`
    route inside the router's `:browser` scope (`/robot` by default, or
    `--path`), and registers the JS hook in `assets/js/app.js`. This needs
    a Phoenix router in the project; without one the installer prints the
    manual wiring instead of guessing.

    Without `--ssh`, `--nerves`, or `--web`, no supervision is wired up:
    launch the dashboard on demand with `mix bb.tui` or `BB.TUI.run/1`
    from IEx. Auto-claiming the local terminal would fight an IEx session
    for stdin/stdout.

    ## Examples

    ```bash
    mix igniter.install bb_tui
    mix igniter.install bb_tui --robot MyApp.Arm
    mix igniter.install bb_tui --auto-bb
    mix igniter.install bb_tui --ssh
    mix igniter.install bb_tui --ssh --port 2222
    mix igniter.install bb_tui --ssh --user pilot --password secret
    mix igniter.install bb_tui --nerves
    mix igniter.install bb_tui --web
    mix igniter.install bb_tui --web --path /dashboard
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    * `--auto-bb` - When the robot module is missing, compose `bb.install`
      without prompting.
    * `--ssh` - Append a supervised SSH-mode `{BB.TUI, …}` child to the
      application's supervision tree. Idempotent.
    * `--port` - SSH daemon port (default `2222`). Ignored without `--ssh`.
    * `--user` - SSH username (default `admin`). Ignored without `--ssh`.
    * `--password` - SSH password (default `admin`). Ignored without `--ssh`.
    * `--nerves` - Append `BB.TUI.subsystem(<Robot>)` to
      `config :nerves_ssh, :subsystems` in `config/runtime.exs`. Idempotent.
    * `--web` - Add `phoenix_ex_ratatui`, generate a `BB.TUI.Live` LiveView,
      mount it in the Phoenix router, and register the JS hook. Idempotent.
    * `--path` - URL path for the browser dashboard (defaults to the robot's
      last name segment, `/robot` for `MyApp.Robot`). Ignored without `--web`.
    """

    use Igniter.Mix.Task

    alias Igniter.Code.List, as: AstList
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.{Application, Config, Deps, Formatter, Module}

    @phoenix_ex_ratatui_dep {:phoenix_ex_ratatui, "~> 0.2"}
    @hook "PhoenixExRatatuiHook"
    @hook_import ~s|import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"\n|
    @app_js "assets/js/app.js"

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: ["bb.install"],
        schema: [
          robot: :string,
          auto_bb: :boolean,
          ssh: :boolean,
          port: :integer,
          user: :string,
          password: :string,
          nerves: :boolean,
          web: :boolean,
          path: :string
        ],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      auto_bb? = Keyword.get(options, :auto_bb, false)
      igniter = Formatter.import_dep(igniter, :bb_tui)
      robot_module = BB.Igniter.robot_module(igniter)
      {robot_exists?, igniter} = Module.module_exists(igniter, robot_module)

      cond do
        robot_exists? ->
          run_install(igniter, robot_module, options)

        auto_bb? or prompt_bb_install?() ->
          igniter
          |> Igniter.compose_task("bb.install", bb_install_argv(options))
          |> run_install(robot_module, options)

        true ->
          Igniter.add_notice(igniter, manual_install_notice(robot_module))
      end
    end

    defp run_install(igniter, robot_module, options) do
      ssh? = Keyword.get(options, :ssh, false)
      nerves? = Keyword.get(options, :nerves, false)
      web? = Keyword.get(options, :web, false)

      igniter
      |> maybe_supervise_ssh(ssh?, robot_module, options)
      |> maybe_nerves(nerves?, robot_module)
      |> Igniter.add_notice(launch_notice(robot_module, ssh?, nerves?, options))
      |> maybe_web(web?, robot_module, options)
    end

    defp maybe_supervise_ssh(igniter, false, _robot_module, _options), do: igniter

    defp maybe_supervise_ssh(igniter, true, robot_module, options) do
      Application.add_new_child(
        igniter,
        {BB.TUI, {:code, child_opts_ast(robot_module, options)}},
        after: [robot_module]
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

    # --web: the browser transport. Everything hangs off the presence of a
    # Phoenix router — without one there is nothing to mount the LiveView
    # in, so the installer explains the manual wiring instead of guessing.
    defp maybe_web(igniter, false, _robot_module, _options), do: igniter

    defp maybe_web(igniter, true, robot_module, options) do
      live_module = live_module(igniter, robot_module)
      path = Keyword.get(options, :path, default_web_path(robot_module))

      case Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_notice(igniter, manual_web_notice(live_module, robot_module, path))

        {igniter, router} ->
          {live_exists?, igniter} = Module.module_exists(igniter, live_module)

          igniter
          |> Deps.add_dep(@phoenix_ex_ratatui_dep, on_exists: :skip)
          |> scaffold_live(live_exists?, router, live_module, robot_module, path)
          |> register_hook()
          |> Igniter.add_notice(web_notice(live_module, path))
      end
    end

    # An existing LiveView means a previous run already mounted it; the
    # route is left alone so a hand-edited path or scope survives.
    defp scaffold_live(igniter, true, _router, _live_module, _robot_module, _path), do: igniter

    defp scaffold_live(igniter, false, router, live_module, robot_module, path) do
      igniter
      |> create_live_module(live_module, robot_module)
      |> mount_live_route(router, live_module, path)
    end

    defp create_live_module(igniter, live_module, robot_module) do
      contents = """
      @moduledoc \"\"\"
      The #{inspect(robot_module)} dashboard in the browser.

      Every connected tab runs its own isolated `BB.TUI` session over the
      shared robot, like concurrent SSH clients. Override `tui_mount_opts/1`
      to derive the mount options from the socket instead.
      \"\"\"

      use BB.TUI.Live, robot: #{inspect(robot_module)}
      """

      # Igniter's own placement (`lib/my_app_web/robot_live.ex`) rather than
      # Phoenix's `live/` folder: igniter relocates every new module to its
      # computed location on apply, so a custom path would only move back.
      Module.create_module(igniter, live_module, contents)
    end

    # Mounted inside the web module's `:browser` scope, so the route names
    # the LiveView by its suffix — the scope alias supplies the prefix.
    defp mount_live_route(igniter, router, live_module, path) do
      web_module = Phoenix.web_module(igniter)
      route = "live #{inspect(path)}, #{inspect(live_suffix(live_module))}"

      Phoenix.append_to_scope(igniter, "/", route,
        router: router,
        arg2: web_module,
        with_pipelines: [:browser]
      )
    end

    defp live_module(igniter, robot_module) do
      Elixir.Module.concat(Phoenix.web_module(igniter), "#{robot_name(robot_module)}Live")
    end

    defp live_suffix(live_module) do
      live_module |> Elixir.Module.split() |> List.last() |> List.wrap() |> Elixir.Module.concat()
    end

    defp robot_name(robot_module) do
      robot_module |> Elixir.Module.split() |> List.last()
    end

    defp default_web_path(robot_module) do
      "/" <> Macro.underscore(robot_name(robot_module))
    end

    # The hook registration is a plain-text edit of app.js — there is no AST
    # to lean on — so it recognises the two shapes Phoenix generates and
    # falls back to a warning with the snippet for anything else.
    defp register_hook(igniter) do
      if Igniter.exists?(igniter, @app_js) do
        Igniter.update_file(igniter, @app_js, &update_app_js/1)
      else
        Igniter.add_warning(igniter, manual_hook_warning())
      end
    end

    defp update_app_js(source) do
      content = Rewrite.Source.get(source, :content)

      case wire_hook(content) do
        {:ok, ^content} -> source
        {:ok, updated} -> Rewrite.Source.update(source, :content, updated)
        :error -> {:warning, manual_hook_warning()}
      end
    end

    defp wire_hook(content) do
      if String.contains?(content, @hook) do
        {:ok, content}
      else
        with {:ok, content} <- add_hook_to_live_socket(content) do
          {:ok, add_hook_import(content)}
        end
      end
    end

    # `hooks: {...colocatedHooks}` (Phoenix 1.8) gains the hook as its first
    # entry; an options object without `hooks:` (Phoenix 1.7) gains the key.
    defp add_hook_to_live_socket(content) do
      cond do
        Regex.match?(~r/hooks:\s*\{/, content) ->
          {:ok, Regex.replace(~r/hooks:\s*\{/, content, "hooks: {#{@hook}, ", global: false)}

        Regex.match?(~r/new LiveSocket\([^{]*\{/, content) ->
          {:ok,
           Regex.replace(~r/(new LiveSocket\([^{]*\{)/, content, "\\1\n  hooks: {#{@hook}},",
             global: false
           )}

        true ->
          :error
      end
    end

    defp add_hook_import(content) do
      case Regex.scan(~r/^import .*\n/m, content, return: :index) do
        [] ->
          @hook_import <> content

        matches ->
          [{start, length}] = List.last(matches)
          split_at = start + length
          head = binary_part(content, 0, split_at)
          tail = binary_part(content, split_at, byte_size(content) - split_at)
          head <> @hook_import <> tail
      end
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

    defp launch_notice(robot_module, ssh?, nerves?, options) do
      cond do
        nerves? ->
          """
          bb_tui: registered as an SSH subsystem under :nerves_ssh.

          From any SSH client with access to the device:

              ssh -t <device.local> -s Elixir.BB.TUI.App

          The -t flag is required — the dashboard needs PTY allocation
          for interactive input.
          """

        ssh? ->
          port = Keyword.get(options, :port, 2222)
          user = Keyword.get(options, :user, "admin")

          """
          bb_tui: the dashboard is supervised as part of the application and
          will serve over SSH on application start.

              ssh #{user}@localhost -p #{port}

          Adjust the credentials in the child spec before deploying.
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

    defp web_notice(live_module, path) do
      """
      bb_tui: the dashboard is mounted in the browser at #{path}
      (#{inspect(live_module)}, through the optional phoenix_ex_ratatui
      dependency). Fetch it, then open the route under the running endpoint:

          mix deps.get
          http://localhost:4000#{path}

      The hook import in assets/js/app.js resolves from deps/ through the
      default esbuild NODE_PATH. An npm-managed assets/ directory needs
      "phoenix_ex_ratatui": "file:../deps/phoenix_ex_ratatui" in its
      package.json instead.
      """
    end

    defp manual_web_notice(live_module, robot_module, path) do
      """
      bb_tui: --web needs a Phoenix router and none was found, so nothing
      was wired for the browser. Set up a Phoenix endpoint and router first
      and re-run

          mix igniter.install bb_tui --web

      or wire the browser transport by hand: add
      #{inspect(@phoenix_ex_ratatui_dep)} to the deps, define

          defmodule #{inspect(live_module)} do
            use BB.TUI.Live, robot: #{inspect(robot_module)}
          end

      route to it with `live #{inspect(path)}, #{inspect(live_module)}`, and
      register #{@hook} in assets/js/app.js.
      """
    end

    defp manual_hook_warning do
      """
      bb_tui: could not register the phoenix_ex_ratatui hook in #{@app_js}.
      Add it by hand — the dashboard renders nothing without it:

          import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: { PhoenixExRatatuiHook },
            // ...existing options
          })
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
