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
    * `Enter` — show event details
    * `p` — pause / resume stream
    * `c` — clear events

  ### Commands panel

    * `j` / `Down` — select next command
    * `k` / `Up` — select previous command
    * `Enter` — execute selected command

  ### Joints panel

    * `j` / `Down` — select next joint
    * `k` / `Up` — select previous joint
    * `l` / `Right` — increase position (1% step)
    * `h` / `Left` — decrease position (1% step)
    * `L` — increase position (10% step)
    * `H` — decrease position (10% step)

  ### Parameters panel

    * `j` / `Down` — select next parameter
    * `k` / `Up` — select previous parameter
    * `l` / `Right` — increase value (+1 int, +0.1 float)
    * `h` / `Left` — decrease value (-1 int, -0.1 float)
    * `L` — increase value x10
    * `H` — decrease value x10
    * `Enter` — toggle boolean parameter
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
