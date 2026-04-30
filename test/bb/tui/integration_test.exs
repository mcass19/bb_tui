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
      assert snapshot.mode == :reducer
      assert snapshot.transport == :local
      refute snapshot.polling_enabled?
      assert snapshot.dimensions == {80, 24}
    end
  end

  describe "Command result flow" do
    test "completion: a command that exits :normal yields {:ok, :completed}" do
      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        cmd_pid = spawn(fn -> :ok end)
        {:ok, cmd_pid}
      end)

      pid = start_tui_on_commands_panel!()

      :ok = Runtime.inject_event(pid, %Key{code: "enter", kind: "press"})

      eventually(fn ->
        assert current_state(pid).command_result == {:ok, :completed}
      end)

      assert current_state(pid).executing_command == nil
    end

    test "execute error: a {:error, reason} from execute_command surfaces verbatim" do
      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        {:error, :not_allowed}
      end)

      pid = start_tui_on_commands_panel!()

      :ok = Runtime.inject_event(pid, %Key{code: "enter", kind: "press"})

      eventually(fn ->
        assert current_state(pid).command_result == {:error, :not_allowed}
      end)
    end

    test "abnormal exit: a non-:normal :DOWN reason surfaces as {:error, reason}" do
      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        cmd_pid = spawn(fn -> exit(:boom) end)
        {:ok, cmd_pid}
      end)

      pid = start_tui_on_commands_panel!()

      :ok = Runtime.inject_event(pid, %Key{code: "enter", kind: "press"})

      eventually(fn ->
        assert current_state(pid).command_result == {:error, :boom}
      end)
    end

    test "timeout: a long-running command fires :command_timeout via send_after" do
      Mimic.stub(BB.Robot.Runtime, :execute, fn _robot, :home, _goal ->
        cmd_pid = spawn(fn -> Process.sleep(:infinity) end)
        {:ok, cmd_pid}
      end)

      pid = start_tui_on_commands_panel!()

      :ok = Runtime.inject_event(pid, %Key{code: "enter", kind: "press"})

      # config/test.exs sets :bb_tui, :command_timeout to 100ms.
      eventually(fn ->
        assert current_state(pid).command_result == {:error, :timeout}
      end)
    end
  end

  describe "Throbber subscription" do
    test "dormant when nothing is animating" do
      pid = start_tui!()

      # In :idle / :armed there's no throbber subscription, so the
      # throbber_step never advances on its own.
      Process.sleep(150)

      assert current_state(pid).throbber_step == 0
    end

    test "advances while safety_state is :disarming" do
      pid = start_tui!()

      # Force the dashboard into the animating state, then inject any
      # event so the runtime re-evaluates subscriptions/1 and arms the
      # 100ms interval that drives :throbber_tick.
      update_user_state(pid, fn state -> %{state | safety_state: :disarming} end)
      :ok = Runtime.inject_event(pid, %Key{code: "noop", kind: "press"})

      eventually(fn ->
        assert current_state(pid).throbber_step > 0
      end)
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

  defp start_tui_on_commands_panel! do
    pid = start_tui!()

    # Seed a Ready command so Enter has something to execute.
    update_user_state(pid, fn state ->
      %{
        state
        | active_panel: :commands,
          commands: [%{name: :home, allowed_states: [:idle]}],
          command_selected: 0,
          runtime_state: :idle
      }
    end)

    pid
  end

  defp update_user_state(pid, fun) do
    :sys.replace_state(pid, fn server_state ->
      %{server_state | user_state: fun.(server_state.user_state)}
    end)
  end

  # Polls `assertion_fn` every 25ms until it succeeds or 2 seconds elapse.
  # The reducer runs commands and subscriptions on the live server, so
  # results land asynchronously — we have to wait for the mailbox round-trip.
  defp eventually(assertion_fn, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_eventually(assertion_fn, deadline)
  end

  defp do_eventually(assertion_fn, deadline) do
    assertion_fn.()
  rescue
    ExUnit.AssertionError ->
      if System.monotonic_time(:millisecond) >= deadline do
        # Final attempt — let the assertion error propagate.
        assertion_fn.()
      else
        Process.sleep(25)
        do_eventually(assertion_fn, deadline)
      end
  end
end
