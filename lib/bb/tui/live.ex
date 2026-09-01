if Code.ensure_loaded?(PhoenixExRatatui.LiveView) do
  defmodule BB.TUI.Live do
    @moduledoc """
    The dashboard as a Phoenix LiveView — the browser transport.

    Available when the optional [`phoenix_ex_ratatui`](https://hex.pm/packages/phoenix_ex_ratatui)
    dependency is present; without it this module is not compiled. Add it
    next to `bb_tui`:

        {:bb_tui, "~> #{Mix.Project.config()[:version] |> String.split(".") |> Enum.take(2) |> Enum.join(".")}"},
        {:phoenix_ex_ratatui, "~> 0.2"}

    Define a LiveView and route to it like any other:

        defmodule MyAppWeb.RobotLive do
          use BB.TUI.Live, robot: MyApp.Robot
        end

        # router.ex
        live "/robot", MyAppWeb.RobotLive

    The `use` options are the dashboard's mount options — the same keyword
    list `BB.TUI.start/2` takes (`:robot` is required; `:node`,
    `:subscribe_paths`, and `:renderers` pass through). For per-session
    options — picking the robot from the session or params — override
    `tui_mount_opts/1`, which receives the LiveView socket after `mount`:

        defmodule MyAppWeb.RobotLive do
          use BB.TUI.Live, robot: MyApp.Robot

          def tui_mount_opts(socket) do
            [robot: socket.assigns.robot]
          end
        end

    Each browser connection runs its own isolated dashboard session over
    the shared robot, exactly as concurrent SSH clients do. The JS side
    needs `phoenix_ex_ratatui`'s hook registered once in `app.js` — see
    the [phoenix_ex_ratatui docs](https://hexdocs.pm/phoenix_ex_ratatui)
    and the `dev/web` demo endpoint in this repository for the wiring.
    """

    defmacro __using__(opts) do
      quote bind_quoted: [opts: opts] do
        use PhoenixExRatatui.LiveView, runtime: :reducer

        @bb_tui_live_opts opts

        @doc false
        def tui_mount_opts(_socket), do: @bb_tui_live_opts

        defoverridable tui_mount_opts: 1

        defdelegate tui_init(opts), to: BB.TUI.App, as: :init
        defdelegate tui_render(state, frame), to: BB.TUI.App, as: :render
        defdelegate tui_update(msg, state), to: BB.TUI.App, as: :update
        defdelegate tui_subscriptions(state), to: BB.TUI.App, as: :subscriptions

        @doc false
        def tui_terminate(_reason, _state), do: :ok
      end
    end
  end
end
