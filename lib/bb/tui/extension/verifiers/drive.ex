defmodule BB.TUI.Extension.Verifiers.Drive do
  @moduledoc """
  Checks the `drive` section: `publish` and `stop` come together, and each
  names a function with the right arity — `publish/3`, `stop/1`.

  A module that can't be loaded here (one that only exists on the robot's
  node, say) is left for `BB.TUI.App` to check when the session starts.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    publish = Verifier.get_option(dsl_state, [:drive], :publish)
    stop = Verifier.get_option(dsl_state, [:drive], :stop)

    with :ok <- both_or_neither(module, publish, stop),
         :ok <- exported(module, :publish, publish, 3) do
      exported(module, :stop, stop, 1)
    end
  end

  defp both_or_neither(_module, nil, nil), do: :ok
  defp both_or_neither(_module, {_, _}, {_, _}), do: :ok

  defp both_or_neither(module, _publish, _stop) do
    error(module, [], "drive needs both `publish` and `stop`")
  end

  defp exported(_module, _option, nil, _arity), do: :ok

  defp exported(module, option, {mod, fun}, arity) do
    case Code.ensure_compiled(mod) do
      {:module, ^mod} ->
        if function_exported?(mod, fun, arity),
          do: :ok,
          else: error(module, [option], "#{inspect(mod)}.#{fun}/#{arity} is not exported")

      {:error, _reason} ->
        :ok
    end
  end

  defp error(module, path, message),
    do: {:error, DslError.exception(module: module, path: [:drive | path], message: message)}
end
