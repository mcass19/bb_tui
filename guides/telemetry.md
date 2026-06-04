# Telemetry

Every BB.TUI session rides on ExRatatui's `:telemetry` instrumentation. The runtime wraps `mount`, every input event, every PubSub/info dispatch, and every frame in spans with `:start` / `:stop` / `:exception` events; transport connect/disconnect and session open/close fire as single events. All metadata carries `:mod` (`BB.TUI.App` for any TUI session) and `:transport` (`:local`, `:ssh`, `:distributed`, or `:cell_session`).

## Development logger

A one-call default Logger handler is exposed for development:

```elixir
BB.TUI.attach_telemetry_logger()

# or, scoped to a single level / event subset
BB.TUI.attach_telemetry_logger(level: :info)

BB.TUI.detach_telemetry_logger()
```

## Production observability

For production, attach a custom handler that ships into `Telemetry.Metrics`, OpenTelemetry, or whatever the consumer app already uses. See `ExRatatui.Telemetry` for the full event reference — event names, measurement units, and metadata shapes.
