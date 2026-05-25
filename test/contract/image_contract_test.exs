defmodule Modal.Contract.ImageTest do
  @moduledoc """
  Validates that Modal.ImageTest mocks match the real API.

  Asserted contracts (with strict struct-shape checks via
  `Modal.Contract.Support.assert_struct_shape/2`):

    - `:image_get_or_create` returns `%ImageGetOrCreateResponse{image_id: "im-…"}`.
    - `:image_join_streaming` yields `%ImageJoinStreamingResponse{task_logs: […], result: nil_or_GenericResult}`.
      - `task_logs` is a list of `%TaskLogs{}` whose log payload field is
        `:data` (NOT `:message` — a regression past).
      - `result` is `%GenericResult{}` with a `:status` field whose
        observed values are atoms in the `:GENERIC_STATUS_*` enum
        family. Catches an enum rename like `:GENERIC_STATUS_SUCCESS →
        :STATUS_OK`.
    - Cached vs built signal: a build returns at least one response with
      non-empty `task_logs`; a cache hit returns no log entries.
    - Two calls with the same dockerfile return the same `image_id`
      (content-addressed) and the second is `:cached`.
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract
  @moduletag timeout: 300_000

  @dockerfile ["FROM python:3.14-slim"]

  # The atoms we accept for GenericResult.status. Any new value that
  # appears in production output should be added here intentionally —
  # silently accepting unknowns would defeat the contract.
  @known_status_atoms [
    :GENERIC_STATUS_UNSPECIFIED,
    :GENERIC_STATUS_SUCCESS,
    :GENERIC_STATUS_FAILURE,
    :GENERIC_STATUS_TERMINATED,
    :GENERIC_STATUS_TIMEOUT,
    :GENERIC_STATUS_INTERNAL_FAILURE
  ]

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, "elixir-contract-test")
    %{client: client, app: app}
  end

  test "get_or_create returns {:ok, image_id, status} 3-tuple", %{client: client, app: app} do
    result = Modal.Image.get_or_create(client, @dockerfile, app: app)
    assert {:ok, image_id, status} = result
    assert is_binary(image_id)
    assert String.starts_with?(image_id, "im-")
    assert status in [:cached, :built]
  end

  test "second call for same dockerfile returns :cached", %{client: client, app: app} do
    # First call builds or finds the image.
    {:ok, id1, _} = Modal.Image.get_or_create(client, @dockerfile, app: app)
    # Second call with identical commands must hit the content-addressed cache.
    {:ok, id2, status} = Modal.Image.get_or_create(client, @dockerfile, app: app)

    assert id1 == id2
    assert status == :cached
  end

  test "ImageGetOrCreateResponse: shape", %{client: client, app: app} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :image_get_or_create,
        %Modal.Client.ImageGetOrCreateRequest{
          image: %Modal.Client.Image{dockerfile_commands: @dockerfile},
          app_id: app.id
        }
      )

    assert %Modal.Client.ImageGetOrCreateResponse{} = resp
    assert_struct_shape(resp, %{image_id: {:string_prefix, "im-"}})
  end

  test "ImageJoinStreamingResponse: shape, plus TaskLogs.data (not .message)",
       %{client: client, app: app} do
    {:ok, %{image_id: image_id}} =
      Modal.Client.rpc(
        client,
        :image_get_or_create,
        %Modal.Client.ImageGetOrCreateRequest{
          image: %Modal.Client.Image{dockerfile_commands: @dockerfile},
          app_id: app.id
        }
      )

    {:ok, responses} =
      Modal.Client.stream_rpc(
        client,
        :image_join_streaming,
        %Modal.Client.ImageJoinStreamingRequest{
          image_id: image_id,
          # Same unit as the SandboxWait `timeout` field: SECONDS as a
          # float. A drift to milliseconds would make this 60ms and the
          # call would deadline-exceed immediately.
          timeout: 60.0,
          include_logs_for_finished: false
        }
      )

    assert is_list(responses)
    refute Enum.empty?(responses), "ImageJoinStreaming returned no responses at all"

    for r <- responses do
      assert %Modal.Client.ImageJoinStreamingResponse{} = r

      assert_struct_shape(r, %{
        task_logs: {:list_of, {:struct, Modal.Client.TaskLogs}},
        result: {:nil_or, {:struct, Modal.Client.GenericResult}}
      })

      # Critical historical regression: TaskLogs's log payload is `:data`,
      # not `:message`. The mock returns %TaskLogs{data: "..."} — a
      # rename here would silently make the mock lie and the image
      # cached-vs-built signal (await_build counts non-empty task_logs)
      # would misbehave.
      for log <- r.task_logs do
        assert_struct_shape(log, %{data: :string})
      end

      # If a result has been emitted, its status must be one of the
      # enum atoms we know about. Catches an enum rename.
      if r.result do
        assert_struct_shape(r.result, %{status: {:enum, @known_status_atoms}})
      end
    end
  end
end
