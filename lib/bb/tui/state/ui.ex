defmodule BB.TUI.State.UI do
  @moduledoc """
  View chrome state, split out of `BB.TUI.State`.

  `active_tab` is the focused top-level tab; `active_panel` is the focused panel
  within the Control Panel tab; `show_help?` toggles the help overlay and
  `help_scroll_offset` scrolls it; `throbber_step` advances the spinner animation.
  """

  defstruct active_tab: :control,
            active_panel: :safety,
            show_help?: false,
            help_scroll_offset: 0,
            throbber_step: 0

  @type t :: %__MODULE__{
          active_tab: :control | :visualization,
          active_panel: :safety | :commands | :joints | :events | :parameters,
          show_help?: boolean(),
          help_scroll_offset: non_neg_integer(),
          throbber_step: non_neg_integer()
        }
end
