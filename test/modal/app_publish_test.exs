defmodule Modal.AppPublishTest do
  @moduledoc """
  Tests for `Modal.App.publish/3`. The standalone surface for the
  third RPC in the Function-deploy dance; called automatically by
  `Modal.Function.deploy_asgi/2` but also exposed for advanced uses
  (manual publishing, multi-function apps, deploy-then-stop flows).
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @app %Modal.App{id: "ap-test", name: "my-svc", client: @client}

  describe "publish/3" do
    test "default :state is :deployed → APP_STATE_DEPLOYED on the wire" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_publish, req, _ ->
        assert req.app_state == :APP_STATE_DEPLOYED
        {:ok, %Modal.Client.AppPublishResponse{url: "https://dash", deployed_at: 0.0}}
      end)

      assert {:ok, %{url: "https://dash", deployed_at: +0.0}} =
               Modal.App.publish(@client, @app, function_ids: %{"web" => "fu-1"})
    end

    test ":stopped maps to APP_STATE_STOPPED" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_publish, req, _ ->
        assert req.app_state == :APP_STATE_STOPPED
        {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)

      assert {:ok, _} = Modal.App.publish(@client, @app, state: :stopped)
    end

    test "function_ids map is sent verbatim" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_publish, req, _ ->
        assert req.function_ids == %{"web" => "fu-1", "api" => "fu-2"}
        {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.App.publish(@client, @app, function_ids: %{"web" => "fu-1", "api" => "fu-2"})
    end

    test "deployment_tag is sent on the wire" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_publish, req, _ ->
        assert req.deployment_tag == "v1.2.3"
        {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.App.publish(@client, @app,
                 function_ids: %{"web" => "fu-1"},
                 deployment_tag: "v1.2.3"
               )
    end

    test "unknown state returns :validation" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.App.publish(@client, @app, state: :rollback_to_yesterday)
    end

    test "propagates RPC error" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :app_publish, _req, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14}} =
               Modal.App.publish(@client, @app, function_ids: %{"web" => "fu-1"})
    end
  end
end
