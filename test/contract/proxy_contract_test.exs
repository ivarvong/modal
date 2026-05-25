defmodule Modal.Contract.ProxyTest do
  @moduledoc """
  Validates `Modal.Proxy.get/3` against live Modal.

  Modal proxies are dashboard-provisioned (the ProxyGetOrCreate /
  ProxyCreate RPCs return `INVALID_ARGUMENT: "Creation method not
  supported"`). So this contract only exercises the lookup path:

    - get/3 on a non-existent proxy returns :grpc 5 (NOT_FOUND).
    - This pins the documented behavior on which the rest of
      `Modal.Proxy.get/3`'s contract rests.

  To extend this with positive-path tests (lookup succeeds + IPs
  populated), create a proxy named `contract-test` in the dashboard.
  Skipped here so the contract suite doesn't require manual setup
  or billable IP allocations.
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 30_000

  setup_all do
    %{client: Support.client!()}
  end

  test "get/3 on a non-existent name returns :grpc 5 (NOT_FOUND)", %{client: client} do
    nonexistent = "definitely-not-a-real-proxy-#{System.os_time(:second)}"

    assert {:error, %Modal.Error{kind: :grpc, code: 5}} = Modal.Proxy.get(client, nonexistent)
  end
end
