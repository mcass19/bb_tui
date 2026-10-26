defmodule BB.TUI.DistributedTest do
  # Drives a dashboard attached with `node:` to a real robot on a `:peer` node,
  # so the remote paths run over actual distribution rather than a mocked
  # `BB.TUI.Rpc`. Mocks can't catch node-local state on the wrong node — the
  # remote command await read the dashboard node's ResultCache and reported
  # `:noproc` for every quick command until it was routed to the robot's node.
  use ExUnit.Case

  @moduletag :distributed

  alias BB.TUI.App
  alias BB.TUI.Test.PeerHelper
  alias BB.TUI.Test.RemoteRobot
  alias ExRatatui.Event.Key
  alias ExRatatui.Runtime

  # Excluded by default via test_helper.exs.
  # Run with: elixir --sname test -S mix test --only distributed
  setup do
    unless Node.alive?() do
      flunk(
        "Node is not distributed. " <>
          "Run with: elixir --sname test -S mix test --only distributed"
      )
    end

    # The peer sees every compiled BEAM file: bb_tui, deps, test/support (the
    # robot fixture and PeerHelper), and Elixir with its sibling applications —
    # bb needs `:logger`.
    code_paths =
      Path.wildcard("_build/test/lib/*/ebin") ++
        Path.wildcard(Path.join([:code.lib_dir(:elixir), "..", "*", "ebin"]))

    args = Enum.flat_map(code_paths, fn path -> [~c"-pa", String.to_charlist(path)] end)

    peer_name = :"bb_tui_peer_#{System.unique_integer([:positive])}"
    {:ok, peer_pid, peer_node} = :peer.start(%{name: peer_name, args: args})
    on_exit(fn -> :peer.stop(peer_pid) end)

    {:ok, _robot} = :rpc.call(peer_node, PeerHelper, :start_robot_unlinked, [RemoteRobot])

    {:ok, tui} =
      App.start_link(robot: RemoteRobot, node: peer_node, test_mode: {120, 40}, name: nil)

    # Linked to the test process, so the dashboard goes down with it.

    press(tui, "a")
    eventually(fn -> assert user_state(tui).safety.state == :armed end)

    {:ok, tui: tui, peer_node: peer_node}
  end

  test "a quick command reports its real result", %{tui: tui} do
    select_command(tui, :home)

    for _run <- 1..3 do
      press(tui, "enter")
      eventually(fn -> assert user_state(tui).commands.result == {:ok, %{}} end)
      :sys.replace_state(tui, &put_in(&1.user_state.commands.result, nil))
    end
  end

  test "a running command is listed and cancelled across nodes", %{tui: tui, peer_node: peer} do
    {:ok, _pid} = :rpc.call(peer, BB.Robot.Runtime, :execute, [RemoteRobot, :calibrate, %{}])

    eventually(fn -> assert [%{name: :calibrate}] = user_state(tui).commands.running end)

    select_command(tui, :calibrate)
    press(tui, "c")

    eventually(fn ->
      assert user_state(tui).commands.running == []

      assert Enum.any?(
               user_state(tui).events.list,
               &match?({_, [:command, :calibrate, _], _}, &1)
             )
    end)

    assert [] = :rpc.call(peer, BB.Command, :list, [RemoteRobot])
  end

  test "refusals come back across nodes", %{tui: tui} do
    press(tui, "a")

    eventually(fn ->
      assert Enum.any?(
               user_state(tui).events.list,
               &match?({_, [:safety, :arm], %{payload: %{error: :already_armed}}}, &1)
             )
    end)
  end

  test "a jog drives the remote actuator and its feedback comes back", %{tui: tui} do
    press(tui, "3")
    press(tui, "L")

    eventually(fn ->
      %{position: position, target: target} = user_state(tui).joints.entries.shoulder
      assert position > 0.0
      assert target == nil
    end)
  end

  defp select_command(tui, name) do
    press(tui, "2")
    index = Enum.find_index(user_state(tui).commands.available, &(&1.name == name))
    :sys.replace_state(tui, &put_in(&1.user_state.commands.selected, index))
  end

  defp press(tui, code) do
    :ok = Runtime.inject_event(tui, %Key{code: code, kind: "press"})
    _ = :sys.get_state(tui)
    :ok
  end

  defp user_state(tui), do: :sys.get_state(tui).user_state

  defp eventually(fun, attempts \\ 50) do
    fun.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if attempts > 0 do
        Process.sleep(50)
        eventually(fun, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
