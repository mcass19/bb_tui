defmodule BB.TUI.Errors do
  @moduledoc """
  Turns the error reasons bb hands back into display text and a severity.

  bb reports failures as `BB.Error` exception structs (`BB.Error.State.NotArmed`,
  `BB.Error.State.CommandPending`, …), each carrying a message and a
  `BB.Error.Severity`. Anything else — a bare atom, a tuple from an older
  handler, the async runner's `{:exit, reason}` — is inspected and treated as
  an error.
  """

  alias BB.Error.Severity

  @doc """
  Returns a one-line description of an error reason.

  Exceptions render through `Exception.message/1`; any other term is inspected,
  truncated to `limit` items.

  ## Examples

      iex> BB.TUI.Errors.describe(:timeout)
      ":timeout"

      iex> BB.TUI.Errors.describe(%RuntimeError{message: "boom"})
      "boom"

      iex> BB.TUI.Errors.describe(Enum.to_list(1..10), 3)
      "[1, 2, 3, ...]"
  """
  @spec describe(term(), pos_integer()) :: String.t()
  def describe(reason, limit \\ 30)
  def describe(%{__exception__: true} = exception, _limit), do: Exception.message(exception)
  def describe(reason, limit), do: inspect(reason, pretty: false, limit: limit)

  @doc """
  Returns the severity of an error reason.

  A reason implementing `BB.Error.Severity` reports its own; everything else
  counts as `:error`.

  ## Examples

      iex> BB.TUI.Errors.severity(:disarmed)
      :error

      iex> BB.TUI.Errors.severity(%BB.Error.State.CommandPending{actuator: :elbow, timeout_ms: 250})
      :warning
  """
  @spec severity(term()) :: Severity.t()
  def severity(reason) do
    if Severity.impl_for(reason),
      do: Severity.severity(reason),
      else: :error
  end
end
