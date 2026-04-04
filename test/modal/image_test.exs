defmodule Modal.ImageTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @dockerfile ["FROM python:3.12-slim"]
  @image_id "im-abc123"

  defp stub_get_or_create do
    Modal.Client.Mock
    |> expect(:rpc, fn @client, :image_get_or_create, _req, _timeout ->
      {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: @image_id}}
    end)
  end

  describe "get_or_create/3" do
    test "returns :cached when stream has no task_logs" do
      stub_get_or_create()

      Modal.Client.Mock
      |> expect(:stream_rpc, fn @client, :image_join_streaming, _req, _timeout ->
        {:ok, [%Modal.Client.ImageJoinStreamingResponse{task_logs: []}]}
      end)

      assert {:ok, @image_id, :cached} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end

    test "returns :built when stream has task_logs" do
      stub_get_or_create()

      Modal.Client.Mock
      |> expect(:stream_rpc, fn @client, :image_join_streaming, _req, _timeout ->
        log = %Modal.Client.TaskLogs{data: "Step 1/3 : FROM python:3.12-slim"}
        {:ok, [%Modal.Client.ImageJoinStreamingResponse{task_logs: [log]}]}
      end)

      assert {:ok, @image_id, :built} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end

    test "returns error when build fails" do
      stub_get_or_create()

      Modal.Client.Mock
      |> expect(:stream_rpc, fn @client, :image_join_streaming, _req, _timeout ->
        result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_FAILURE, exception: "OOM"}
        {:ok, [%Modal.Client.ImageJoinStreamingResponse{task_logs: [], result: result}]}
      end)

      assert {:error, {:image_build_failed, :GENERIC_STATUS_FAILURE}} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end

    test "passes app_id in the request" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :image_get_or_create, req, _timeout ->
        assert req.app_id == "ap-xyz"
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: @image_id}}
      end)
      |> expect(:stream_rpc, fn @client, :image_join_streaming, _req, _timeout ->
        {:ok, [%Modal.Client.ImageJoinStreamingResponse{task_logs: []}]}
      end)

      assert {:ok, @image_id, :cached} =
               Modal.Image.get_or_create(@client, @dockerfile, app_id: "ap-xyz")
    end

    test "propagates RPC errors from get_or_create" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :image_get_or_create, _req, _timeout ->
        {:error, {:grpc, 14, "unavailable"}}
      end)

      assert {:error, {:grpc, 14, "unavailable"}} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end
  end
end
