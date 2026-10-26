defmodule BB.TUI.Extension.Verifiers.Keys do
  @moduledoc """
  Checks that no `bind` takes a key bb_tui already uses (see
  `BB.TUI.Extension.reserved_keys/0`). Two binds on the same key are caught
  by the entity's identifier.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @reserved_keys ~w(q ? a d f [ ] - + = 1 2 3 4 5 j k h l H L c p t r y n m) ++
                   ~w(enter tab back_tab esc backspace up down left right)

  @doc false
  # Kept here rather than in `BB.TUI.Extension` (which delegates to it) so
  # the verifier doesn't depend on the module whose DSL it verifies.
  def reserved_keys, do: @reserved_keys

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:keys])
    |> Enum.find(&(&1.key in @reserved_keys))
    |> case do
      nil ->
        :ok

      bind ->
        {:error,
         DslError.exception(
           module: module,
           path: [:keys, :bind, bind.key],
           message: "#{inspect(bind.key)} is one of bb_tui's own keys and can't be bound"
         )}
    end
  end
end
