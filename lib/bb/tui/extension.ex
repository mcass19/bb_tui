defmodule BB.TUI.Extension do
  @moduledoc """
  Extends the dashboard for a particular robot or kit: driving, panels of
  live readouts and plots, keys bound to commands, and per-state hints.

  An extension is a module of declarations, kept apart from the robot module
  and passed to every entry point as `extensions: [MyRobot.TUI]`. bb_tui
  renders everything with its own widgets and theme, and never needs to know
  the kit behind it: driving, for instance, goes through the functions the
  extension names.

      defmodule Goatbot.TUI do
        use BB.TUI.Extension

        drive do
          publish {BB.NSK.Drive, :command}
          stop {BB.NSK.Drive, :stop}
          turn_scale param([:yaw, :turn_rate])
        end

        panels do
          panel :balance do
            title "Balance"
            tab :drive
            readout "lean", joint(:lean), unit: :degree, decimals: 1
            readout "setpoint", controller(:pid_balancer, :setpoint), unit: :degree
            plot "lean vs target", [joint(:lean), controller(:pid_balancer, :target)]
          end
        end

        keys do
          bind "s", command: :stand, label: "stand"
        end

        hints do
          state :idle, "hold it upright, then s to stand"
        end
      end

  ## Sections

    * `drive` — hold-to-drive with the arrow keys: the `publish` function is
      called as `publish(robot, throttle, turn)` at `rate` Hz while a key is
      held, and `stop(robot)` when it is let go.
    * `panels` — `panel` entities holding `readout`s, `plot`s and
      `attitude` indicators, each fed by a source: `joint/1`, `controller/2`, `topic/2` or `param/1` (see
      `BB.TUI.Extension.Source`).
    * `keys` — `bind` a key to a robot command. bb_tui's own keys
      (`reserved_keys/0`) can't be bound.
    * `hints` — a banner per robot runtime state.

  `BB.TUI.Extension.Dsl` documents every option; `BB.TUI.Extension.Info`
  reads them back.
  """

  use Spark.Dsl, default_extensions: [extensions: [BB.TUI.Extension.Dsl]]

  @doc """
  The keys bb_tui handles itself, which an extension's `bind` can't take:
  the global keys, panel navigation, the arrows used for jogging and driving,
  space (which freezes an extension tab's charts), and each panel's own keys.

  ## Examples

      iex> "q" in BB.TUI.Extension.reserved_keys()
      true

      iex> "s" in BB.TUI.Extension.reserved_keys()
      false
  """
  @spec reserved_keys() :: [String.t()]
  defdelegate reserved_keys, to: BB.TUI.Extension.Verifiers.Keys

  @doc """
  Whether `module` is a `BB.TUI.Extension`.

  ## Examples

      iex> BB.TUI.Extension.extension?(Enum)
      false
  """
  @spec extension?(module()) :: boolean()
  def extension?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) and
      BB.TUI.Extension.Dsl in Spark.extensions(module)
  end
end
