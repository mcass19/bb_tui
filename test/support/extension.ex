defmodule BB.TUI.Test.Drive do
  @moduledoc false
  def command(_robot, _throttle, _turn), do: :ok
  def stop(_robot), do: :ok
end

defmodule BB.TUI.Test.Extension do
  @moduledoc false
  use BB.TUI.Extension

  drive do
    publish {BB.TUI.Test.Drive, :command}
    stop {BB.TUI.Test.Drive, :stop}
    turn_scale param([:yaw, :turn_rate])
  end

  panels do
    panel :balance do
      title "Balance"
      tab :drive
      readout "lean", joint(:lean), unit: :degree, decimals: 1
      plot "lean vs target", [joint(:lean), controller(:balancer, :target)]
      readout "speed", topic([:sensor, :wheel], [:velocity, :x]), scale: 2.15
    end

    panel :yaw do
      readout "heading", controller(:yaw, :heading)
    end
  end

  keys do
    bind "s", command: :stand, label: "stand"
  end

  hints do
    state :idle, "s to stand"
  end
end

defmodule BB.TUI.Test.EmptyExtension do
  @moduledoc false
  use BB.TUI.Extension
end
