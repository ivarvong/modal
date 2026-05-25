defmodule Modal.Contract.DictTest do
  @moduledoc """
  Validates that Modal.DictTest mocks match the real API.

  Asserted contract:
    - `:dict_get_or_create` returns `%DictGetOrCreateResponse{dict_id: "di-…"}`.
    - `put` / `get` / `contains?` / `len` / `pop` / `clear` / `delete`
      all round-trip with the live Dict server.
    - JSON encoding survives a real put → get cycle (the contract assumed
      by `Modal.Dict` unit tests is honored by Modal's server).
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract
  @moduletag timeout: 60_000

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, "elixir-contract-test")
    %{client: client, app: app}
  end

  setup %{client: client, app: app} do
    name = "contract-dict-#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"
    {:ok, dict} = Modal.Dict.get_or_create(client, name, app: app)

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Dict.delete(dict)
    end)

    %{dict: dict, name: name}
  end

  test "DictGetOrCreateResponse shape", %{client: client, name: name} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :dict_get_or_create,
        %Modal.Client.DictGetOrCreateRequest{
          deployment_name: "shape-check-#{name}",
          object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
        }
      )

    assert %Modal.Client.DictGetOrCreateResponse{} = resp
    assert_struct_shape(resp, %{dict_id: {:string_prefix, "di-"}})
  end

  test "JSON put → get round-trip", %{dict: dict} do
    payload = %{"counter" => 42, "ok" => true, "items" => [1, 2, "three"]}
    :ok = Modal.Dict.put(dict, "k1", payload)
    assert {:ok, ^payload} = Modal.Dict.get(dict, "k1")
  end

  test ":raw bytes round-trip without re-encoding", %{dict: dict} do
    raw = <<0xFF, 0xFE, 0x00, 0x01>>
    :ok = Modal.Dict.put(dict, "k2", raw, encoding: :raw)
    assert {:ok, ^raw} = Modal.Dict.get(dict, "k2", encoding: :raw)
  end

  test "get on a missing key returns :not_found (not an error)", %{dict: dict} do
    assert :not_found = Modal.Dict.get(dict, "definitely-not-there")
  end

  test "contains? and len reflect Modal's view", %{dict: dict} do
    refute Modal.Dict.contains?(dict, "a")
    assert Modal.Dict.len(dict) == 0

    :ok = Modal.Dict.put(dict, "a", 1)
    :ok = Modal.Dict.put(dict, "b", 2)

    assert Modal.Dict.contains?(dict, "a")
    assert Modal.Dict.len(dict) == 2
  end

  test "pop is atomic get + delete", %{dict: dict} do
    :ok = Modal.Dict.put(dict, "doomed", "bye")
    assert {:ok, "bye"} = Modal.Dict.pop(dict, "doomed")
    assert :not_found = Modal.Dict.get(dict, "doomed")
  end

  test "put_many is atomic and observable", %{dict: dict} do
    :ok = Modal.Dict.put_many(dict, %{"x" => 1, "y" => 2, "z" => 3})
    assert Modal.Dict.len(dict) == 3
    assert {:ok, 2} = Modal.Dict.get(dict, "y")
  end

  test "clear empties the dict", %{dict: dict} do
    :ok = Modal.Dict.put(dict, "x", 1)
    :ok = Modal.Dict.clear(dict)
    assert Modal.Dict.len(dict) == 0
  end
end
