defmodule BB.TUI.Renderer do
  @moduledoc """
  Behaviour a **consumer** implements to teach the dashboard how to render a
  payload on a PubSub path the consumer owns — without `bb_tui` knowing anything
  about that payload's shape or struct.

  `bb_tui` subscribes to whatever paths it is told (`:subscribe_paths`) and
  dispatches each `{:bb, path, msg}` by path prefix. Most prefixes have
  dedicated, built-in handling (`[:state_machine]`, `[:sensor]`, `[:param]`, …).
  Anything else falls to a generic event-log row via `inspect/2`.

  A renderer plugs into that generic seam: a consumer registers a module for a
  path prefix via the `:renderers` option (a `%{prefix => module}` map threaded
  through `BB.TUI.run/2`, `start/2`, `start_ssh/2`). When a message arrives whose
  path matches a registered prefix (longest prefix wins, like a routing table),
  `bb_tui` calls back into the consumer's module rather than pattern-matching the
  payload itself. The dashboard therefore stays free of any downstream struct
  knowledge — the consumer owns the rendering of its own data.

  Two callbacks:

    * `summarize/2` — the one-line string for the event log. Return `nil` to fall
      back to `bb_tui`'s generic `inspect/2`.
    * `observed/2` (optional) — feed the at-a-glance status-bar readout. Return a
      `{slot_key, display, meta}` triple to record/refresh a slot, or `nil` to
      skip. The status bar surfaces the freshest slot (max `meta.seq`) and dims
      stale ones (`meta.freshness == :stale`).

  ## Return shapes

  `summarize(path, payload)` → `String.t() | nil`.

  `observed(path, payload)` → `{slot_key, display, meta} | nil` where:

    * `slot_key` — any term that identifies the slot (e.g. `{:wheels, :imu}` or a
      bare atom). Successive samples on the same `slot_key` overwrite, so the
      readout shows the latest value of each slot rather than accumulating.
    * `display` — a `map()` the status bar renders. `bb_tui` reads at least
      `:label` (a `String.t()` shown in the segment) from it; consumers may carry
      extra fields for their own future use.
    * `meta` — a `map()` carrying at least:
      * `:freshness` — `:fresh | :stale`. Stale slots render dimmed.
      * `:seq` — a sortable term (typically an integer or timestamp). The status
        bar picks the slot with the maximum `:seq` as "freshest".

  ## Example

      defmodule MyApp.SlotRenderer do
        @behaviour BB.TUI.Renderer

        @impl true
        def summarize([:demo | _], %{name: name, value: value}) do
          "\#{name} = \#{value}"
        end

        def summarize(_path, _payload), do: nil

        @impl true
        def observed([:demo | _], %{name: name, value: value} = p) do
          {name, %{label: "\#{name}:\#{value}"},
           %{freshness: Map.get(p, :freshness, :fresh), seq: Map.get(p, :seq, 0)}}
        end

        def observed(_path, _payload), do: nil
      end

  Then:

      BB.TUI.run(MyApp.Robot,
        subscribe_paths: [[:demo]],
        renderers: %{[:demo] => MyApp.SlotRenderer}
      )
  """

  @typedoc "A registered slot key — any term the renderer uses to identify a slot."
  @type slot_key :: term()

  @typedoc "The status-bar display map. `bb_tui` reads at least `:label`."
  @type display :: %{optional(atom()) => term()}

  @typedoc "Slot metadata. Carries at least `:freshness` and a sortable `:seq`."
  @type meta :: %{required(:freshness) => :fresh | :stale, required(:seq) => term()}

  @doc """
  Returns a one-line event-log summary for `payload` on `path`, or `nil` to fall
  back to `bb_tui`'s generic `inspect/2` rendering.
  """
  @callback summarize(path :: [atom()], payload :: term()) :: String.t() | nil

  @doc """
  Returns `{slot_key, display, meta}` to record/refresh an at-a-glance status-bar
  slot, or `nil` to skip. Optional — a renderer that only needs an event-log row
  can omit it.
  """
  @callback observed(path :: [atom()], payload :: term()) ::
              {slot_key(), display(), meta()} | nil

  @optional_callbacks observed: 2
end
