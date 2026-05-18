defmodule Mix.Tasks.BbTui.InstallTest do
  use ExUnit.Case
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

      assert_creates(igniter, "config/runtime.exs", """
      import Config
      config :nerves_ssh, subsystems: [BB.TUI.subsystem(Test.Robot)]
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
end
