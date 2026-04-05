defmodule Modal.RPC do
  @moduledoc false

  def call(client, method, request, timeout \\ 30_000) when is_atom(method) do
    :telemetry.span([:modal, :rpc], %{method: method, kind: :unary}, fn ->
      result = client_impl().rpc(client, stub_method(method), request, timeout)
      {result, %{method: method, kind: :unary}}
    end)
  end

  def stream(client, method, request, timeout \\ 60_000) when is_atom(method) do
    :telemetry.span([:modal, :rpc], %{method: method, kind: :stream}, fn ->
      result = client_impl().stream_rpc(client, stub_method(method), request, timeout)
      {result, %{method: method, kind: :stream}}
    end)
  end

  def stream_each(client, method, request, callback, timeout \\ :infinity) when is_atom(method) do
    :telemetry.span([:modal, :rpc], %{method: method, kind: :stream_each}, fn ->
      result =
        client_impl().stream_rpc_each(client, stub_method(method), request, callback, timeout)

      {result, %{method: method, kind: :stream_each}}
    end)
  end

  def stream_reduce(client, method, request, acc, reducer, timeout \\ :infinity)
      when is_atom(method) do
    :telemetry.span([:modal, :rpc], %{method: method, kind: :stream_reduce}, fn ->
      result =
        client_impl().stream_rpc_reduce(
          client,
          stub_method(method),
          request,
          acc,
          reducer,
          timeout
        )

      {result, %{method: method, kind: :stream_reduce}}
    end)
  end

  defp client_impl, do: Application.get_env(:modal, :client_impl, Modal.Client)

  @methods %{
    AppGetOrCreate: :app_get_or_create,
    AuthTokenGet: :auth_token_get,
    ContainerExec: :container_exec,
    ContainerExecGetOutput: :container_exec_get_output,
    ContainerExecPutInput: :container_exec_put_input,
    ContainerExecWait: :container_exec_wait,
    ContainerFilesystemExec: :container_filesystem_exec,
    ContainerFilesystemExecGetOutput: :container_filesystem_exec_get_output,
    ImageGetOrCreate: :image_get_or_create,
    ImageJoinStreaming: :image_join_streaming,
    SandboxCreate: :sandbox_create,
    SandboxCreateConnectToken: :sandbox_create_connect_token,
    SandboxGetFromName: :sandbox_get_from_name,
    SandboxGetLogs: :sandbox_get_logs,
    SandboxGetTaskId: :sandbox_get_task_id,
    SandboxGetTunnels: :sandbox_get_tunnels,
    SandboxList: :sandbox_list,
    SandboxRestore: :sandbox_restore,
    SandboxSnapshot: :sandbox_snapshot,
    SandboxSnapshotFs: :sandbox_snapshot_fs,
    SandboxSnapshotWait: :sandbox_snapshot_wait,
    SandboxStdinWrite: :sandbox_stdin_write,
    SandboxTerminate: :sandbox_terminate,
    SandboxWait: :sandbox_wait,
    SandboxWaitUntilReady: :sandbox_wait_until_ready,
    TaskGetCommandRouterAccess: :task_get_command_router_access,
    WorkspaceBillingReport: :workspace_billing_report
  }

  defp stub_method(method), do: Map.fetch!(@methods, method)
end
