defmodule BB.TUI.State.Commands do
  @moduledoc """
  Command palette and inline argument-edit state, split out of `BB.TUI.State`.

  `available` is the discovered command list; `selected` is the highlighted
  row; `result` is the last execution result; `executing` is a marker held
  while a command runs; `edit_mode?`/`focused_arg`/`form_values` drive the
  inline argument editor. `available` is seeded when `BB.TUI.App` starts.
  """

  defstruct available: [],
            selected: 0,
            result: nil,
            executing: nil,
            edit_mode?: false,
            focused_arg: 0,
            form_values: %{}

  @type t :: %__MODULE__{
          available: [term()],
          selected: non_neg_integer(),
          result: {:ok, term()} | {:error, term()} | nil,
          executing: term() | nil,
          edit_mode?: boolean(),
          focused_arg: non_neg_integer(),
          form_values: %{atom() => %{atom() => String.t()}}
        }
end
