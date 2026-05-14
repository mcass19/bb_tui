defmodule Mix.Tasks.BbTui.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  defp project_with_robot do
    test_project()
    |> Igniter.compose_task("bb.install")
    |> apply_igniter!()
  end

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
end
