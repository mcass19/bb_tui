defmodule BB.TUI.State.Parameters do
  @moduledoc """
  Parameter browser state, split out of `BB.TUI.State`.

  `list` is the local parameter `{path, value}` list with `metadata` keyed by
  path; `tabs`/`tab_selected` drive the Local/bridge tab strip; `remote` caches
  per-bridge remote parameter fetches; `selected` is the highlighted row.
  """

  defstruct list: [],
            metadata: %{},
            tabs: [:local],
            tab_selected: 0,
            remote: %{},
            selected: 0

  @type t :: %__MODULE__{
          list: [{list(), term()}],
          metadata: %{list() => map()},
          tabs: [:local | {:bridge, atom()}],
          tab_selected: non_neg_integer(),
          remote: %{atom() => [map()] | {:error, term()}},
          selected: non_neg_integer()
        }
end
