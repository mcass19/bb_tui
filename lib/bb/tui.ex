defmodule BB.TUI do
  @moduledoc """
  Terminal-based dashboard for Beam Bots robots.

  BB.TUI provides a TUI interface for monitoring and controlling BB robots —
  safety controls, runtime state, joint positions, event stream, and command
  display — in terminal environments.

  ## Usage

      # Programmatic — from IEx when robot is already running
      BB.TUI.start(MyApp.Robot)

      # Supervised — add to your app's supervision tree
      children = [
        {BB.Supervisor, MyApp.Robot},
        {BB.TUI, robot: MyApp.Robot}
      ]

      # Mix task — standalone
      $ mix bb.tui --robot MyApp.Robot

  """

  @doc """
  Starts the TUI dashboard for the given robot module.

  The robot must already be supervised and running. This function
  starts the TUI as a linked process.

  ## Options

    * `:test_mode` - `{width, height}` tuple for headless testing (optional)

  """
  @spec start(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(robot, opts \\ []) when is_atom(robot) do
    BB.TUI.App.start_link(Keyword.put(opts, :robot, robot))
  end
end
