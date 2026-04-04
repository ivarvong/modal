defmodule Modal.Contract.SandboxTest do
  @moduledoc """
  Validates that Modal.SandboxTest mocks match the real API.

  Our mocks assume:
    - rpc(:sandbox_create, ...) → {:ok, %SandboxCreateResponse{sandbox_id: "sb-..."}}
    - rpc(:sandbox_get_task_id, ...) → {:ok, %SandboxGetTaskIdResponse{task_id: "ti-..."}}
    - rpc(:sandbox_wait, timeout: 0.0) → {:error, {:grpc, 4, _}} when running
    - rpc(:sandbox_list, ...) → {:ok, %SandboxListResponse{sandboxes: [...]}}
    - rpc(:sandbox_get_from_name, ...) → {:ok, %SandboxGetFromNameResponse{sandbox_id: "sb-..."}}
    - rpc(:sandbox_terminate, ...) → {:ok, %SandboxTerminateResponse{}}
  """
  use ExUnit.Case, async: false
  @moduletag :contract
  @moduletag timeout: 60_000

  setup_all do
    client = Modal.Contract.Support.client!()
    {:ok, app_id} = Modal.App.lookup(client, "elixir-contract-test")

    {:ok, image_id, _} =
      Modal.Image.get_or_create(client, ["FROM python:3.12-slim"], app_id: app_id)

    %{client: client, app_id: app_id, image_id: image_id}
  end

  setup %{client: client, app_id: app_id, image_id: image_id} do
    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout: 120,
        idle_timeout: 30
      )

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Sandbox.terminate(sandbox)
    end)

    {:ok, _task_id, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    %{sandbox: sandbox}
  end

  test "create returns sandbox_id starting with 'sb-'", %{sandbox: sb} do
    assert String.starts_with?(sb.id, "sb-")
  end

  test "get_task_id returns task_id and an updated sandbox with task_id set", %{sandbox: sb} do
    # Already called in setup — verifies the cached path works too.
    assert is_binary(sb.task_id)
    assert String.length(sb.task_id) > 0

    # Second call must return the cached task_id without an RPC.
    task_id = sb.task_id
    assert {:ok, ^task_id, ^sb} = Modal.Sandbox.get_task_id(sb)
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

  test "SandboxCreateResponse has :sandbox_id field", %{
    client: client,
    app_id: app_id,
    image_id: image_id
  } do
    # Drive the raw RPC to validate the response struct shape.
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :sandbox_create,
        %Modal.Client.SandboxCreateRequest{
          app_id: app_id,
          definition: %Modal.Client.Sandbox{
            entrypoint_args: ["sleep", "5"],
            image_id: image_id,
            timeout_secs: 30,
            direct_sandbox_commands_enabled: true
          }
        }
      )

    assert Map.has_key?(resp, :sandbox_id)
    assert String.starts_with?(resp.sandbox_id, "sb-")
    Modal.Sandbox.terminate(%Modal.Sandbox{id: resp.sandbox_id, client: client})
  end

  test "SandboxWaitResponse has :result field, nil when still running", %{sandbox: sb} do
    # poll/1 relies on GRPC status 4 (DEADLINE_EXCEEDED) meaning "still running".
    # Validate the actual wire behavior here.
    result =
      Modal.Client.rpc(
        sb.client,
        :sandbox_wait,
        %Modal.Client.SandboxWaitRequest{sandbox_id: sb.id, timeout: 0.0}
      )

    case result do
      {:ok, resp} ->
        assert Map.has_key?(resp, :result)
        assert resp.result == nil

      {:error, {:grpc, 4, _msg}} ->
        # DEADLINE_EXCEEDED — this is the other valid signal for "still running".
        :ok
    end
  end
end
