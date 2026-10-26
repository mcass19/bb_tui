defmodule Dev.Oscillator do
  @moduledoc """
  Dev-only controller with state worth watching: a sine wave and a target
  that lags it, the shape of a balancing loop's lean and setpoint. It
  publishes nothing — like goatbot's balancer, its state is only reachable
  through `handle_call(:inspect, ...)` — so it exercises the extension
  `controller/2` source and its polling.
  """
  use BB.Controller

  @tick_ms 50
  @period_ms 4_000
  @amplitude 0.4

  @impl BB.Controller
  def init(_opts) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{started_at: now(), output: 0.0, target: 0.0, ticks: 0}}
  end

  @impl BB.Controller
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    phase = 2 * :math.pi() * (now() - state.started_at) / @period_ms
    output = @amplitude * :math.sin(phase)
    # The target follows the output with a lag, like a setpoint chasing a lean.
    target = state.target + (output - state.target) * 0.1
    {:noreply, %{state | output: output, target: target, ticks: state.ticks + 1}}
  end

  @impl BB.Controller
  def handle_call(:inspect, _from, state) do
    {:reply, Map.drop(state, [:started_at]), state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
