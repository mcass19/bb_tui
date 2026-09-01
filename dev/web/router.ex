defmodule Dev.Web.Router do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {Dev.Web.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live("/", Dev.Web.RobotLive)
  end
end
