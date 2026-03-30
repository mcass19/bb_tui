defmodule Mix.Tasks.Bb.Tui do
  @shortdoc "Launches the BB TUI robot dashboard"

  @moduledoc """
  Starts the terminal dashboard for a Beam Bots robot.

      $ mix bb.tui --robot MyApp.Robot

  The dashboard connects to a running robot's supervision tree and
  displays safety controls, joint positions, event stream, and
  available commands.

  ## Options

    * `--robot` - (required) The robot module to connect to.

  ## Keybindings

    * `Tab` — cycle active panel
    * `a` — arm robot
    * `d` — disarm robot
    * `f` — force disarm (error state only)
    * `j`/`k` — scroll events
    * `?` — help overlay
    * `q` — quit
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [robot: :string])

    robot =
      case Keyword.get(opts, :robot) do
        nil ->
          Mix.raise("--robot option is required. Usage: mix bb.tui --robot MyApp.Robot")

        module_str ->
          Module.concat([module_str])
      end

    Mix.Task.run("app.start")

    {:ok, pid} = BB.TUI.start(robot)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
