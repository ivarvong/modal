defmodule Modal.Contract.QueueTest do
  @moduledoc """
  Validates that Modal.QueueTest mocks match the real API.

  Asserted contract:
    - `:queue_get_or_create` returns `%QueueGetOrCreateResponse{queue_id: "qu-…"}`.
    - `put` / `put_many` / `get` (single + N + empty) / `len` / `clear`
      round-trip with the live Queue server.
    - `Queue.get` is a server-side atomic pop — two consumers racing on the
      same queue each pop different items, never the same one.
    - `put/3` semantics: list-typed values stay as ONE item; `put_many/3`
      sends them as N items (the v0.3 split that fixed the List.wrap bug).
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract
  @moduletag timeout: 60_000

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, Support.app_name())
    %{client: client, app: app}
  end

  setup %{client: client, app: app} do
    name = "contract-queue-#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"
    {:ok, queue} = Modal.Queue.get_or_create(client, name, app: app)

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Queue.delete(queue)
    end)

    %{queue: queue}
  end

  test "QueueGetOrCreateResponse shape", %{client: client} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :queue_get_or_create,
        %Modal.Client.QueueGetOrCreateRequest{
          deployment_name: "shape-check-#{System.os_time(:second)}",
          object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
        }
      )

    assert %Modal.Client.QueueGetOrCreateResponse{} = resp
    assert_struct_shape(resp, %{queue_id: {:string_prefix, "qu-"}})
  end

  test "put then get round-trips JSON", %{queue: queue} do
    payload = %{"job_id" => 7, "samples" => 1000}
    :ok = Modal.Queue.put(queue, payload)
    assert {:ok, ^payload} = Modal.Queue.get(queue, timeout_secs: 5.0)
  end

  test "put/3 with a list value stays as ONE item (not N — v0.3 fix)", %{queue: queue} do
    list_value = [1, 2, 3]
    :ok = Modal.Queue.put(queue, list_value)
    assert Modal.Queue.len(queue) == 1
    assert {:ok, ^list_value} = Modal.Queue.get(queue, timeout_secs: 5.0)
  end

  test "put_many/3 sends N items", %{queue: queue} do
    :ok = Modal.Queue.put_many(queue, [1, 2, 3])
    assert Modal.Queue.len(queue) == 3
    assert {:ok, 1} = Modal.Queue.get(queue, timeout_secs: 5.0)
    assert {:ok, 2} = Modal.Queue.get(queue, timeout_secs: 5.0)
    assert {:ok, 3} = Modal.Queue.get(queue, timeout_secs: 5.0)
  end

  test "get on empty queue returns :empty (no error)", %{queue: queue} do
    assert :empty = Modal.Queue.get(queue, timeout_secs: 1.0)
  end

  test "get with n > 1 returns a list", %{queue: queue} do
    :ok = Modal.Queue.put_many(queue, ["a", "b", "c"])
    assert {:ok, list} = Modal.Queue.get(queue, n: 3, timeout_secs: 5.0)
    assert is_list(list)
    assert length(list) == 3
  end

  test "server-side atomic pop — racing consumers never share an item", %{queue: queue} do
    # Drop 100 unique items, drain across 8 parallel consumers; assert no
    # duplicates. This is the core load-bearing guarantee of Modal.Queue
    # for fan-out work: server is the single source of arbitration.
    items = Enum.map(1..100, fn i -> %{"id" => i} end)
    :ok = Modal.Queue.put_many(queue, items)

    collected =
      1..8
      |> Task.async_stream(
        fn _ -> drain(queue) end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.flat_map(fn {:ok, items} -> items end)

    ids = Enum.map(collected, & &1["id"]) |> Enum.sort()
    assert ids == Enum.to_list(1..100)
  end

  defp drain(queue) do
    case Modal.Queue.get(queue, timeout_secs: 0.5) do
      {:ok, item} -> [item | drain(queue)]
      :empty -> []
    end
  end

  test "clear empties the queue", %{queue: queue} do
    :ok = Modal.Queue.put_many(queue, [1, 2, 3])
    :ok = Modal.Queue.clear(queue)
    assert Modal.Queue.len(queue) == 0
  end
end
