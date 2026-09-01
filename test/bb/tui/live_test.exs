defmodule BB.TUI.LiveTest do
  use ExUnit.Case, async: false
  use Mimic

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BB.TUI.Test.Fixtures

  @endpoint BB.TUI.Test.Endpoint

  setup :set_mimic_global
  setup :verify_on_exit!

  defmodule RobotLive do
    use BB.TUI.Live, robot: BB.TUI.TestRobot
  end

  defmodule CustomOptsLive do
    use BB.TUI.Live, robot: BB.TUI.TestRobot

    def tui_mount_opts(_socket), do: [robot: BB.TUI.TestRobot, subscribe_paths: [[:sensor]]]
  end

  describe "use BB.TUI.Live" do
    test "boots the dashboard and pushes the first full frame on resize" do
      Fixtures.stub_bb_modules()

      {:ok, view, _html} = live_isolated(build_conn(), RobotLive)

      view
      |> element("#phoenix-ex-ratatui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 100, "rows" => 30})

      assert_push_event(
        view,
        "phx_ex_ratatui:render",
        %{"width" => 100, "height" => 30, "ops" => ops},
        2_000
      )

      assert length(ops) == 100 * 30

      text = Enum.map_join(ops, &Enum.at(&1, 2))
      assert text =~ "Parameters"
    end

    test "browser key input reaches the dashboard and triggers a redraw" do
      Fixtures.stub_bb_modules()

      {:ok, view, _html} = live_isolated(build_conn(), RobotLive)

      view
      |> element("#phoenix-ex-ratatui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 100, "rows" => 30})

      assert_push_event(view, "phx_ex_ratatui:render", %{"ops" => _first_frame}, 2_000)

      view
      |> element("#phoenix-ex-ratatui")
      |> render_hook("phx_ex_ratatui:input", %{
        "kind" => "key",
        "code" => "tab",
        "modifiers" => [],
        "press_kind" => "press"
      })

      assert_push_event(view, "phx_ex_ratatui:render", %{"ops" => diff}, 2_000)
      assert diff != []
    end

    test "tui_mount_opts is overridable and reaches the app's init" do
      Fixtures.stub_bb_modules()
      test_pid = self()

      Mimic.expect(BB.TUI.App, :init, fn opts ->
        send(test_pid, {:mount_opts, opts})
        {:ok, :halt_here}
      end)

      Mimic.stub(BB.TUI.App, :subscriptions, fn _state -> [] end)
      Mimic.stub(BB.TUI.App, :render, fn _state, _frame -> [] end)

      {:ok, view, _html} = live_isolated(build_conn(), CustomOptsLive)

      view
      |> element("#phoenix-ex-ratatui")
      |> render_hook("phx_ex_ratatui:resize", %{"cols" => 80, "rows" => 24})

      assert_receive {:mount_opts, opts}, 2_000
      assert opts[:robot] == BB.TUI.TestRobot
      assert opts[:subscribe_paths] == [[:sensor]]
    end
  end
end
