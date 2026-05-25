defmodule Modal.RPC do
  @moduledoc """
  Documented escape hatch for calling Modal's gRPC API directly.

  `Modal.Sandbox`, `Modal.Image`, `Modal.Volume`, `Modal.Secret`,
  `Modal.Filesystem`, and friends wrap the RPCs you'll need 95% of the
  time. When you need an RPC that *isn't* wrapped — or when you want
  finer control than the wrapper exposes — `Modal.RPC.call/4`,
  `stream/4`, and `stream_reduce/6` are the supported, SemVer-protected
  entry points.

  Every call goes through the same dispatch path as the high-level
  wrappers: per-client `Task.Supervisor`, JWT auth headers,
  `:max_concurrency` backpressure, reconnect-on-`gun_down`, and the
  same `[:modal, :rpc, :start | :stop | :exception]` telemetry events.

  ## Quick example

      alias Modal.Client
      request = %Client.SandboxListRequest{include_finished: true}
      {:ok, %Client.SandboxListResponse{sandboxes: sbs}} =
        Modal.RPC.call(client, :SandboxList, request)

  Method atoms are the **PascalCase** names that appear in
  `modal_proto/api.proto` (e.g. `:SandboxCreate`, `:SecretGetOrCreate`).
  An unknown atom raises `FunctionClauseError` at the call site — a
  typo is a compile-time-shaped error, not a runtime stacktrace from
  the generated stub.

  ## Three call shapes

    * `call/4` — unary RPC. Returns `{:ok, response_struct} | {:error, %Modal.Error{}}`.
    * `stream/4` — server-streaming RPC, collected into a list.
      Convenient for small bounded streams (`SandboxGetLogs` for a
      finished sandbox). Use `stream_reduce/6` when the stream is
      unbounded or large.
    * `stream_reduce/6` — server-streaming RPC, folded with a reducer
      that returns `{:cont, acc} | {:halt, acc}` per response. Used
      internally by `Modal.Image.get_or_create/3` to watch a long-lived
      build stream without buffering every log line.

  ## When the RPC you need isn't in the table

  The method type typespec (`@type method ::` below) lists the atoms
  this module recognises — about two dozen. For an RPC that *isn't*
  in the table
  — say, a brand-new proto method Modal ships next week —
  `Modal.Client.rpc/4` (the lower-level entry on the
  `Modal.Client` GenServer) is the fallback. It accepts any
  `snake_case` atom matching a function on the generated gRPC stub
  module. You lose the typo-safety check and the
  `[:modal, :rpc, :*]` telemetry events, but you can reach every RPC
  the proto defines. File an issue (or a PR adding the atom to
  `@methods`) when you find one.

  ## Stability promise

  The `call/4`, `stream/4`, and `stream_reduce/6` signatures, the
  `[:modal, :rpc, :*]` telemetry events, and the set of method type
  atoms in the dispatch table are SemVer-protected. New atoms added to `@methods` are a
  minor-version change; removing an atom or renaming it is a major.
  The error shapes follow `Modal.Error`'s contract.
  """

  # Maps domain-level RPC names (PascalCase atoms matching the proto service
  # definition) to the snake_case function names on the generated gRPC stub.
  # Each mapping generates a compile-time function clause, so a typo in a
  # caller's method atom produces a clear FunctionClauseError, not a runtime
  # Map.fetch! crash.
  @methods %{
    AppGetOrCreate: :app_get_or_create,
    AppPublish: :app_publish,
    ClassCreate: :class_create,
    ClassGet: :class_get,
    FunctionCallGetDataOut: :function_call_get_data_out,
    ContainerFilesystemExec: :container_filesystem_exec,
    ContainerFilesystemExecGetOutput: :container_filesystem_exec_get_output,
    DictClear: :dict_clear,
    DictContains: :dict_contains,
    DictDelete: :dict_delete,
    DictGet: :dict_get,
    DictGetOrCreate: :dict_get_or_create,
    DictLen: :dict_len,
    DictPop: :dict_pop,
    DictUpdate: :dict_update,
    FunctionCreate: :function_create,
    FunctionGet: :function_get,
    FunctionGetOutputs: :function_get_outputs,
    FunctionMap: :function_map,
    FunctionPrecreate: :function_precreate,
    ProxyGet: :proxy_get,
    ImageGetOrCreate: :image_get_or_create,
    ImageJoinStreaming: :image_join_streaming,
    QueueClear: :queue_clear,
    QueueDelete: :queue_delete,
    QueueGet: :queue_get,
    QueueGetOrCreate: :queue_get_or_create,
    QueueLen: :queue_len,
    QueuePut: :queue_put,
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
    SecretDelete: :secret_delete,
    SecretGetOrCreate: :secret_get_or_create,
    SecretList: :secret_list,
    TaskGetCommandRouterAccess: :task_get_command_router_access,
    VolumeCommit: :volume_commit,
    VolumeDelete: :volume_delete,
    VolumeGetFile2: :volume_get_file2,
    VolumeGetOrCreate: :volume_get_or_create,
    VolumeListFiles2: :volume_list_files2,
    VolumePutFiles2: :volume_put_files2,
    VolumeReload: :volume_reload
  }

  @typedoc """
  PascalCase atom naming one of the RPCs this module dispatches. Matches
  the proto service definition (`SandboxCreate`, `ImageGetOrCreate`, …).
  """
  @type method :: unquote(Enum.reduce(Map.keys(@methods), &{:|, [], [&1, &2]}))

  @doc """
  Call a unary Modal RPC. Returns `{:ok, response_struct}` or
  `{:error, %Modal.Error{}}`.

  `request` is the generated `Modal.Client.<Name>Request` struct for the
  RPC. `timeout` is the wall-clock deadline in milliseconds (default
  30s).

      request = %Modal.Client.SandboxTerminateRequest{sandbox_id: "sb-..."}
      :ok = case Modal.RPC.call(client, :SandboxTerminate, request) do
        {:ok, _} -> :ok
        other -> other
      end

  Emits `[:modal, :rpc, :start | :stop | :exception]` telemetry. Start
  metadata is `%{method: method, kind: :unary}`; stop metadata adds
  `:status` (`:ok | :error`) and — when the error carries one — an
  `:error_kind` atom (e.g. `:grpc`, `:network`, `:timeout`) so
  dashboards can group error rates by category without pattern-matching
  the body.
  """
  @spec call(GenServer.server(), method(), struct(), timeout()) ::
          {:ok, struct()} | {:error, Modal.Error.t()}
  def call(client, method, request, timeout \\ 30_000) do
    call_with_retry(client, method, request, timeout, 0)
  end

  @doc """
  Like `call/4` but skips client-level retry. Use for poll-style
  RPCs where transient codes (DEADLINE_EXCEEDED in particular)
  carry domain meaning — e.g. `SandboxWait` and `FunctionGetOutputs`
  use DEADLINE_EXCEEDED to signal "still running," and retrying
  silently inflates the apparent latency.

  Same telemetry, same return shape; the difference is exactly one
  attempt instead of up to 4.
  """
  @spec call_no_retry(GenServer.server(), method(), struct(), timeout()) ::
          {:ok, struct()} | {:error, Modal.Error.t()}
  def call_no_retry(client, method, request, timeout \\ 30_000) do
    :telemetry.span(
      [:modal, :rpc],
      %{method: method, kind: :unary, attempt: 0, retry: false},
      fn ->
        result = client_impl().rpc(client, stub_method(method), request, timeout)
        {result, stop_metadata(method, :unary, result)}
      end
    )
  end

  # Transient gRPC failures (DEADLINE_EXCEEDED / RESOURCE_EXHAUSTED /
  # ABORTED / UNAVAILABLE, plus network/open-failed) get retried with
  # exponential backoff + jitter, up to @max_retry_attempts times.
  # Each attempt emits its own telemetry span (with `:attempt` in
  # metadata) so dashboards see retry storms as distinct events.
  #
  # Idempotency: Modal's API generally returns transient codes only
  # when the request DIDN'T reach the server (transport drop, server
  # overloaded before it could dispatch). Non-transient codes
  # (INVALID_ARGUMENT, FAILED_PRECONDITION, NOT_FOUND, ...) are
  # never retried — they're definitive answers from the server.
  @max_retry_attempts 3

  defp call_with_retry(client, method, request, timeout, attempt) do
    result =
      :telemetry.span(
        [:modal, :rpc],
        %{method: method, kind: :unary, attempt: attempt},
        fn ->
          result = client_impl().rpc(client, stub_method(method), request, timeout)
          # Include :attempt in stop metadata too — :telemetry doesn't
          # auto-merge start metadata into stop, so dashboards keying off
          # :attempt would only see it on :start otherwise.
          stop = stop_metadata(method, :unary, result) |> Map.put(:attempt, attempt)
          {result, stop}
        end
      )

    maybe_retry(result, client, method, request, timeout, attempt)
  end

  defp maybe_retry({:ok, _} = ok, _client, _method, _request, _timeout, _attempt), do: ok

  defp maybe_retry(
         {:error, %Modal.Error{} = err} = error,
         client,
         method,
         request,
         timeout,
         attempt
       ) do
    if attempt < @max_retry_attempts and Modal.Error.transient?(err) do
      delay = Modal.Backoff.delay(attempt, retry_base_ms(), 30_000)
      Process.sleep(delay)
      call_with_retry(client, method, request, timeout, attempt + 1)
    else
      error
    end
  end

  defp maybe_retry(error, _, _, _, _, _), do: error

  defp retry_base_ms, do: Application.get_env(:modal, :rpc_retry_base_ms, 1_000)

  @doc """
  Call a server-streaming Modal RPC, collecting every response into a list.

  Use only when the stream is bounded and small enough to fit in
  memory (e.g. `:SandboxGetLogs` for a finished sandbox). Use
  `stream_reduce/6` for unbounded or large streams to avoid buffering
  every response.

  Emits `[:modal, :rpc, :*]` telemetry with `kind: :stream`.
  """
  @spec stream(GenServer.server(), method(), struct(), timeout()) ::
          {:ok, [struct()]} | {:error, Modal.Error.t()}
  def stream(client, method, request, timeout \\ 60_000) do
    :telemetry.span([:modal, :rpc], %{method: method, kind: :stream}, fn ->
      result = client_impl().stream_rpc(client, stub_method(method), request, timeout)
      {result, stop_metadata(method, :stream, result)}
    end)
  end

  @doc """
  Call a server-streaming Modal RPC, folding each response into an
  accumulator with a `{:cont, acc} | {:halt, acc}` reducer.

  Used internally by `Modal.Image.get_or_create/3` to consume a
  long-running image-build stream without buffering every log line.
  The reducer is invoked once per response; return `{:halt, acc}` to
  short-circuit and close the stream.

  Emits `[:modal, :rpc, :*]` telemetry with `kind: :stream_reduce`.
  """
  @spec stream_reduce(GenServer.server(), method(), struct(), acc, reducer, timeout()) ::
          {:ok, acc} | {:error, Modal.Error.t()}
        when acc: term(), reducer: (struct(), acc -> {:cont, acc} | {:halt, acc})
  def stream_reduce(client, method, request, acc, reducer, timeout \\ :infinity) do
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

      {result, stop_metadata(method, :stream_reduce, result)}
    end)
  end

  # Build the `:stop` event metadata for an RPC dispatch. The base
  # `%{method, kind}` is preserved (existing handlers continue to
  # work); `:status`, `:error_kind`, and `:code` are additive so a
  # partial-match handler doesn't crash on the new keys. Symmetric
  # with `Modal.ContainerProcess`'s worker-channel stop metadata so a
  # single handler can subscribe to both event families with the same
  # bucketing logic.
  defp stop_metadata(method, kind, result) do
    base = %{method: method, kind: kind}

    case result do
      {:ok, _} ->
        Map.put(base, :status, :ok)

      {:error, %Modal.Error{kind: error_kind, code: code}} ->
        base
        |> Map.put(:status, :error)
        |> Map.put(:error_kind, error_kind)
        |> Map.put(:code, code)

      {:error, _other} ->
        # Non-Modal.Error errors leak through from internal paths
        # (e.g. raw GRPC.RPCError). Tag them :error but with no
        # :error_kind so dashboards still see the failure.
        Map.put(base, :status, :error)
    end
  end

  @doc false
  @spec lookup_task_id(GenServer.server(), String.t()) :: {:ok, String.t()} | :miss
  def lookup_task_id(client, sandbox_id) do
    client_impl().lookup_task_id(client, sandbox_id)
  end

  @doc false
  @spec cache_task_id(GenServer.server(), String.t(), String.t()) :: :ok
  def cache_task_id(client, sandbox_id, task_id) do
    client_impl().cache_task_id(client, sandbox_id, task_id)
  end

  # Default is fixed at compile-time (so config changes trigger
  # recompile warnings like compile_env always did). But the actual
  # lookup is `get_env` so tests can switch impls at runtime —
  # essential for contract tests that want the real client while
  # the rest of the test env still defaults to Modal.Client.Mock.
  @default_client_impl Application.compile_env(:modal, :client_impl, Modal.Client)
  defp client_impl, do: Application.get_env(:modal, :client_impl, @default_client_impl)

  for {domain, stub} <- @methods do
    defp stub_method(unquote(domain)), do: unquote(stub)
  end
end
