defmodule Modal.DictTest do
  @moduledoc """
  Tests for `Modal.Dict`. Pins the JSON-by-default value encoding
  contract, the `:not_found` vs `{:ok, value}` discrimination on
  `get/3` and `pop/3`, and the bulk-update path.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @dict %Modal.Dict{id: "di-test", name: "results", client: @client}

  # ── Lifecycle ───────────────────────────────────────────────────

  describe "get_or_create/3" do
    test "creates if missing and returns a struct with id + name" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_get_or_create, req, _ ->
        assert req.deployment_name == "results"
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
        {:ok, %Modal.Client.DictGetOrCreateResponse{dict_id: "di-new"}}
      end)

      assert {:ok, %Modal.Dict{id: "di-new", name: "results", client: @client}} =
               Modal.Dict.get_or_create(@client, "results")
    end
  end

  # ── Read ────────────────────────────────────────────────────────

  describe "get/3" do
    test "decodes JSON by default" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_get, req, _ ->
        assert req.dict_id == "di-test"
        assert req.key == "job_42"

        {:ok, %Modal.Client.DictGetResponse{found: true, value: ~s({"status":"done","value":100})}}
      end)

      assert {:ok, %{"status" => "done", "value" => 100}} =
               Modal.Dict.get(@dict, "job_42")
    end

    test "returns :not_found when found=false" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_get, _, _ ->
        {:ok, %Modal.Client.DictGetResponse{found: false, value: nil}}
      end)

      assert :not_found = Modal.Dict.get(@dict, "missing")
    end

    test "encoding: :raw returns bytes as-is, no JSON decode" do
      raw = <<1, 2, 3, 0xFF>>

      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_get, _, _ ->
        {:ok, %Modal.Client.DictGetResponse{found: true, value: raw}}
      end)

      assert {:ok, ^raw} = Modal.Dict.get(@dict, "blob", encoding: :raw)
    end
  end

  describe "pop/3" do
    test "atomic get + delete, JSON-decoded" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_pop, req, _ ->
        assert req.key == "k"
        {:ok, %Modal.Client.DictPopResponse{found: true, value: ~s("popped")}}
      end)

      assert {:ok, "popped"} = Modal.Dict.pop(@dict, "k")
    end

    test "returns :not_found when key wasn't there" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_pop, _, _ ->
        {:ok, %Modal.Client.DictPopResponse{found: false}}
      end)

      assert :not_found = Modal.Dict.pop(@dict, "missing")
    end
  end

  describe "contains?/2 + len/1" do
    test "contains? returns the boolean" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_contains, _, _ ->
        {:ok, %Modal.Client.DictContainsResponse{found: true}}
      end)

      assert Modal.Dict.contains?(@dict, "k")
    end

    test "len returns the integer count" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_len, _, _ ->
        {:ok, %Modal.Client.DictLenResponse{len: 42}}
      end)

      assert 42 = Modal.Dict.len(@dict)
    end
  end

  # ── Write ───────────────────────────────────────────────────────

  describe "put/4" do
    test "JSON-encodes the value and sends one entry" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_update, req, _ ->
        assert req.dict_id == "di-test"
        assert req.if_not_exists == false
        assert [%Modal.Client.DictEntry{key: "k", value: value_bytes}] = req.updates
        assert Jason.decode!(value_bytes) == %{"a" => 1, "b" => "two"}
        {:ok, %Modal.Client.DictUpdateResponse{}}
      end)

      assert :ok = Modal.Dict.put(@dict, "k", %{a: 1, b: "two"})
    end

    test "if_not_exists: true propagates to the request" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_update, req, _ ->
        assert req.if_not_exists == true
        {:ok, %Modal.Client.DictUpdateResponse{}}
      end)

      assert :ok = Modal.Dict.put(@dict, "k", "v", if_not_exists: true)
    end

    test "encoding: :raw requires a binary, raises otherwise" do
      assert_raise ArgumentError, ~r/requires a binary value/, fn ->
        Modal.Dict.put(@dict, "k", %{not: "binary"}, encoding: :raw)
      end
    end
  end

  describe "put_many/3" do
    test "sends one DictEntry per key/value, JSON-encoded" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_update, req, _ ->
        assert length(req.updates) == 3

        decoded =
          for entry <- req.updates, into: %{}, do: {entry.key, Jason.decode!(entry.value)}

        assert decoded == %{"a" => 1, "b" => 2, "c" => 3}
        {:ok, %Modal.Client.DictUpdateResponse{}}
      end)

      assert :ok = Modal.Dict.put_many(@dict, %{"a" => 1, "b" => 2, "c" => 3})
    end
  end

  describe "clear/1 + delete/1" do
    test "clear sends DictClearRequest" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_clear, req, _ ->
        assert req.dict_id == "di-test"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Dict.clear(@dict)
    end

    test "delete sends DictDeleteRequest" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :dict_delete, req, _ ->
        assert req.dict_id == "di-test"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Dict.delete(@dict)
    end
  end

  # ── Inspect ─────────────────────────────────────────────────────

  describe "Inspect" do
    test "shows id + name" do
      assert inspect(@dict) =~ "id: di-test"
      assert inspect(@dict) =~ ~s|name: "results"|
    end
  end
end
