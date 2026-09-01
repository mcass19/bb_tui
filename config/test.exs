import Config

# Minimal endpoint that powers Phoenix.LiveViewTest for BB.TUI.Live.
config :bb_tui, BB.TUI.Test.Endpoint,
  secret_key_base: String.duplicate("bb_tui_test_secret", 4),
  live_view: [signing_salt: "bb_tui_test_salt"]

config :phoenix, :json_library, Jason

# LiveView mounts and hook events log at :debug; keep test output clean.
# capture_log-based tests capture at all levels regardless.
config :logger, level: :warning
