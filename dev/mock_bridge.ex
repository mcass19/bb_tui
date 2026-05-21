# SPDX-License-Identifier: Apache-2.0

defmodule Dev.MockBridge do
  @moduledoc """
  Development-only `BB.Bridge` implementation that exposes a small set
  of pretend remote parameters with in-memory writes.

  Useful for exercising `bb_tui`'s Bridge tab UI end-to-end without
  connecting to a real flight controller or GCS:

      iex> {:ok, params} = BB.Parameter.list_remote(Dev.TestRobot, :mavlink)
      iex> BB.Parameter.set_remote(Dev.TestRobot, :mavlink, "PITCH_P", 0.42)
      :ok

  Storage is per-process and resets on bridge restart. Param shape
  mirrors `bb_liveview`'s expected map keys (`:id`, `:value`, `:type`,
  `:min`, `:max`, `:doc`) so both dashboards consume the same payload.
  """
  use BB.Bridge, options_schema: []

  @initial_params [
    %{
      id: "PITCH_P",
      value: 0.10,
      type: :float,
      min: 0.0,
      max: 1.0,
      doc: "Proportional gain on the pitch axis."
    },
    %{
      id: "PITCH_I",
      value: 0.05,
      type: :float,
      min: 0.0,
      max: 1.0,
      doc: "Integral gain on the pitch axis."
    },
    %{
      id: "MAX_RATE",
      value: 250,
      type: :integer,
      min: 0,
      max: 1000,
      doc: "Maximum commanded rate in deg/s."
    },
    %{
      id: "ARM_CHECKS",
      value: true,
      type: :boolean,
      doc: "Run pre-flight safety checks before allowing arm."
    },
    %{
      id: "FLIGHT_MODE",
      value: "STABILIZE",
      type: :string,
      doc: "Active flight mode name."
    }
  ]

  @impl GenServer
  def init(opts) do
    params = Map.new(@initial_params, fn p -> {p.id, p} end)
    {:ok, %{bb: opts[:bb], params: params}}
  end

  @impl BB.Bridge
  def handle_change(_robot, _changed, state) do
    # The mock bridge has no outbound clients — local param changes
    # don't need to be relayed anywhere.
    {:ok, state}
  end

  @impl BB.Bridge
  def list_remote(state) do
    {:ok, Map.values(state.params), state}
  end

  @impl BB.Bridge
  def get_remote(param_id, state) do
    case Map.fetch(state.params, param_id) do
      {:ok, %{value: value}} -> {:ok, value, state}
      :error -> {:error, :not_found, state}
    end
  end

  @impl BB.Bridge
  def set_remote(param_id, value, state) do
    case Map.fetch(state.params, param_id) do
      {:ok, param} ->
        updated = %{param | value: value}
        {:ok, %{state | params: Map.put(state.params, param_id, updated)}}

      :error ->
        {:ok, state}
    end
  end

  @impl BB.Bridge
  def subscribe_remote(_param_id, state) do
    # No external feed — nothing to subscribe to.
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:list_remote, _from, state) do
    {:ok, params, state} = list_remote(state)
    {:reply, {:ok, params}, state}
  end

  def handle_call({:get_remote, param_id}, _from, state) do
    case get_remote(param_id, state) do
      {:ok, value, state} -> {:reply, {:ok, value}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_remote, param_id, value}, _from, state) do
    {:ok, state} = set_remote(param_id, value, state)
    # No remote system to talk to and no outbound PubSub fanout — the
    # TUI refetches via list_remote/1 right after a successful set, so
    # the in-memory map is the source of truth.
    {:reply, :ok, state}
  end

  def handle_call({:subscribe_remote, param_id}, _from, state) do
    {:ok, state} = subscribe_remote(param_id, state)
    {:reply, :ok, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
