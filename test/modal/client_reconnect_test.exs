defmodule Modal.ClientReconnectTest do
  @moduledoc """
  Pins the epoch-deduplicated reconnect contract in `Modal.Client`.

  Pre-fix shape of the bug: every task that observed a network error cast
  `:connection_failed`, and every cast triggered a full `reconnect/1` —
  disconnect, re-open, replace state. With N concurrent in-flight tasks
  that all observed the same dead channel, this produced a stampede of N
  reconnects, blocking the GenServer mailbox and pummeling the gRPC client.

  Post-fix shape: each dispatch tags its task with the epoch it observed
  at dispatch time. `handle_cast({:connection_failed, e})` only reconnects
  when `e == current_epoch`. A successful reconnect bumps the epoch, so
  every other stale cast becomes a no-op.

  This suite proves:

    * N concurrent failing RPCs trigger exactly ONE reconnect (the
      stampede regression).
    * After reconnect, the next dispatched task uses the NEW epoch and CAN
      trigger another reconnect if it also fails (i.e. we didn't
      over-deduplicate — we only collapsed stale casts).
    * A gun_down message doesn't itself trigger a reconnect — only an
      observed failure does.
    * The connect_fn is called exactly once per generation.
  """
  use ExUnit.Case, async: false

  alias Modal.Client.SandboxListRequest, as: ListReq

  defp start_client_with_counter!(opts \\ []) do
    counter = :counters.new(1, [:atomics])

    connect_fn = fn s ->
      :counters.add(counter, 1, 1)
      {:ok, %{s | channel: :test_channel}}
    end

    {:ok, client} =
      Modal.Client.start_link(
        Keyword.merge(
          [
            token_id: "ak-reconnect-test",
            token_secret: "as-reconnect-test",
            modal_stub: Modal.Test.NetworkErrorStub,
            connect_fn: connect_fn
          ],
          opts
        )
      )

    {client, counter}
  end

  defp connect_count(counter), do: :counters.get(counter, 1)
  defp epoch(client), do: :sys.get_state(client).epoch

  # ── The stampede regression ───────────────────────────────────────

  describe "reconnect stampede" do
    test "N concurrent network errors trigger exactly ONE reconnect" do
      # Use a barrier-synchronized stub so all N task bodies are confirmed
      # to have captured epoch=1 BEFORE any of them returns and triggers
      # a `:connection_failed` cast. Without the barrier this test is
      # racy: task bodies that finish before all 25 are dispatched can
      # interleave their casts with later handle_call dispatches, causing
      # the later tasks to capture a post-reconnect epoch.
      :persistent_term.put(:modal_barrier_pid, self())
      on_exit(fn -> :persistent_term.erase(:modal_barrier_pid) end)

      {client, counter} =
        start_client_with_counter!(modal_stub: Modal.Test.BarrierNetworkErrorStub)

      assert connect_count(counter) == 1
      assert epoch(client) == 1

      n = 25

      tasks =
        Enum.map(1..n, fn _ ->
          Task.async(fn ->
            Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 30_000)
          end)
        end)

      # Collect all N arrivals — proves every task body is now executing
      # inside the dispatched Task and has thereby captured the current
      # epoch. Equivalent to taking a "ready set" snapshot.
      arrived =
        Enum.map(1..n, fn _ ->
          receive do
            {:arrived, pid} -> pid
          after
            5_000 -> flunk("timed out waiting for tasks to arrive at the barrier")
          end
        end)

      # All tasks at the barrier. Release them simultaneously — they will
      # each return {:error, :closed} and fire a `:connection_failed` cast
      # carrying epoch=1.
      Enum.each(arrived, &send(&1, :release))

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(
               results,
               &match?({:error, %Modal.Error{kind: :network, code: :closed}}, &1)
             )

      # Drain the mailbox so every `:connection_failed` cast has been
      # handled before we assert.
      :pong = GenServer.call(client, :ping)

      assert connect_count(counter) == 2,
             "Expected 2 connects (init + 1 reconnect), got " <>
               "#{connect_count(counter)} — stampede regression"

      assert epoch(client) == 2

      GenServer.stop(client)
    end

    test "second burst (after the first reconnect) gets its own reconnect — no over-dedup" do
      # Same barrier strategy as the stampede test, applied twice. Without
      # the barrier the burst is racy: a task that fails before its peers
      # are even dispatched gets its `:connection_failed` cast processed
      # first, the GenServer reconnects, and subsequent dispatches observe
      # the new epoch — turning what should be N-collapsed-to-1 into a
      # spread that's anywhere from 1 to N. We don't need the test to
      # observe scheduler noise; we want to test the epoch dedup contract.
      :persistent_term.put(:modal_barrier_pid, self())
      on_exit(fn -> :persistent_term.erase(:modal_barrier_pid) end)

      {client, counter} =
        start_client_with_counter!(modal_stub: Modal.Test.BarrierNetworkErrorStub)

      assert connect_count(counter) == 1

      run_burst = fn n ->
        tasks =
          Enum.map(1..n, fn _ ->
            Task.async(fn ->
              Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 30_000)
            end)
          end)

        arrived =
          Enum.map(1..n, fn _ ->
            receive do
              {:arrived, pid} -> pid
            after
              5_000 -> flunk("burst didn't arrive at barrier")
            end
          end)

        Enum.each(arrived, &send(&1, :release))
        Task.await_many(tasks, 10_000)
      end

      # First burst — collapses to a single reconnect.
      run_burst.(5)
      :pong = GenServer.call(client, :ping)
      assert connect_count(counter) == 2
      assert epoch(client) == 2

      # Second burst — observes the new epoch and triggers its own single
      # reconnect (not silenced by stale-epoch dedup).
      run_burst.(5)
      :pong = GenServer.call(client, :ping)
      assert connect_count(counter) == 3
      assert epoch(client) == 3

      GenServer.stop(client)
    end
  end

  # ── gun_down semantics ────────────────────────────────────────────

  describe "gun_down handling" do
    test "gun_down clears the channel but does NOT itself trigger a reconnect" do
      # gun_down is a passive signal — the channel goes nil, and the next
      # RPC's `ensure_channel/1` is what actually reopens. This avoids
      # eager reconnects when no work is queued.
      {client, counter} = start_client_with_counter!()
      assert connect_count(counter) == 1

      send(client, {:gun_down, :fake_pid, :http2, :reason, []})
      :pong = GenServer.call(client, :ping)

      # No reconnect yet — counter unchanged.
      assert connect_count(counter) == 1

      state = :sys.get_state(client)
      assert state.channel == nil

      # The very next RPC opens a fresh channel via ensure_channel/1 →
      # connect/1 → counter goes up.
      Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 5_000)
      :pong = GenServer.call(client, :ping)

      # connect ran (counter 2). The RPC then failed and triggered a
      # stale-vs-current epoch check that, depending on capture timing,
      # may have triggered one more reconnect — bound it loosely to
      # leave room for either case, but ensure we never see 1 (no
      # reopen happened) or many (stampede).
      total = connect_count(counter)
      assert total in 2..3, "Expected 2 or 3 connects, got #{total}"

      GenServer.stop(client)
    end
  end

  # ── Reconnect path is defensive (the safe_disconnect change) ──────

  describe "safe_disconnect under crash" do
    test "GRPC.Stub.disconnect/1 crashing during reconnect does NOT kill the client" do
      # Sanity check that the safe_disconnect wrapper introduced for Fix 1
      # also covers the reconnect path. Use the barrier stub so all three
      # tasks observe the same epoch, otherwise this is racy in the same
      # way as the stampede test.
      :persistent_term.put(:modal_barrier_pid, self())
      on_exit(fn -> :persistent_term.erase(:modal_barrier_pid) end)

      {client, counter} =
        start_client_with_counter!(modal_stub: Modal.Test.BarrierNetworkErrorStub)

      assert connect_count(counter) == 1
      pid = client

      n = 3

      tasks =
        Enum.map(1..n, fn _ ->
          Task.async(fn ->
            Modal.Client.rpc(client, :sandbox_list, %ListReq{}, 30_000)
          end)
        end)

      arrived =
        Enum.map(1..n, fn _ ->
          receive do
            {:arrived, pid} -> pid
          after
            5_000 -> flunk("burst didn't arrive at barrier")
          end
        end)

      Enum.each(arrived, &send(&1, :release))
      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, &match?({:error, %Modal.Error{kind: :network}}, &1))
      :pong = GenServer.call(client, :ping)

      # Client must still be alive and exactly ONE reconnect must have run
      # (the safe_disconnect wrapper would otherwise have crashed the
      # GenServer during reconnect).
      assert Process.alive?(pid)
      assert connect_count(counter) == 2

      GenServer.stop(client)
    end
  end
end
