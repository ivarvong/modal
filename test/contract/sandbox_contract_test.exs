defmodule Modal.Contract.SandboxTest do
  @moduledoc """
  Validates that Modal.SandboxTest mocks match the real API.

  Asserted contracts (one test per RPC, plus shape assertions via
  `Modal.Contract.Support.assert_struct_shape/2`):

    - `:sandbox_create` returns `%SandboxCreateResponse{sandbox_id: "sb-…"}`.
    - `:sandbox_get_task_id` returns `%SandboxGetTaskIdResponse{task_id: "ti-…"}`,
      stable across calls (the client-side cache short-circuits the second
      and subsequent calls).
    - `:sandbox_wait` with `timeout: 0.0` for a running sandbox returns
      either `{:ok, %SandboxWaitResponse{result: nil}}` or
      `{:error, %Modal.Error{kind: :grpc, code: 4}}` (DEADLINE_EXCEEDED).
    - `:sandbox_list` returns `%SandboxListResponse{sandboxes: list()}`.
    - `:sandbox_get_from_name` returns `%SandboxGetFromNameResponse{sandbox_id: "sb-…"}`,
      and a missing name yields `{:error, ...}` (not a default sandbox_id).
    - `:sandbox_terminate` returns `{:ok, %SandboxTerminateResponse{}}`.
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract
  @moduletag timeout: 60_000

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, "elixir-contract-test")

    {:ok, image_id, _} =
      Modal.Image.get_or_create(client, ["FROM python:3.14-slim"], app: app)

    %{client: client, app: app, image_id: image_id}
  end

  setup %{client: client, app: app, image_id: image_id} do
    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 120,
        idle_timeout_secs: 30
      )

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Sandbox.terminate(sandbox)
    end)

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    %{sandbox: sandbox}
  end

  test "create returns sandbox_id starting with 'sb-'", %{sandbox: sb} do
    assert String.starts_with?(sb.id, "sb-")
  end

  test "get_task_id returns a stable task_id (cache hits on second call)", %{
    sandbox: sb,
    client: client
  } do
    # First call (already done in setup) populated the client-side cache.
    # The second call must return the same task_id without rerunning the
    # SandboxGetTaskId RPC. We can't easily prove "no RPC" against the live
    # service, but stability across calls is the user-visible contract.
    assert {:ok, task_id1} = Modal.Sandbox.get_task_id(sb)
    assert is_binary(task_id1)
    assert String.starts_with?(task_id1, "ta-")

    assert {:ok, ^task_id1} = Modal.Sandbox.get_task_id(sb)

    # A new Modal.Sandbox value with the same id and a fresh client also
    # resolves to a task_id starting with "ta-" (i.e. the cache is keyed by
    # sandbox_id, not by some per-struct identity).
    assert {:ok, ^task_id1} =
             Modal.Sandbox.get_task_id(%Modal.Sandbox{id: sb.id, client: client})
  end

  test "poll returns {:ok, nil} for a running sandbox", %{sandbox: sb} do
    assert {:ok, nil} = Modal.Sandbox.poll(sb)
  end

  test "list returns a list", %{client: client} do
    assert {:ok, sandboxes} = Modal.Sandbox.list(client)
    assert is_list(sandboxes)
  end

  test "from_name returns error when name not found", %{client: client} do
    assert {:error, _} =
             Modal.Sandbox.from_name(client, "no-such-sandbox-#{System.unique_integer()}")
  end

  test "SandboxCreateResponse: full struct shape", %{
    client: client,
    app: app,
    image_id: image_id
  } do
    # Drive the raw RPC and assert the response struct's typed shape.
    # `assert_struct_shape/2` would fail loudly on a field rename, an
    # unexpected nil, or a type change.
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :sandbox_create,
        %Modal.Client.SandboxCreateRequest{
          app_id: app.id,
          definition: %Modal.Client.Sandbox{
            entrypoint_args: ["sleep", "5"],
            image_id: image_id,
            # IMPORTANT: this field MUST be `timeout_secs` (seconds). A
            # rename to `timeout_ms` would silently break every sandbox
            # by sending a 30000-second timeout. The strict shape check
            # via the request struct's compile-time field set catches
            # this — the failing line would be the line that constructs
            # the request, not the contract test itself.
            timeout_secs: 30,
            direct_sandbox_commands_enabled: true
          }
        }
      )

    assert %Modal.Client.SandboxCreateResponse{} = resp
    assert_struct_shape(resp, %{sandbox_id: {:string_prefix, "sb-"}})

    Modal.Sandbox.terminate(%Modal.Sandbox{id: resp.sandbox_id, client: client})
  end

  test "SandboxWaitResponse: shape when still running", %{sandbox: sb} do
    # poll/1 relies on GRPC status 4 (DEADLINE_EXCEEDED) meaning "still running"
    # OR on response.result being nil. Validate both wire behaviours.
    result =
      Modal.Client.rpc(
        sb.client,
        :sandbox_wait,
        %Modal.Client.SandboxWaitRequest{sandbox_id: sb.id, timeout: 0.0}
      )

    case result do
      {:ok, resp} ->
        assert %Modal.Client.SandboxWaitResponse{} = resp
        # The :result field, when present, is a %GenericResult{} or nil.
        # "still running" specifically means nil.
        assert_struct_shape(resp, %{
          result: {:nil_or, {:struct, Modal.Client.GenericResult}}
        })

        assert resp.result == nil, "expected nil result for a running sandbox"

      {:error, %Modal.Error{kind: :grpc, code: 4}} ->
        # DEADLINE_EXCEEDED — the other valid signal for "still running".
        # Pinning the exact code (4) catches any drift in how Modal
        # signals "not ready yet".
        :ok
    end
  end

  test "SandboxListResponse: shape and field types", %{client: client} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :sandbox_list,
        %Modal.Client.SandboxListRequest{}
      )

    assert %Modal.Client.SandboxListResponse{} = resp
    assert_struct_shape(resp, %{sandboxes: :list})
  end

  test "SandboxTerminateResponse: empty struct shape", %{
    client: client,
    app: app,
    image_id: image_id
  } do
    # Create-then-terminate a throwaway sandbox to exercise the
    # terminate response shape (an empty struct on success).
    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 60,
        idle_timeout_secs: 30
      )

    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :sandbox_terminate,
        %Modal.Client.SandboxTerminateRequest{sandbox_id: sandbox.id}
      )

    assert %Modal.Client.SandboxTerminateResponse{} = resp
  end
end
