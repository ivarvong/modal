defmodule Modal.ClientCrashTest do
  @moduledoc """
  Pins the contract for task-crash recovery inside `Modal.Client`'s dispatch
  Task.

  Before this fix, `Task.Supervisor.start_child` was passed a closure with no
  `try/after`. If `stub.call/4` (or the stream variant) raised, the closure
  unwound without sending `:task_completed`, without replying to the
  GenServer caller, and without sending `:connection_failed`. Three concrete
  symptoms followed:

    * The caller's `GenServer.call` blocked until its timeout — 30s+ from a
      user's perspective for what should be an immediate error.
    * `state.inflight` leaked: a crash bumped it but the `:task_completed`
      decrement never arrived. Eventually a client with `max_concurrency: N`
      would refuse every subsequent RPC with `%Modal.Error{kind: :overloaded}`.
    * A burst of concurrent crashing RPCs could indefinitely wedge the
      client's effective throughput at zero.

  The regression suite here drives the real GenServer through a stub that
  always raises (`Modal.Test.RaisingStub`) and asserts each of those
  symptoms is gone.
  """
  use ExUnit.Case, async: false

  alias Modal.Client.SandboxListRequest, as: ListReq

  defp start_client!(opts \\ []) do
    {:ok, client} =
      Modal.Client.start_link(
        Keyword.merge(
          [
            token_id: "ak-crash-test",
            token_secret: "as-crash-test",
            modal_stub: Modal.Test.RaisingStub,
            connect_fn: fn s -> {:ok, %{s | channel: :test_channel}} end
          ],
          opts
        )
      )

    client
  end

  defp inflight(client), do: :sys.get_state(client).inflight

  # ── Caller surface ────────────────────────────────────────────────

  describe "caller surface on task crash" do
    test "caller receives :task_crashed Modal.Error — never blocks until timeout" do
      client = start_client!()

      t0 = System.monotonic_time(:millisecond)

      result =
        Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 30_000)

      elapsed = System.monotonic_time(:millisecond) - t0

      assert {:error, %Modal.Error{kind: :task_crashed, code: :error} = err} = result
      assert %RuntimeError{message: msg} = err.metadata.reason
      assert msg =~ "RaisingStub"

      assert elapsed < 500,
             "Reply must arrive promptly after crash, got #{elapsed}ms " <>
               "(would have been ~timeout before the fix)"

      GenServer.stop(client)
    end

    test "stream RPCs that crash inside the stub get the same surface" do
      client = start_client!()

      assert {:error, %Modal.Error{kind: :task_crashed, code: :error}} =
               Modal.Client.stream_rpc(client, :sandbox_list, %ListReq{}, 5_000)

      GenServer.stop(client)
    end
  end

  # ── :inflight counter ─────────────────────────────────────────────

  describe ":inflight counter recovery" do
    test "counter returns to zero after a single crashing RPC" do
      client = start_client!()

      assert {:error, %Modal.Error{kind: :task_crashed}} =
               Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      # The `:task_completed` cast is async, but it must land before
      # subsequent calls observe a leaked counter. Settle the mailbox via
      # a synchronous round-trip (any GenServer.call works).
      :pong = GenServer.call(client, :ping)

      assert inflight(client) == 0
      GenServer.stop(client)
    end

    test "counter returns to zero after N concurrent crashes" do
      client = start_client!()
      n = 25

      results =
        1..n
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)
          end)
        end)
        |> Task.await_many(10_000)

      assert Enum.all?(results, &match?({:error, %Modal.Error{kind: :task_crashed}}, &1))

      :pong = GenServer.call(client, :ping)
      assert inflight(client) == 0

      GenServer.stop(client)
    end
  end

  # ── max_concurrency interaction ───────────────────────────────────

  describe ":max_concurrency cap is restored after crashes" do
    test "second RPC at cap=1 is NOT rejected as :overloaded after the first crashes" do
      client = start_client!(max_concurrency: 1)

      # Serial — the first call must fully drain before the second starts.
      assert {:error, %Modal.Error{kind: :task_crashed}} =
               Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      :pong = GenServer.call(client, :ping)

      # If `:task_completed` had been lost on crash, the second would
      # be :overloaded instead.
      assert {:error, %Modal.Error{kind: :task_crashed}} =
               Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      GenServer.stop(client)
    end

    test "burst of crashes at cap=2 doesn't permanently wedge throughput" do
      :persistent_term.put(:modal_switchable_mode, :crash)
      on_exit(fn -> :persistent_term.erase(:modal_switchable_mode) end)

      client = start_client!(modal_stub: Modal.Test.SwitchableStub, max_concurrency: 2)

      Enum.each(1..10, fn _ ->
        assert {:error, %Modal.Error{kind: :task_crashed}} =
                 Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)
      end)

      :pong = GenServer.call(client, :ping)
      assert inflight(client) == 0

      :persistent_term.put(:modal_switchable_mode, :ok)

      assert {:ok, %Modal.Client.SandboxListResponse{}} =
               Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      GenServer.stop(client)
    end
  end

  # ── Crash classifications ─────────────────────────────────────────

  describe "crash kind classification" do
    test "exit(:reason) inside the stub surfaces as code: :exit" do
      defmodule ExitingStub do
        @behaviour Modal.ModalStub.Behaviour
        @impl true
        def call(_c, _m, _r, _o), do: exit(:explicit_exit)
        @impl true
        def stream(_c, _m, _r, _o), do: {:ok, []}
      end

      client = start_client!(modal_stub: ExitingStub)

      assert {:error,
              %Modal.Error{
                kind: :task_crashed,
                code: :exit,
                metadata: %{reason: :explicit_exit}
              }} = Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      GenServer.stop(client)
    end

    test "throw inside the stub surfaces as code: :throw" do
      defmodule ThrowingStub do
        @behaviour Modal.ModalStub.Behaviour
        @impl true
        def call(_c, _m, _r, _o), do: throw(:thrown_value)
        @impl true
        def stream(_c, _m, _r, _o), do: {:ok, []}
      end

      client = start_client!(modal_stub: ThrowingStub)

      assert {:error,
              %Modal.Error{
                kind: :task_crashed,
                code: :throw,
                metadata: %{reason: :thrown_value}
              }} = Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)

      GenServer.stop(client)
    end
  end
end
