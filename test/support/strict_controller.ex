defmodule BB.TUI.Test.StrictController do
  @moduledoc false
  # Stands in for a controller under `BB.Controller.Server` whose
  # `handle_call/3` clauses have no catch-all, like `BB.NSK.Balance.Controller`:
  # a call it doesn't know crashes it. Reading its state must not.
  use GenServer

  def start(user_state), do: GenServer.start(__MODULE__, user_state)

  @impl GenServer
  def init(user_state), do: {:ok, %BB.Controller.Server{user_state: user_state}}

  @impl GenServer
  def handle_call(:events, _from, state), do: {:reply, [], state}
end
