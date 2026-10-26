defmodule BB.TUI.State.Commands do
  @moduledoc """
  Command palette and inline argument-edit state, split out of `BB.TUI.State`.

  `available` is the discovered command list; `selected` is the highlighted
  row; `result` is the last execution result; `executing` is the name of the
  command this dashboard started, held until its result arrives; `running` is
  every command running on the robot, whoever started it, as listed by
  `BB.Command.list/1`, oldest first; `edit_mode?`/`focused_arg`/`form_values`
  drive the inline argument editor. `available` and `running` are seeded when
  `BB.TUI.App` starts.
  """

  defstruct available: [],
            selected: 0,
            result: nil,
            executing: nil,
            running: [],
            edit_mode?: false,
            focused_arg: 0,
            form_values: %{}

  @typedoc "A running command, as listed by `BB.Command.list/1`."
  @type running :: %{
          required(:name) => atom(),
          required(:execution_id) => reference(),
          required(:started_at) => DateTime.t(),
          optional(atom()) => term()
        }

  @type t :: %__MODULE__{
          available: [term()],
          selected: non_neg_integer(),
          result: {:ok, term()} | {:error, term()} | nil,
          executing: term() | nil,
          running: [running()],
          edit_mode?: boolean(),
          focused_arg: non_neg_integer(),
          form_values: %{atom() => %{atom() => String.t()}}
        }
end
