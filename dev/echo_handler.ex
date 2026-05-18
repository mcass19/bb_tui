# SPDX-License-Identifier: Apache-2.0

defmodule Dev.EchoHandler do
  @moduledoc """
  No-op command handler for dev/UI testing. Echoes the goal map back as
  the result so the parsed arguments are visible in the commands panel's
  result line. Use only from the dev tree.
  """
  use BB.Command

  @impl BB.Command
  def handle_command(goal, _context, state) do
    {:stop, :normal, %{state | result: {:ok, goal}}}
  end

  @impl BB.Command
  def result(%{result: result}), do: result
end
