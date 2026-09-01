import Config

if config_env() == :dev do
  # Dev-only browser dashboard (dev/web) at http://localhost:4040.
  config :bb_tui, Dev.Web.Endpoint,
    adapter: Bandit.PhoenixAdapter,
    url: [host: "localhost"],
    http: [ip: {127, 0, 0, 1}, port: 4040],
    server: true,
    secret_key_base: String.duplicate("bb_tui_dev_secret", 4),
    live_view: [signing_salt: "bb_tui_dev_salt"],
    debug_errors: true

  config :phoenix, :json_library, Jason
end

if config_env() == :test do
  import_config "test.exs"
end
