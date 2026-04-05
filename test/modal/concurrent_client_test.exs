defmodule Modal.ConcurrentClientTest do
  @moduledoc """
  Tests for Modal.Client concurrency and credential isolation.

  These tests start real Modal.Client GenServer instances (not the Mox mock)
  and use custom stub implementations to observe behavior without a live
  gRPC connection.
  """
  use ExUnit.Case, async: false

  # Start a real Modal.Client with a fake (non-connecting) URL, then inject
  # a fake channel so the GenServer thinks it's connected. The stub handles
  # all calls without touching the network.
  defp start_client(token_id, opts \\ []) do
    token_secret = Keyword.get(opts, :token_secret, "test-secret")
    stub = Keyword.get(opts, :modal_stub, Modal.Test.SlowStub)

    {:ok, client} =
      Modal.Client.start_link(
        token_id: token_id,
        token_secret: token_secret,
        # Port 1 is reserved and will be refused immediately — gRPC handles
        # this gracefully (channel: nil) rather than crashing init/1.
        server_url: "localhost:1",
        modal_stub: stub
      )

    # Bypass the real connection — inject a fake channel so ensure_channel/1
    # returns {:ok, state} and the GenServer dispatches Tasks normally.
    :sys.replace_state(client, fn state -> %{state | channel: :fake_channel} end)
    client
  end

  # ── Concurrency ──────────────────────────────────────────────────

  describe "async dispatch" do
    test "N concurrent RPCs complete in parallel, not serially" do
      client = start_client("ak-concurrent-test")

      n = 5
      stub_delay_ms = 50

      {elapsed_us, results} =
        :timer.tc(fn ->
          1..n
          |> Enum.map(fn _ ->
            Task.async(fn ->
              Modal.Client.rpc(
                client,
                :sandbox_list,
                %Modal.Client.SandboxListRequest{},
                5_000
              )
            end)
          end)
          |> Task.await_many(10_000)
        end)

      elapsed_ms = div(elapsed_us, 1_000)

      # All RPCs must succeed.
      assert Enum.all?(results, &match?({:ok, _}, &1)),
             "Expected all RPCs to succeed, got: #{inspect(results)}"

      # If dispatched serially: elapsed ~ n * stub_delay_ms = 250ms.
      # If dispatched concurrently: elapsed ~ stub_delay_ms = 50ms.
      # We allow 3x the stub delay to absorb scheduling jitter.
      assert elapsed_ms < stub_delay_ms * 3,
             "Expected parallel execution (~#{stub_delay_ms}ms), " <>
               "got #{elapsed_ms}ms — serial would be #{n * stub_delay_ms}ms"

      GenServer.stop(client)
    end

    test "GenServer mailbox stays responsive while RPCs are in-flight" do
      client = start_client("ak-mailbox-test")

      # Fire a slow RPC asynchronously — if the GenServer is blocked on this
      # call it won't be able to process the ping below.
      slow_task =
        Task.async(fn ->
          Modal.Client.rpc(client, :sandbox_list, %Modal.Client.SandboxListRequest{}, 5_000)
        end)

      # Immediately after, fire a fast ping via GenServer.call. If the GenServer
      # is blocked on the slow RPC, this will timeout.
      assert :pong = GenServer.call(client, :ping, 500),
             "GenServer was blocked on an in-flight RPC"

      Task.await(slow_task, 5_000)
      GenServer.stop(client)
    end
  end

  # ── Credential isolation ──────────────────────────────────────────

  describe "credential isolation" do
    test "two clients with different credentials never share metadata" do
      # Register this test process as the recorder.
      :persistent_term.put(:modal_spy_recorder, self())

      client_a =
        start_client("ak-client-a",
          token_secret: "as-secret-a",
          modal_stub: Modal.Test.CredentialSpyStub
        )

      client_b =
        start_client("ak-client-b",
          token_secret: "as-secret-b",
          modal_stub: Modal.Test.CredentialSpyStub
        )

      # Fire one RPC through each client.
      {:ok, _} =
        Modal.Client.rpc(client_a, :sandbox_list, %Modal.Client.SandboxListRequest{}, 5_000)

      {:ok, _} =
        Modal.Client.rpc(client_b, :sandbox_list, %Modal.Client.SandboxListRequest{}, 5_000)

      # Collect recorded token-ids (Tasks send messages to this test process).
      tokens = collect_spy_messages(2)

      assert "ak-client-a" in tokens, "client-a's token was never seen"
      assert "ak-client-b" in tokens, "client-b's token was never seen"
      assert length(tokens) == 2, "Expected exactly 2 RPCs, got #{length(tokens)}"

      # Neither client's token appeared in the other's call.
      # (If credentials leaked, we'd see one token more than once.)
      assert Enum.uniq(tokens) == tokens,
             "Credential bleed detected: #{inspect(tokens)}"

      GenServer.stop(client_a)
      GenServer.stop(client_b)
      :persistent_term.erase(:modal_spy_recorder)
    end

    test "credentials are set once at start and never mutate" do
      :persistent_term.put(:modal_spy_recorder, self())

      client =
        start_client("ak-immutable",
          token_secret: "as-immutable",
          modal_stub: Modal.Test.CredentialSpyStub
        )

      # Fire 3 RPCs — the token must be the same every time.
      for _ <- 1..3 do
        {:ok, _} =
          Modal.Client.rpc(client, :sandbox_list, %Modal.Client.SandboxListRequest{}, 5_000)
      end

      tokens = collect_spy_messages(3)

      assert Enum.all?(tokens, &(&1 == "ak-immutable")),
             "Token changed between calls: #{inspect(tokens)}"

      GenServer.stop(client)
      :persistent_term.erase(:modal_spy_recorder)
    end
  end

  # ── Bounded concurrency ──────────────────────────────────────────

  describe "max_concurrency" do
    test "returns {:error, :overloaded} when at capacity" do
      client = start_client("ak-bounded", modal_stub: Modal.Test.SlowStub)

      # Override max_concurrency to 2.
      :sys.replace_state(client, fn state -> %{state | max_concurrency: 2} end)

      # Fire 2 RPCs that will block (SlowStub sleeps 50ms).
      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Modal.Client.rpc(client, :sandbox_list, %Modal.Client.SandboxListRequest{}, 5_000)
          end)
        end

      # Give tasks a moment to start.
      Process.sleep(10)

      # Third call should be rejected immediately.
      assert {:error, :overloaded} =
               Modal.Client.rpc(client, :sandbox_list, %Modal.Client.SandboxListRequest{}, 1_000)

      # Original tasks complete fine.
      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))

      GenServer.stop(client)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  # Collect N {:spy_token, token_id} messages from the mailbox.
  defp collect_spy_messages(n, acc \\ [])
  defp collect_spy_messages(0, acc), do: Enum.reverse(acc)

  defp collect_spy_messages(n, acc) do
    receive do
      {:spy_token, token_id} -> collect_spy_messages(n - 1, [token_id | acc])
    after
      2_000 ->
        flunk("Timed out waiting for spy messages (got #{length(acc)} of #{n + length(acc)})")
    end
  end
end
