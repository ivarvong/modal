defmodule Modal.RPCTest do
  @moduledoc """
  Tests for the `Modal.RPC` escape-hatch surface — specifically the
  telemetry contract.

  Every `Modal.RPC.{call, stream, stream_reduce}` invocation emits the
  `[:modal, :rpc, :start | :stop | :exception]` triplet. The `:stop`
  event metadata is what downstream dashboards key off, so it's worth
  asserting the shape explicitly.
  """
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  setup do
    # Each test attaches a single handler that forwards every relevant
    # event to the test process. Mox's `verify_on_exit!` runs in the
    # test process, so we don't have to worry about cross-test handler
    # bleed — but we still detach on exit for hygiene.
    #
    # The handler is a named module function (`__MODULE__.forward/4`)
    # rather than an anonymous closure — `:telemetry` logs a perf
    # warning every time a local-capture handler is attached, and the
    # test suite output gets unreadable otherwise.
    handler_id = "rpc-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:modal, :rpc, :start],
        [:modal, :rpc, :stop],
        [:modal, :rpc, :exception]
      ],
      &__MODULE__.forward/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  # Telemetry handler — must be a named module function (see setup/0).
  @doc false
  def forward(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  describe ":stop event metadata" do
    test "tags :status :ok on successful unary RPC" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_list, _, _ ->
        {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
      end)

      assert {:ok, _} =
               Modal.RPC.call(:mock, :SandboxList, %Modal.Client.SandboxListRequest{})

      assert_received {:telemetry, [:modal, :rpc, :start], _, %{method: :SandboxList}}
      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}

      assert meta.method == :SandboxList
      assert meta.kind == :unary
      assert meta.status == :ok
      refute Map.has_key?(meta, :error_kind), "no :error_kind on success"
    end

    test "tags :status :error + :error_kind + :code on a %Modal.Error{} failure" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, _} =
               Modal.RPC.call(:mock, :SandboxCreate, %Modal.Client.SandboxCreateRequest{})

      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}

      assert meta.status == :error
      assert meta.error_kind == :grpc
      # Symmetric with the worker-channel family — a single handler
      # subscribing to both can read :code without a defensive
      # Map.get/3.
      assert meta.code == 7
    end

    test "tags :status :error without :error_kind on raw non-Modal.Error failure" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, _, _ ->
        # Simulates an internal path that hasn't been wrapped yet —
        # exercise the defensive clause so a partial migration doesn't
        # break dashboards.
        {:error, :something_weird}
      end)

      assert {:error, _} =
               Modal.RPC.call(:mock, :SandboxCreate, %Modal.Client.SandboxCreateRequest{})

      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}

      assert meta.status == :error
      refute Map.has_key?(meta, :error_kind)
    end

    test "stream/4 carries :status and :error_kind under :kind :stream" do
      Modal.Client.Mock
      |> expect(:stream_rpc, fn _, :sandbox_get_logs, _, _ ->
        {:error, Modal.Error.network(:closed)}
      end)

      assert {:error, _} =
               Modal.RPC.stream(:mock, :SandboxGetLogs, %Modal.Client.SandboxGetLogsRequest{})

      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}

      assert meta.kind == :stream
      assert meta.status == :error
      assert meta.error_kind == :network
    end

    test "stream/4 returns items in the order the server sent them" do
      # Happy-path bytes-through was previously only covered indirectly
      # via Image.get_or_create/3. A future refactor that returned
      # responses reversed wouldn't be caught until an image-build log
      # printed in the wrong order.
      items = [%{seq: 1}, %{seq: 2}, %{seq: 3}]

      Modal.Client.Mock
      |> expect(:stream_rpc, fn _, :sandbox_get_logs, _, _ ->
        {:ok, items}
      end)

      assert {:ok, ^items} =
               Modal.RPC.stream(:mock, :SandboxGetLogs, %Modal.Client.SandboxGetLogsRequest{})

      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}
      assert meta.status == :ok
      assert meta.kind == :stream
    end

    test "stream_reduce/6 carries :status :ok with :kind :stream_reduce" do
      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _, :image_join_streaming, _, init, _reducer, _ ->
        {:ok, init}
      end)

      assert {:ok, _} =
               Modal.RPC.stream_reduce(
                 :mock,
                 :ImageJoinStreaming,
                 %Modal.Client.ImageJoinStreamingRequest{},
                 :init_acc,
                 fn _resp, acc -> {:cont, acc} end
               )

      assert_received {:telemetry, [:modal, :rpc, :stop], _, meta}

      assert meta.kind == :stream_reduce
      assert meta.status == :ok
    end
  end

  # ── Retry behavior — transient codes → up to 4 attempts ────────

  describe "retry-with-jitter" do
    test "retries on UNAVAILABLE up to 4 total attempts, then propagates" do
      attempts = :counters.new(1, [])

      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_create, _, _ ->
        :counters.add(attempts, 1, 1)
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14}} =
               Modal.RPC.call(:mock, :SandboxCreate, %Modal.Client.SandboxCreateRequest{})

      # 1 initial + 3 retries.
      assert :counters.get(attempts, 1) == 4
    end

    test "retries on DEADLINE_EXCEEDED / RESOURCE_EXHAUSTED / ABORTED" do
      for code <- [4, 8, 10, 14] do
        attempts = :counters.new(1, [])

        Modal.Client.Mock
        |> stub(:rpc, fn _, :sandbox_list, _, _ ->
          :counters.add(attempts, 1, 1)
          {:error, Modal.Error.grpc(code, "transient")}
        end)

        Modal.RPC.call(:mock, :SandboxList, %Modal.Client.SandboxListRequest{})
        assert :counters.get(attempts, 1) == 4, "code #{code} should retry"
      end
    end

    test "does NOT retry on non-transient codes (definitive answers)" do
      for code <- [3, 5, 7, 9, 13, 16] do
        attempts = :counters.new(1, [])

        Modal.Client.Mock
        |> expect(:rpc, fn _, :sandbox_create, _, _ ->
          :counters.add(attempts, 1, 1)
          {:error, Modal.Error.grpc(code, "definitive")}
        end)

        Modal.RPC.call(:mock, :SandboxCreate, %Modal.Client.SandboxCreateRequest{})
        assert :counters.get(attempts, 1) == 1, "code #{code} should NOT retry"
      end
    end

    test "succeeds on the first retry if the server recovers" do
      attempts = :counters.new(1, [])

      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_list, _, _ ->
        n = :counters.get(attempts, 1)
        :counters.add(attempts, 1, 1)

        if n == 0 do
          {:error, Modal.Error.grpc(14, "transient")}
        else
          {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
        end
      end)

      assert {:ok, _} =
               Modal.RPC.call(:mock, :SandboxList, %Modal.Client.SandboxListRequest{})

      # 1 failure + 1 success.
      assert :counters.get(attempts, 1) == 2
    end

    test "call_no_retry/4 fires exactly once even on transient errors" do
      # Used by poll-style RPCs (Sandbox.wait, FunctionGetOutputs)
      # where DEADLINE_EXCEEDED has domain meaning.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_wait, _, _ ->
        {:error, Modal.Error.grpc(4, "deadline exceeded — still running")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 4}} =
               Modal.RPC.call_no_retry(:mock, :SandboxWait, %Modal.Client.SandboxWaitRequest{})
    end

    test "each retry attempt emits its own telemetry span (visible retry storms)" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      Modal.RPC.call(:mock, :SandboxCreate, %Modal.Client.SandboxCreateRequest{})

      # Each attempt is its own telemetry event — dashboards can see
      # a retry storm as 4 separate spans rather than one long call.
      assert_received {:telemetry, [:modal, :rpc, :stop], _, %{attempt: 0}}
      assert_received {:telemetry, [:modal, :rpc, :stop], _, %{attempt: 1}}
      assert_received {:telemetry, [:modal, :rpc, :stop], _, %{attempt: 2}}
      assert_received {:telemetry, [:modal, :rpc, :stop], _, %{attempt: 3}}
    end
  end

  describe "dispatch table" do
    # Pin every PascalCase ↔ snake_case mapping. A typo in `@methods`
    # (e.g. `SecretGetOrCreate: :secret_create`) used to compile cleanly
    # and surface only the first time that specific RPC fired. This
    # parameterised test makes the dispatch table fail at test
    # compile/load if any pairing drifts.
    #
    # Cross-check the canonical PascalCase ↔ snake_case algorithm. We
    # don't import `@methods` directly — that would tautologically
    # compare the table to itself; instead we recompute the expected
    # snake_case from the documented atom and assert dispatch.
    @canonical_methods [
      AppGetOrCreate: :app_get_or_create,
      AppList: :app_list,
      AppPublish: :app_publish,
      AppStop: :app_stop,
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
    ]

    for {pascal, expected_snake} <- @canonical_methods do
      test "#{pascal} maps to :#{expected_snake}" do
        Modal.Client.Mock
        |> expect(:rpc, fn _, stub_method, _req, _timeout ->
          assert stub_method == unquote(expected_snake),
                 "expected #{inspect(unquote(pascal))} to dispatch as " <>
                   "#{inspect(unquote(expected_snake))}, got #{inspect(stub_method)}"

          {:ok, %{}}
        end)

        Modal.RPC.call(:mock, unquote(pascal), %{})
      end
    end

    test "an unknown method atom raises FunctionClauseError at the call site" do
      # Compile-time-shaped failure mode: a typo'd atom hits the
      # `stub_method/1` defp clauses and produces an immediate
      # FunctionClauseError instead of a runtime Map.fetch! deep in
      # the generated stub. Caller debugging hint, not dispatch logic.
      assert_raise FunctionClauseError, fn ->
        Modal.RPC.call(:mock, :TotallyMadeUpAtom, %{})
      end
    end
  end
end
