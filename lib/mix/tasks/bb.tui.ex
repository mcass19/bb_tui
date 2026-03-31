defmodule Mix.Tasks.Bb.Tui do
  @shortdoc "Launches the BB TUI robot dashboard"

  @moduledoc """
  Starts the terminal dashboard for a Beam Bots robot.

      $ mix bb.tui --robot MyApp.Robot

  The dashboard connects to a running robot's supervision tree and
  displays safety controls, runtime state, joint positions, event
  stream, and available commands.

  ## Options

    * `--robot` - (required) The robot module to connect to.

  ## Keybindings

  ### Global

    * `q` — quit
    * `Tab` — cycle active panel
    * `?` — toggle help overlay
    * `a` — arm robot
    * `d` — disarm robot
    * `f` — force disarm (error state only)

  ### Events panel

    * `j` / `Down` — scroll down
    * `k` / `Up` — scroll up

  ### Commands panel

    * `Up` / `Down` — select command
    * `Enter` — execute command
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

    BB.TUI.run(robot)
  end
end
