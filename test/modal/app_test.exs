defmodule Modal.AppTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock

  describe "lookup/3" do
    test "returns app_id on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, _req, _timeout ->
        {:ok, %Modal.Client.AppGetOrCreateResponse{app_id: "ap-abc123"}}
      end)

      assert {:ok, "ap-abc123"} = Modal.App.lookup(@client, "my-app")
    end

    test "passes environment_name option" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, req, _timeout ->
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.AppGetOrCreateResponse{app_id: "ap-staging"}}
      end)

      assert {:ok, "ap-staging"} =
               Modal.App.lookup(@client, "my-app", environment_name: "staging")
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, _req, _timeout ->
        {:error, {:grpc, 2, "unknown"}}
      end)

      assert {:error, {:grpc, 2, "unknown"}} = Modal.App.lookup(@client, "my-app")
    end
  end
end
