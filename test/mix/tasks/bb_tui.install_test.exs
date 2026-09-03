defmodule Mix.Tasks.BbTui.InstallTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import Igniter.Test

  @moduletag :igniter

  defp project_with_robot do
    test_project()
    |> Igniter.compose_task("bb.install")
    |> apply_igniter!()
  end

  describe "robot module already present" do
    test "prints a launch notice with the default robot module" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install")
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Robot"))
    end

    test "uses a custom robot module when --robot is given" do
      test_project()
      |> Igniter.compose_task("bb.add_robot", ["--robot", "Test.Arms.Left"])
      |> apply_igniter!()
      |> Igniter.compose_task("bb_tui.install", ["--robot", "Test.Arms.Left"])
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Arms.Left"))
    end

    test "mentions the BB.TUI.run helper in the launch notice" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install")
      |> assert_has_notice(&String.contains?(&1, "BB.TUI.run(Test.Robot)"))
    end

    test "imports bb_tui into .formatter.exs" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install")
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:bb_tui, :bb]
      """)
    end

    test "does not re-run bb.install when the robot already exists" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--auto-bb"])
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Robot"))
    end
  end

  describe "robot module missing" do
    test "with --auto-bb composes bb.install and scaffolds the default robot" do
      test_project()
      |> Igniter.compose_task("bb_tui.install", ["--auto-bb"])
      |> assert_creates("lib/test/robot.ex")
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Robot"))
    end

    test "forwards --robot to the composed bb.install" do
      test_project()
      |> Igniter.compose_task("bb_tui.install", ["--auto-bb", "--robot", "Test.Arms.Left"])
      |> assert_creates("lib/test/arms/left.ex")
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Arms.Left"))
    end

    test "without --auto-bb falls back to a manual-install notice" do
      capture_io(fn ->
        test_project()
        |> Igniter.compose_task("bb_tui.install")
        |> assert_has_notice(&String.contains?(&1, "no robot module found"))
        |> assert_has_notice(&String.contains?(&1, "--auto-bb"))
      end)
    end
  end

  describe "--ssh" do
    test "appends a supervised SSH child after the robot in the application" do
      igniter =
        project_with_robot()
        |> Igniter.compose_task("bb_tui.install", ["--ssh"])

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |    children = [
      """)

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |         transport: :ssh,
      + |         port: 2222,
      """)

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |         auth_methods: ~c"password",
      """)

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |         user_passwords: [{~c"admin", ~c"admin"}]
      """)

      assert_has_notice(igniter, &String.contains?(&1, "ssh admin@localhost -p 2222"))
    end

    test "honours --port / --user / --password overrides" do
      igniter =
        project_with_robot()
        |> Igniter.compose_task("bb_tui.install", [
          "--ssh",
          "--port",
          "3333",
          "--user",
          "pilot",
          "--password",
          "secret"
        ])

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |         port: 3333,
      """)

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |         user_passwords: [{~c"pilot", ~c"secret"}]
      """)

      assert_has_notice(igniter, &String.contains?(&1, "ssh pilot@localhost -p 3333"))
    end

    test "is idempotent on a second run" do
      first =
        project_with_robot()
        |> Igniter.compose_task("bb_tui.install", ["--ssh"])
        |> apply_igniter!()

      first
      |> Igniter.compose_task("bb_tui.install", ["--ssh"])
      |> assert_unchanged("lib/test/application.ex")
    end

    test "supervises SSH child after composing bb.install when robot is missing" do
      test_project()
      |> Igniter.compose_task("bb_tui.install", ["--auto-bb", "--ssh"])
      |> assert_creates("lib/test/application.ex")
    end
  end

  describe "--nerves" do
    test "registers BB.TUI.subsystem under :nerves_ssh in runtime.exs" do
      igniter =
        project_with_robot()
        |> Igniter.compose_task("bb_tui.install", ["--nerves"])

      assert_has_patch(igniter, "config/runtime.exs", """
      + |config :nerves_ssh, subsystems: [BB.TUI.subsystem(Test.Robot)]
      """)

      assert_has_notice(igniter, &String.contains?(&1, "ssh -t <device.local>"))
    end

    test "appends to an existing :nerves_ssh subsystems list" do
      runtime_exs = """
      import Config

      config :nerves_ssh, subsystems: [:ssh_sftpd.subsystem_spec(cwd: ~c"/")]
      """

      test_project(files: %{"config/runtime.exs" => runtime_exs})
      |> Igniter.compose_task("bb.install")
      |> apply_igniter!()
      |> Igniter.compose_task("bb_tui.install", ["--nerves"])
      |> assert_has_patch("config/runtime.exs", """
      + |  subsystems: [:ssh_sftpd.subsystem_spec(cwd: ~c"/"), BB.TUI.subsystem(Test.Robot)]
      """)
    end

    test "is idempotent on a second run" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--nerves"])
      |> apply_igniter!()
      |> Igniter.compose_task("bb_tui.install", ["--nerves"])
      |> assert_unchanged("config/runtime.exs")
    end

    test "does not touch runtime.exs when the flag is absent" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install")
      |> assert_unchanged("config/runtime.exs")
    end
  end

  describe "--web" do
    @router """
    defmodule TestWeb.Router do
      use Phoenix.Router
      import Phoenix.LiveView.Router

      pipeline :browser do
        plug(:accepts, ["html"])
      end

      scope "/", TestWeb do
        pipe_through(:browser)

        get("/", PageController, :home)
      end
    end
    """

    # What `mix phx.new` generates on Phoenix 1.8 — hooks already present.
    @app_js_1_8 """
    import "phoenix_html"
    import {Socket} from "phoenix"
    import {LiveSocket} from "phoenix_live_view"
    import {hooks as colocatedHooks} from "phoenix-colocated/test"

    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    const liveSocket = new LiveSocket("/live", Socket, {
      longPollFallbackMs: 2500,
      params: {_csrf_token: csrfToken},
      hooks: {...colocatedHooks},
    })

    liveSocket.connect()
    """

    # Phoenix 1.7 shape — no `hooks:` key on the LiveSocket options.
    @app_js_1_7 """
    import {Socket} from "phoenix"
    import {LiveSocket} from "phoenix_live_view"

    const liveSocket = new LiveSocket("/live", Socket, {
      params: {_csrf_token: csrfToken}
    })

    liveSocket.connect()
    """

    defp phx_project_with_robot(files \\ %{}) do
      test_project(files: Map.merge(%{"lib/test_web/router.ex" => @router}, files))
      |> Igniter.compose_task("bb.install")
      |> apply_igniter!()
    end

    test "adds the optional phoenix_ex_ratatui dependency" do
      phx_project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_patch("mix.exs", """
      + |      {:phoenix_ex_ratatui, "~> 0.2"}
      """)
    end

    test "generates a BB.TUI.Live LiveView under the web namespace" do
      igniter =
        phx_project_with_robot()
        |> Igniter.compose_task("bb_tui.install", ["--web"])

      assert_creates(igniter, "lib/test_web/robot_live.ex", """
      defmodule TestWeb.RobotLive do
        @moduledoc \"\"\"
        The Test.Robot dashboard in the browser.

        Every connected tab runs its own isolated `BB.TUI` session over the
        shared robot, like concurrent SSH clients. Override `tui_mount_opts/1`
        to derive the mount options from the socket instead.
        \"\"\"

        use BB.TUI.Live, robot: Test.Robot
      end
      """)
    end

    test "mounts a live route inside the web module's :browser scope" do
      phx_project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_patch("lib/test_web/router.ex", """
        |    get("/", PageController, :home)
      + |    live("/robot", RobotLive)
      """)
    end

    test "honours --path for the route" do
      phx_project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web", "--path", "/dashboard"])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |    live("/dashboard", RobotLive)
      """)
      |> assert_has_notice(&String.contains?(&1, "http://localhost:4000/dashboard"))
    end

    test "derives the LiveView name and path from the robot module" do
      igniter =
        test_project(files: %{"lib/test_web/router.ex" => @router})
        |> Igniter.compose_task("bb.add_robot", ["--robot", "Test.Arms.Left"])
        |> apply_igniter!()
        |> Igniter.compose_task("bb_tui.install", ["--web", "--robot", "Test.Arms.Left"])

      assert_creates(igniter, "lib/test_web/left_live.ex", """
      defmodule TestWeb.LeftLive do
        @moduledoc \"\"\"
        The Test.Arms.Left dashboard in the browser.

        Every connected tab runs its own isolated `BB.TUI` session over the
        shared robot, like concurrent SSH clients. Override `tui_mount_opts/1`
        to derive the mount options from the socket instead.
        \"\"\"

        use BB.TUI.Live, robot: Test.Arms.Left
      end
      """)

      assert_has_patch(igniter, "lib/test_web/router.ex", """
      + |    live("/left", LeftLive)
      """)
    end

    test "registers the hook in a Phoenix 1.8 app.js that already declares hooks" do
      igniter =
        phx_project_with_robot(%{"assets/js/app.js" => @app_js_1_8})
        |> Igniter.compose_task("bb_tui.install", ["--web"])

      assert_has_patch(igniter, "assets/js/app.js", """
        |import {hooks as colocatedHooks} from "phoenix-colocated/test"
      + |import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"
      """)

      assert_has_patch(igniter, "assets/js/app.js", """
      - |  hooks: {...colocatedHooks},
      + |  hooks: {PhoenixExRatatuiHook, ...colocatedHooks},
      """)
    end

    test "adds a hooks key to a Phoenix 1.7 app.js without one" do
      igniter =
        phx_project_with_robot(%{"assets/js/app.js" => @app_js_1_7})
        |> Igniter.compose_task("bb_tui.install", ["--web"])

      assert_has_patch(igniter, "assets/js/app.js", """
        |import {LiveSocket} from "phoenix_live_view"
      + |import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"
      """)

      assert_has_patch(igniter, "assets/js/app.js", """
        |const liveSocket = new LiveSocket("/live", Socket, {
      + |  hooks: {PhoenixExRatatuiHook},
        |  params: {_csrf_token: csrfToken}
      """)
    end

    test "prepends the import when app.js has no import lines" do
      app_js = """
      const liveSocket = new LiveSocket("/live", Socket, {})
      """

      phx_project_with_robot(%{"assets/js/app.js" => app_js})
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_content_equals("assets/js/app.js", """
      import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"
      const liveSocket = new LiveSocket("/live", Socket, {
        hooks: {PhoenixExRatatuiHook},})
      """)
    end

    test "warns with the manual snippet when app.js is missing" do
      phx_project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_warning(
        &String.contains?(&1, "could not register the phoenix_ex_ratatui hook")
      )
    end

    test "warns with the manual snippet when app.js has no LiveSocket" do
      app_js = """
      import "phoenix_html"
      console.log("no live socket here")
      """

      phx_project_with_robot(%{"assets/js/app.js" => app_js})
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_warning(
        &String.contains?(&1, "could not register the phoenix_ex_ratatui hook")
      )
      |> assert_unchanged("assets/js/app.js")
    end

    test "leaves an app.js that already registers the hook untouched" do
      app_js = """
      import { PhoenixExRatatuiHook } from "phoenix_ex_ratatui"

      const liveSocket = new LiveSocket("/live", Socket, {
        hooks: { PhoenixExRatatuiHook }
      })
      """

      phx_project_with_robot(%{"assets/js/app.js" => app_js})
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_unchanged("assets/js/app.js")
    end

    test "is idempotent on a second run" do
      first =
        phx_project_with_robot(%{"assets/js/app.js" => @app_js_1_8})
        |> Igniter.compose_task("bb_tui.install", ["--web"])
        |> apply_igniter!()

      first
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_unchanged([
        "mix.exs",
        "lib/test_web/router.ex",
        "lib/test_web/robot_live.ex",
        "assets/js/app.js"
      ])
    end

    test "prints the manual wiring when the project has no Phoenix router" do
      project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_notice(&String.contains?(&1, "--web needs a Phoenix router"))
      |> assert_has_notice(&String.contains?(&1, "use BB.TUI.Live, robot: Test.Robot"))
      |> refute_creates("lib/test_web/robot_live.ex")
      |> assert_unchanged("mix.exs")
    end

    test "scaffolds the robot first when composed with --auto-bb" do
      test_project(files: %{"lib/test_web/router.ex" => @router})
      |> Igniter.compose_task("bb_tui.install", ["--auto-bb", "--web"])
      |> assert_creates("lib/test/robot.ex")
      |> assert_creates("lib/test_web/robot_live.ex")
    end

    test "still prints the terminal launch notice alongside the web one" do
      phx_project_with_robot()
      |> Igniter.compose_task("bb_tui.install", ["--web"])
      |> assert_has_notice(&String.contains?(&1, "mix bb.tui --robot Test.Robot"))
      |> assert_has_notice(&String.contains?(&1, "mounted in the browser at /robot"))
    end
  end
end
