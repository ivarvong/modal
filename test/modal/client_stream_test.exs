defmodule Modal.ClientStreamTest do
  @moduledoc """
  Drives `Modal.Client.stream_rpc/4` and `stream_rpc_reduce/6` through the real
  GenServer with a scripted stream stub.

  Pins the bug that motivated this test: the previous `exec_stream_rpc`
  reducer had a catch-all `_, acc -> {:cont, acc}` clause that silently
  dropped `{:error, {:network, reason}}` (and any other shape that wasn't
  `{:ok, msg}` or `{:error, %GRPC.RPCError{}}`), turning a stream that died
  mid-flight into a `{:ok, partial_list}` "success." This was the worst
  finding from the v0.1.0 code review — it could cause
  `Modal.Image.get_or_create/3` to return `{:ok, :cached}` for an image
  build that actually died at minute 29 of 30.
  """
  use ExUnit.Case, async: false

  alias Modal.Client.SandboxListResponse

  # ── Helpers ─────────────────────────────────────────────────────────

  # Connect_fn returns immediately with a sentinel channel — bypasses the
  # 5-second GRPC.Stub.connect timeout against a refused port and avoids
  # the :sys.replace_state pattern.
  defp start_client! do
    {:ok, client} =
      Modal.Client.start_link(
        token_id: "ak-stream-test",
        token_secret: "as-stream-test",
        modal_stub: Modal.Test.ScriptedStreamStub,
        connect_fn: fn state -> {:ok, %{state | channel: :test_channel}} end
      )

    client
  end

  defp script!(items) do
    :persistent_term.put(:modal_scripted_stream_items, items)
    on_exit(fn -> :persistent_term.erase(:modal_scripted_stream_items) end)
  end

  defp msg(n), do: %SandboxListResponse{sandboxes: [%{id: "sb-#{n}"}]}

  # ── stream_rpc/4 ────────────────────────────────────────────────────

  describe "stream_rpc/4 — error handling" do
    test "all-ok stream returns the items in order" do
      script!([{:ok, msg(1)}, {:ok, msg(2)}, {:ok, msg(3)}])
      client = start_client!()

      assert {:ok, [m1, m2, m3]} =
               Modal.Client.stream_rpc(client, :sandbox_list, %{}, 5_000)

      assert m1 == msg(1)
      assert m2 == msg(2)
      assert m3 == msg(3)
      GenServer.stop(client)
    end

    test "mid-stream {:error, reason} (transport drop) halts with :network — NOT swallowed" do
      # This is the regression test for the original bug. Before the fix the
      # call returned {:ok, [msg(1)]} — the error was silently dropped by the
      # catch-all reducer clause.
      script!([{:ok, msg(1)}, {:error, :closed}, {:ok, msg(2)}])
      client = start_client!()

      assert {:error, %Modal.Error{kind: :network, code: :closed}} =
               Modal.Client.stream_rpc(client, :sandbox_list, %{}, 5_000)

      GenServer.stop(client)
    end

    test "mid-stream %GRPC.RPCError{} halts with :grpc kind" do
      err = %GRPC.RPCError{status: 14, message: "unavailable"}
      script!([{:ok, msg(1)}, {:error, err}])
      client = start_client!()

      assert {:error, %Modal.Error{kind: :grpc, code: 14, message: "unavailable"}} =
               Modal.Client.stream_rpc(client, :sandbox_list, %{}, 5_000)

      GenServer.stop(client)
    end

    test "an unexpected (non-tuple) item halts with :unexpected kind" do
      # If the underlying library ever yields an item that isn't {:ok, _} or
      # {:error, _}, the new reducer must NOT silently drop it. It must halt.
      script!([{:ok, msg(1)}, :surprise_atom])
      client = start_client!()

      assert {:error, %Modal.Error{kind: :unexpected, metadata: %{item: :surprise_atom}}} =
               Modal.Client.stream_rpc(client, :sandbox_list, %{}, 5_000)

      GenServer.stop(client)
    end

    test "first-item error halts before yielding anything" do
      script!([{:error, :nxdomain}])
      client = start_client!()

      assert {:error, %Modal.Error{kind: :network, code: :nxdomain}} =
               Modal.Client.stream_rpc(client, :sandbox_list, %{}, 5_000)

      GenServer.stop(client)
    end
  end

  # ── stream_rpc_reduce/6 ─────────────────────────────────────────────

  describe "stream_rpc_reduce/6 — error handling" do
    test "all-ok stream feeds every item to the reducer" do
      script!([{:ok, msg(1)}, {:ok, msg(2)}, {:ok, msg(3)}])
      client = start_client!()

      reducer = fn item, acc -> {:cont, [item | acc]} end

      assert {:ok, items} =
               Modal.Client.stream_rpc_reduce(
                 client,
                 :sandbox_list,
                 %{},
                 [],
                 reducer,
                 5_000
               )

      assert length(items) == 3
      GenServer.stop(client)
    end

    test "mid-stream {:error, reason} halts BEFORE running reducer on later items" do
      # Same swallow bug, in the reduce variant. Reducer must never see
      # items after a transport error.
      counter = :counters.new(1, [:atomics])

      reducer = fn _item, acc ->
        :counters.add(counter, 1, 1)
        {:cont, acc}
      end

      script!([{:ok, msg(1)}, {:error, :closed}, {:ok, msg(2)}, {:ok, msg(3)}])
      client = start_client!()

      assert {:error, %Modal.Error{kind: :network, code: :closed}} =
               Modal.Client.stream_rpc_reduce(
                 client,
                 :sandbox_list,
                 %{},
                 :acc,
                 reducer,
                 5_000
               )

      assert :counters.get(counter, 1) == 1,
             "reducer must only have seen msg(1) before the error halted the stream"

      GenServer.stop(client)
    end

    test "mid-stream %GRPC.RPCError{} halts with {:grpc, status, msg}" do
      err = %GRPC.RPCError{status: 7, message: "permission denied"}
      script!([{:ok, msg(1)}, {:error, err}])
      client = start_client!()

      reducer = fn _item, acc -> {:cont, acc} end

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Client.stream_rpc_reduce(
                 client,
                 :sandbox_list,
                 %{},
                 :acc,
                 reducer,
                 5_000
               )

      GenServer.stop(client)
    end

    test "reducer that returns {:halt, value} is respected (no error swallow)" do
      script!([{:ok, msg(1)}, {:ok, msg(2)}, {:ok, msg(3)}])
      client = start_client!()

      # Halt after the first item — should NOT see msg(2) or msg(3).
      reducer = fn item, _acc -> {:halt, {:first, item}} end

      assert {:ok, {:first, m}} =
               Modal.Client.stream_rpc_reduce(
                 client,
                 :sandbox_list,
                 %{},
                 nil,
                 reducer,
                 5_000
               )

      assert m == msg(1)
      GenServer.stop(client)
    end
  end
end
