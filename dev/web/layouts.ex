defmodule Dev.Web.Layouts do
  @moduledoc """
  Root layout for the dev browser dashboard.

  The sizing contract matters more than it looks: the page must never
  scroll, and every ancestor of the TUI container needs a resolved
  height, or the hook's ResizeObserver measures a collapsing (or ever
  growing) box. The LiveSocket is wired inline from prebuilt bundles —
  `window.Phoenix` and `window.LiveView` from the UMD builds, the hook
  imported as a native ES module.
  """

  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>bb_tui — Dev.TestRobot</title>
        <style>
          html, body { height: 100%; margin: 0; overflow: hidden; background: #101014; }
          [data-phx-main] { height: 100%; }
        </style>
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js">
        </script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js">
        </script>
        <script type="module">
          import { PhoenixExRatatuiHook } from "/assets/phoenix_ex_ratatui/main.js";

          const csrf = document.querySelector("meta[name='csrf-token']").content;
          const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            params: { _csrf_token: csrf },
            hooks: { PhoenixExRatatuiHook },
          });
          liveSocket.connect();
        </script>
      </body>
    </html>
    """
  end
end
