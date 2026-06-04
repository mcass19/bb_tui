defmodule BB.TUI.State.Events do
  @moduledoc """
  Event-log display state, split out of `BB.TUI.State`.

  `list` holds the captured events (newest first, capped); `scroll_offset` is
  the viewport offset; `paused?` freezes capture; `show_detail?` toggles the
  detail popup for the selected event. The high-rate debounce that feeds
  `list` lives in `BB.TUI.State.Throttle`.
  """

  defstruct list: [],
            scroll_offset: 0,
            paused?: false,
            show_detail?: false

  @type t :: %__MODULE__{
          list: [{DateTime.t(), list(), term()}],
          scroll_offset: non_neg_integer(),
          paused?: boolean(),
          show_detail?: boolean()
        }
end
