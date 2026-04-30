defmodule BB.TUI.RpcTest do
  use ExUnit.Case, async: true

  alias BB.TUI.Rpc

  describe "call/4" do
    test "delegates to :rpc.call/4 — non-existent node returns {:badrpc, _}" do
      # The wrapper is a passthrough; we exercise it by making a real call
      # against a node that does not exist. :rpc.call/4 returns
      # {:badrpc, :nodedown} (or :not_alive when distribution isn't started).
      assert {:badrpc, _reason} = Rpc.call(:"nonexistent@127.0.0.1", :erlang, :node, [])
    end
  end

  describe "spawn_link/2" do
    @tag capture_log: true
    test "delegates to Node.spawn_link/2 — returns a pid even for unknown node" do
      Process.flag(:trap_exit, true)

      # Node.spawn_link/2 against a non-existent node still returns a pid;
      # the link is broken almost immediately. We just need to confirm the
      # wrapper passes the call through.
      pid = Rpc.spawn_link(:"nonexistent@127.0.0.1", fn -> :ok end)
      assert is_pid(pid)

      # Drain any EXIT signal so we don't leak it into the next test.
      receive do
        {:EXIT, ^pid, _reason} -> :ok
      after
        50 -> :ok
      end
    end
  end
end
