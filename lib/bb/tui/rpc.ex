defmodule BB.TUI.Rpc do
  @moduledoc """
  Thin wrapper around `:rpc.call/4` and `Node.spawn_link/2`.

  This module exists purely so the cross-node code paths in
  `BB.TUI.Robot` can be exercised in tests by mocking a normal Elixir
  module — `:rpc` itself is a sticky kernel module and cannot be
  swapped out at runtime.

  In production this is a transparent passthrough; in tests Mimic
  replaces it.
  """

  @doc """
  Synchronous remote function call. Mirrors `:rpc.call/4`.
  """
  @spec call(node(), module(), atom(), [term()]) :: term()
  def call(node, mod, fun, args), do: :rpc.call(node, mod, fun, args)

  @doc """
  Synchronous remote function call that gives up after `timeout`
  milliseconds. Mirrors `:rpc.call/5`.
  """
  @spec call(node(), module(), atom(), [term()], timeout()) :: term()
  def call(node, mod, fun, args, timeout), do: :rpc.call(node, mod, fun, args, timeout)

  @doc """
  Asynchronous remote call: runs `mod.fun(args)` on `node` without waiting
  for it. Mirrors `:erpc.cast/4`.
  """
  @spec cast(node(), module(), atom(), [term()]) :: :ok
  def cast(node, mod, fun, args), do: :erpc.cast(node, mod, fun, args)

  @doc """
  Spawns a linked process on a remote node. Mirrors `Node.spawn_link/2`.
  """
  @spec spawn_link(node(), (-> any())) :: pid()
  def spawn_link(node, fun) when is_function(fun, 0) do
    Node.spawn_link(node, fun)
  end
end
