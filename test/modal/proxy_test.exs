defmodule Modal.ProxyTest do
  @moduledoc """
  Tests for `Modal.Proxy`. Proxies are dashboard-provisioned on
  Modal — the only callable wire RPC is `ProxyGet`. See moduledoc
  on `Modal.Proxy` for the dashboard rationale.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock

  describe "get/3" do
    test "looks up by name + hydrates the struct from ProxyGetResponse" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :proxy_get, req, _ ->
        assert req.name == "customer-db"
        assert req.environment_name == "prod"

        {:ok,
         %Modal.Client.ProxyGetResponse{
           proxy: %Modal.Client.Proxy{
             proxy_id: "pr-1",
             name: "customer-db",
             region: "us-east",
             proxy_ips: [
               %Modal.Client.ProxyIp{proxy_ip: "54.220.1.1"},
               %Modal.Client.ProxyIp{proxy_ip: "54.220.1.2"}
             ]
           }
         }}
      end)

      assert {:ok,
              %Modal.Proxy{
                id: "pr-1",
                name: "customer-db",
                region: "us-east",
                ips: ["54.220.1.1", "54.220.1.2"]
              }} = Modal.Proxy.get(@client, "customer-db", environment_name: "prod")
    end

    test "missing proxy surfaces as :grpc 5 (NOT_FOUND)" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :proxy_get, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
               Modal.Proxy.get(@client, "nope")
    end

    test "get!/3 raises on error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :proxy_get, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert_raise Modal.Error, fn -> Modal.Proxy.get!(@client, "nope") end
    end
  end

  describe "Sandbox :proxy_id integration" do
    test "passing :proxy_id sets Sandbox.proxy_id on the wire" do
      app = %Modal.App{id: "ap-test", name: "test", client: @client}

      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, req, _ ->
        assert req.definition.proxy_id == "pr-1"
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: "sb-1"}}
      end)

      assert {:ok, _} =
               Modal.Sandbox.create(@client,
                 app_id: app.id,
                 image_id: "im",
                 proxy_id: "pr-1"
               )
    end
  end
end
