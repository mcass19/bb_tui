defmodule BB.TUI.State.Parameters do
  @moduledoc """
  Parameter browser state, split out of `BB.TUI.State`.

  `list` is the local parameter `{path, value}` list with `metadata` keyed by
  path; `tabs`/`tab_selected` drive the Local/bridge tab strip; `remote` caches
  per-bridge remote parameter fetches; `selected` is the highlighted row.
  `editing` holds the inline text-edit session for a string or atom
  parameter — `nil`, or a map with the `path` being edited and the `buffer`
  typed so far.
  """

  defstruct list: [],
            metadata: %{},
            tabs: [:local],
            tab_selected: 0,
            remote: %{},
            selected: 0,
            editing: nil

  @type t :: %__MODULE__{
          list: [{list(), term()}],
          metadata: %{list() => map()},
          tabs: [:local | {:bridge, atom()}],
          tab_selected: non_neg_integer(),
          remote: %{atom() => [map()] | {:error, term()}},
          selected: non_neg_integer(),
          editing: %{path: list(), buffer: String.t()} | nil
        }
end
