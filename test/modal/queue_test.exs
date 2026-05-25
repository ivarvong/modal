defmodule Modal.QueueTest do
  @moduledoc """
  Tests for `Modal.Queue`. Pins the JSON-by-default encoding, the
  single-vs-list return-shape distinction on `get/2` (n=1 returns
  the value, n>1 returns a list), the `:empty` discrimination, and
  the partition pass-through.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @queue %Modal.Queue{id: "qu-test", name: "work", client: @client}

  # ── Lifecycle ───────────────────────────────────────────────────

  describe "get_or_create/3" do
    test "creates if missing and returns a struct" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get_or_create, req, _ ->
        assert req.deployment_name == "work"
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
        {:ok, %Modal.Client.QueueGetOrCreateResponse{queue_id: "qu-new"}}
      end)

      assert {:ok, %Modal.Queue{id: "qu-new", name: "work"}} =
               Modal.Queue.get_or_create(@client, "work")
    end
  end

  # ── Producer ────────────────────────────────────────────────────

  describe "put/3" do
    test "single value is wrapped to a one-element list, JSON-encoded" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_put, req, _ ->
        assert req.queue_id == "qu-test"
        assert [bytes] = req.values
        assert Jason.decode!(bytes) == %{"job" => 1}
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.put(@queue, %{job: 1})
    end

    test "put_many/3 sends N entries; put/3 with a list value sends 1" do
      # The whole reason put + put_many are split: a bare list passed
      # to put/3 should be ONE entry (the list itself), not N. To
      # push many values, use put_many/3.

      # put_many: 3 entries.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_put, req, _ ->
        assert length(req.values) == 3
        decoded = Enum.map(req.values, &Jason.decode!/1)
        assert decoded == [1, 2, 3]
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.put_many(@queue, [1, 2, 3])

      # put with a list value: 1 entry (the list).
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_put, req, _ ->
        assert [bytes] = req.values
        assert Jason.decode!(bytes) == [1, 2, 3]
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.put(@queue, [1, 2, 3])
    end

    test ":partition propagates as partition_key on the wire" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_put, req, _ ->
        assert req.partition_key == "tenant-42"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.put(@queue, "x", partition: "tenant-42")
    end

    test "encoding: :raw passes bytes through" do
      raw = <<1, 2, 3, 0xFF>>

      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_put, req, _ ->
        assert req.values == [raw]
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.put(@queue, raw, encoding: :raw)
    end

    test "encoding: :raw with non-binary value raises" do
      assert_raise ArgumentError, ~r/requires a binary value/, fn ->
        Modal.Queue.put(@queue, %{not: "binary"}, encoding: :raw)
      end
    end
  end

  # ── Consumer ────────────────────────────────────────────────────

  describe "get/2" do
    test "default n=1 returns the value unwrapped" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get, req, _ ->
        assert req.n_values == 1
        assert req.timeout == 60.0
        {:ok, %Modal.Client.QueueGetResponse{values: [~s({"job":1})]}}
      end)

      assert {:ok, %{"job" => 1}} = Modal.Queue.get(@queue)
    end

    test "n > 1 returns a list" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get, req, _ ->
        assert req.n_values == 3
        {:ok, %Modal.Client.QueueGetResponse{values: [~s(1), ~s(2), ~s(3)]}}
      end)

      assert {:ok, [1, 2, 3]} = Modal.Queue.get(@queue, n: 3)
    end

    test "empty response returns :empty" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get, _, _ ->
        {:ok, %Modal.Client.QueueGetResponse{values: []}}
      end)

      assert :empty = Modal.Queue.get(@queue, timeout_secs: 0)
    end

    test ":partition propagates as partition_key" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get, req, _ ->
        assert req.partition_key == "tenant-42"
        {:ok, %Modal.Client.QueueGetResponse{values: [~s("ok")]}}
      end)

      assert {:ok, "ok"} = Modal.Queue.get(@queue, partition: "tenant-42")
    end

    test ":timeout_secs: 0 sends timeout=0 (non-blocking)" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_get, req, _ ->
        assert req.timeout == 0.0
        {:ok, %Modal.Client.QueueGetResponse{values: []}}
      end)

      assert :empty = Modal.Queue.get(@queue, timeout_secs: 0)
    end
  end

  describe "len/2" do
    test "returns the int count" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_len, req, _ ->
        assert req.queue_id == "qu-test"
        assert req.total == false
        {:ok, %Modal.Client.QueueLenResponse{len: 7}}
      end)

      assert 7 = Modal.Queue.len(@queue)
    end

    test ":total counts across partitions" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_len, req, _ ->
        assert req.total == true
        {:ok, %Modal.Client.QueueLenResponse{len: 42}}
      end)

      assert 42 = Modal.Queue.len(@queue, total: true)
    end
  end

  describe "clear/2 + delete/1" do
    test "clear with :all_partitions" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_clear, req, _ ->
        assert req.all_partitions == true
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.clear(@queue, all_partitions: true)
    end

    test "delete sends QueueDeleteRequest" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :queue_delete, _, _ ->
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Queue.delete(@queue)
    end
  end
end
