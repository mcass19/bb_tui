defmodule BB.TUI.IntegrationTest do
  @moduledoc """
  End-to-end tests exercising a real `ExRatatui.Server` running the `BB.TUI.App`
  callback runtime under `test_mode`. Events are delivered via
  `ExRatatui.Runtime.inject_event/2` so we drive the app the same way the poll
  loop would — no direct `handle_event/2` calls, no mocked server state.

  These tests complement the pure-function unit tests in `BB.TUI.AppTest` and
  `BB.TUI.StateTest`: they lock in the invariant that wiring through
  `ExRatatui.Server` (mount → render → inject → render) produces the state
  transitions the unit tests describe.
  """

  use ExUnit.Case, async: false
  use Mimic

  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Event.Key
  alias ExRatatui.Runtime

  setup :set_mimic_global

  setup do
    Fixtures.stub_bb_modules()
    :ok
  end

  describe "running under test_mode" do
    test "a tab key press advances the active panel" do
      pid = start_tui!()

      # Mount seed — safety panel is active first.
      assert :safety = current_panel(pid)

      :ok = Runtime.inject_event(pid, %Key{code: "tab", kind: "press"})
      assert :commands = current_panel(pid)

      :ok = Runtime.inject_event(pid, %Key{code: "tab", kind: "press"})
      assert :joints = current_panel(pid)
    end

    test "arming publishes through BB.Safety.arm" do
      test_pid = self()

      Mimic.stub(BB.Safety, :arm, fn _robot ->
        send(test_pid, :armed)
        :ok
      end)

      pid = start_tui!()

      :ok = Runtime.inject_event(pid, %Key{code: "a", kind: "press"})

      assert_receive :armed, 500
    end

    test "toggling help flips the show_help flag" do
      pid = start_tui!()

      refute current_state(pid).show_help

      :ok = Runtime.inject_event(pid, %Key{code: "?", kind: "press"})
      assert current_state(pid).show_help

      :ok = Runtime.inject_event(pid, %Key{code: "?", kind: "press"})
      refute current_state(pid).show_help
    end

    test "enabling trace captures injected events" do
      pid = start_tui!()

      :ok = Runtime.enable_trace(pid, limit: 50)
      :ok = Runtime.inject_event(pid, %Key{code: "tab", kind: "press"})

      # Allow the server to process and record the trace event before reading.
      _ = :sys.get_state(pid)

      events = Runtime.trace_events(pid)

      assert Enum.any?(events, fn e ->
               e.kind == :message and
                 match?(%{source: :event, payload: %Key{code: "tab"}}, e.details)
             end)
    end

    test "snapshot reflects headless test_mode" do
      pid = start_tui!()

      snapshot = Runtime.snapshot(pid)

      assert snapshot.mod == BB.TUI.App
      assert snapshot.mode in [:callbacks, :reducer]
      assert snapshot.transport == :local
      refute snapshot.polling_enabled?
      assert snapshot.dimensions == {80, 24}
    end
  end

  defp start_tui! do
    {:ok, pid} =
      BB.TUI.start(BB.TUI.TestRobot,
        test_mode: {80, 24},
        name: nil
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    Process.unlink(pid)
    pid
  end

  defp current_state(pid) do
    :sys.get_state(pid).user_state
  end

  defp current_panel(pid) do
    current_state(pid).active_panel
  end
end
