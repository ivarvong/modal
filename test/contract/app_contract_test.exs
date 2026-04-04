defmodule Modal.Contract.AppTest do
  @moduledoc """
  Validates that Modal.AppTest mocks match the real API.

  Our mock assumes:
    - rpc(:app_get_or_create, ...) → {:ok, %Modal.Client.AppGetOrCreateResponse{app_id: "ap-..."}}
  """
  use ExUnit.Case, async: false
  @moduletag :contract

  setup_all do
    %{client: Modal.Contract.Support.client!()}
  end

  test "App.lookup returns {:ok, app_id} where app_id is a string starting with 'ap-'",
       %{client: client} do
    assert {:ok, app_id} = Modal.App.lookup(client, "elixir-contract-test")
    assert is_binary(app_id)
    assert String.starts_with?(app_id, "ap-")
  end

  test "App.lookup is idempotent — second call returns the same app_id", %{client: client} do
    {:ok, id1} = Modal.App.lookup(client, "elixir-contract-test")
    {:ok, id2} = Modal.App.lookup(client, "elixir-contract-test")
    assert id1 == id2
  end
end
