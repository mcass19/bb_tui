defmodule Dev.Web.Endpoint do
  @moduledoc """
  Dev-only Phoenix endpoint serving the browser dashboard at
  `http://localhost:4040`.

  Deliberately npm-free: the page loads phoenix and phoenix_live_view as
  their prebuilt UMD bundles straight out of `deps/`, and
  phoenix_ex_ratatui's hook as the prebuilt ES module it ships — see
  `Dev.Web.Layouts.root/1`. No esbuild, no node_modules.
  """

  use Phoenix.Endpoint, otp_app: :bb_tui

  @session_options [
    store: :cookie,
    key: "_bb_tui_dev",
    signing_salt: "bb_tui_dev_session",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static, at: "/assets/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/assets/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  plug(Plug.Static,
    at: "/assets/phoenix_ex_ratatui",
    from: Path.expand("../../deps/phoenix_ex_ratatui/lib/assets/phoenix_ex_ratatui", __DIR__)
  )

  plug(Plug.Session, @session_options)
  plug(Dev.Web.Router)
end
