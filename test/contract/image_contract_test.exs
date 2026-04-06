defmodule Modal.Contract.ImageTest do
  @moduledoc """
  Validates that Modal.ImageTest mocks match the real API.

  Our mocks assume:
    - rpc(:image_get_or_create, ...) → {:ok, %ImageGetOrCreateResponse{image_id: "im-..."}}
    - stream_rpc(:image_join_streaming, ...) → {:ok, [%ImageJoinStreamingResponse{task_logs: [...]}]}
    - When cached: task_logs is [] in every response
    - When built: at least one response has non-empty task_logs
    - ImageJoinStreamingResponse has fields: task_logs, result
    - TaskLogs has field: data (not :message — a past bug)
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 300_000

  @dockerfile ["FROM python:3.12-slim"]

  setup_all do
    client = Support.client!()
    {:ok, app_id} = Modal.App.lookup(client, "elixir-contract-test")
    %{client: client, app_id: app_id}
  end

  test "get_or_create returns {:ok, image_id, status} 3-tuple", %{client: client, app_id: app_id} do
    result = Modal.Image.get_or_create(client, @dockerfile, app_id: app_id)
    assert {:ok, image_id, status} = result
    assert is_binary(image_id)
    assert String.starts_with?(image_id, "im-")
    assert status in [:cached, :built]
  end

  test "second call for same dockerfile returns :cached", %{client: client, app_id: app_id} do
    # First call builds or finds the image.
    {:ok, id1, _} = Modal.Image.get_or_create(client, @dockerfile, app_id: app_id)
    # Second call with identical commands must hit the content-addressed cache.
    {:ok, id2, status} = Modal.Image.get_or_create(client, @dockerfile, app_id: app_id)

    assert id1 == id2
    assert status == :cached
  end

  test "ImageJoinStreamingResponse has :task_logs and :result fields",
       %{client: client, app_id: app_id} do
    # Drive the raw RPC to inspect the response shape directly —
    # this is what the mock must faithfully replicate.
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :image_get_or_create,
        %Modal.Client.ImageGetOrCreateRequest{
          image: %Modal.Client.Image{dockerfile_commands: @dockerfile},
          app_id: app_id
        }
      )

    assert is_binary(resp.image_id)

    {:ok, responses} =
      Modal.Client.stream_rpc(
        client,
        :image_join_streaming,
        %Modal.Client.ImageJoinStreamingRequest{
          image_id: resp.image_id,
          timeout: 60.0,
          include_logs_for_finished: false
        }
      )

    assert is_list(responses)

    for r <- responses do
      # Struct fields our mock relies on must exist.
      assert Map.has_key?(r, :task_logs)
      assert Map.has_key?(r, :result)
      assert is_list(r.task_logs)

      # TaskLogs field is :data, not :message — validates mock correctness.
      for log <- r.task_logs do
        assert Map.has_key?(log, :data)
        assert is_binary(log.data)
      end
    end
  end
end
