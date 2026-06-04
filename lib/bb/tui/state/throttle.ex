defmodule BB.TUI.State.Throttle do
  @moduledoc """
  High-rate sensor handling, split out of `BB.TUI.State`.

  `debounce_ms` + `last_seen` back the event-log debounce in
  `BB.TUI.State.append_event/3`; `flush_ms` + `render_pending?` drive the
  coalesced sensor re-render in `BB.TUI.App`. Defaults: 1s debounce window,
  ~33ms (~30fps) flush. A `debounce_ms` of `0` disables debouncing.
  """

  defstruct debounce_ms: 1000,
            last_seen: %{},
            flush_ms: 33,
            render_pending?: false

  @type t :: %__MODULE__{
          debounce_ms: non_neg_integer(),
          last_seen: %{optional({list(), term()}) => integer()},
          flush_ms: pos_integer(),
          render_pending?: boolean()
        }
end
