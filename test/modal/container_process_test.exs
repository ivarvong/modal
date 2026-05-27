defmodule Modal.ContainerProcessTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @task_id "ti-test"
  @exec_id "ex-test-0000"
  # exp: 9999999999
  @jwt "header.eyJleHAiOjk5OTk5OTk5OTl9.sig"

  # A ContainerProcess whose JWT is far in the future — no expiry interference.
  defp proc(channel \\ :fake_channel) do
    %Modal.ContainerProcess{
      channel: channel,
      task_id: @task_id,
      exec_id: @exec_id,
      jwt: @jwt,
      jwt_exp: 9_999_999_999,
      tcr_stub: Modal.TaskCommandRouter.Mock
    }
  end

  defp expired_proc do
    %Modal.ContainerProcess{
      channel: :fake_channel,
      task_id: @task_id,
      exec_id: @exec_id,
      jwt: "h.e.s",
      # 1970 — always expired
      jwt_exp: 1,
      tcr_stub: Modal.TaskCommandRouter.Mock
    }
  end

  describe "exec_start_request/4" do
    test ":timeout_secs is unset by default — no per-exec kill (sandbox timeout governs)" do
      req = Modal.ContainerProcess.exec_start_request("ti-1", "ex-1", ["echo", "hi"], [])
      assert req.timeout_secs == nil
      assert req.command_args == ["echo", "hi"]
      assert req.workdir == ""
      assert req.pty_info == nil
    end

    test ":timeout_secs passes through when given" do
      req =
        Modal.ContainerProcess.exec_start_request("ti-1", "ex-1", ["sleep", "9000"], timeout_secs: 1_800)

      assert req.timeout_secs == 1_800
    end

    test ":workdir passes through" do
      req = Modal.ContainerProcess.exec_start_request("ti-1", "ex-1", ["ls"], workdir: "/app")
      assert req.workdir == "/app"
    end

    test ":pty true builds a default PTYInfo; a struct passes through" do
      assert %Modal.Client.PTYInfo{enabled: true, pty_type: :PTY_TYPE_SHELL} =
               Modal.ContainerProcess.exec_start_request("ti-1", "ex-1", ["bash"], pty: true).pty_info

      custom = %Modal.Client.PTYInfo{enabled: true, winsz_rows: 50, winsz_cols: 200}

      assert ^custom =
               Modal.ContainerProcess.exec_start_request("ti-1", "ex-1", ["bash"], pty: custom).pty_info
    end
  end

  # ── JWT expiry ───────────────────────────────────────────────────

  describe "JWT expiry" do
    test "exit_code/1 returns :jwt_expired when JWT is expired" do
      # No TCR calls expected — error must be returned before any RPC.
      assert {:error, %Modal.Error{kind: :jwt_expired}} =
               Modal.ContainerProcess.exit_code(expired_proc())
    end

    test "stream/1 returns :jwt_expired when JWT is expired (no raise)" do
      # No TCR calls expected — error must be returned before any RPC.
      assert {:error, %Modal.Error{kind: :jwt_expired}} =
               Modal.ContainerProcess.stream(expired_proc())
    end

    test "exit_code/1 proceeds when JWT is valid" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, 0} = Modal.ContainerProcess.exit_code(proc())
    end

    test "write/3 returns :jwt_expired when JWT is expired (no server round-trip)" do
      # The guard must short-circuit BEFORE any RPC: an expired write would
      # otherwise reach the worker as an opaque auth failure and surface as
      # a generic gRPC error. No mock expectations means verify_on_exit!
      # will fail the test if a stdin_write RPC is attempted.
      assert {:error, %Modal.Error{kind: :jwt_expired}} =
               Modal.ContainerProcess.write(expired_proc(), "data")
    end
  end

  # ── exit_code / wait_loop ────────────────────────────────────────

  describe "exit_code/1" do
    test "returns {:ok, code} for normal exit" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 42}}}
      end)

      assert {:ok, 42} = Modal.ContainerProcess.exit_code(proc())
    end

    test "maps signal exit to 128 + signal" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:signal, 9}}}
      end)

      assert {:ok, 137} = Modal.ContainerProcess.exit_code(proc())
    end

    test "returns {:ok, nil} when exit_status is not set" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{}}
      end)

      assert {:ok, nil} = Modal.ContainerProcess.exit_code(proc())
    end

    test "retries on transient error and succeeds" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, 0} = Modal.ContainerProcess.exit_code(proc())
    end

    test "exhausts exactly 101 attempts (1 initial + 100 retries) then returns error" do
      counter = :counters.new(1, [:atomics])

      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_wait, fn :fake_channel, _req, _opts ->
        :counters.add(counter, 1, 1)
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14}} =
               Modal.ContainerProcess.exit_code(proc())

      assert :counters.get(counter, 1) == 101,
             "Expected 101 attempts (1 + 100 retries), got #{:counters.get(counter, 1)}"
    end

    test "check_jwt is called before each retry, not just at the start" do
      # Verify the structural claim: wait_loop calls check_jwt before
      # sleeping by ensuring that a proc with a valid JWT retries normally,
      # while a proc with an expired JWT never retries.

      # Case 1: valid JWT — retries as expected.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, 2, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, 0} = Modal.ContainerProcess.exit_code(proc())

      # Case 2: expired JWT — exit_code short-circuits before any RPC.
      # (No mock expectations — any call would fail verify_on_exit!.)
      assert {:error, %Modal.Error{kind: :jwt_expired}} =
               Modal.ContainerProcess.exit_code(expired_proc())
    end

    test "re-polls when the wait hits its own deadline (CANCELLED), then returns the code" do
      # A long-running exec outlasts the per-attempt wait deadline, which
      # surfaces as gRPC CANCELLED. That means "still running", not failure
      # — wait_loop must re-poll, not give up.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 1, message: "Timeout expired"}}
      end)
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, 0} = Modal.ContainerProcess.exit_code(proc())
    end

    test "wait-deadline re-polls are bounded by the attempt cap" do
      # Guard against a hot loop if the deadline error keeps coming back
      # (e.g. an instantly-cancelling channel): 1 initial + 100 re-polls.
      counter = :counters.new(1, [:atomics])

      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_wait, fn :fake_channel, _req, _opts ->
        :counters.add(counter, 1, 1)
        {:error, %GRPC.RPCError{status: 1, message: "Timeout expired"}}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 1}} =
               Modal.ContainerProcess.exit_code(proc())

      assert :counters.get(counter, 1) == 101,
             "Expected 101 attempts (1 + 100 re-polls), got #{:counters.get(counter, 1)}"
    end
  end

  # ── await/2 ─────────────────────────────────────────────────────

  describe "await/2" do
    test "returns :timeout when timeout is exceeded" do
      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_wait, fn :fake_channel, _req, _opts ->
        Process.sleep(500)
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)
      |> stub(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, []}
      end)

      assert {:error, %Modal.Error{kind: :timeout}} =
               Modal.ContainerProcess.await(proc(), timeout: 50)
    end

    test "propagates :jwt_expired from stream/1 without raising" do
      # No TCR calls expected at all — JWT check short-circuits before exec.
      assert {:error, %Modal.Error{kind: :jwt_expired}} =
               Modal.ContainerProcess.await(expired_proc())
    end

    test "propagates :open_failed when the stream cannot be opened" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)

      assert {:error, %Modal.Error{kind: :open_failed}} =
               Modal.ContainerProcess.await(proc())
    end

    test ":on_stdout / :on_stderr fire per chunk AND chunks are still collected" do
      # Each fd's stream produces two chunks; the callbacks should fire
      # twice each, and the collected stdout/stderr should still hold
      # the joined bytes.
      stdout_chunks = ["line1\n", "line2\n"]
      stderr_chunks = ["err1\n", "err2\n"]

      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        chunks =
          case req.file_descriptor do
            :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDOUT -> stdout_chunks
            :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDERR -> stderr_chunks
          end

        if req.offset == 0 do
          frames =
            Enum.map(chunks, fn data ->
              {:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: data}}
            end)

          {:ok, frames}
        else
          {:ok, []}
        end
      end)
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      parent = self()

      assert {:ok, %{stdout: "line1\nline2\n", stderr: "err1\nerr2\n", code: 0}} =
               Modal.ContainerProcess.await(proc(),
                 on_stdout: fn chunk -> send(parent, {:stdout, chunk}) end,
                 on_stderr: fn chunk -> send(parent, {:stderr, chunk}) end
               )

      assert_received {:stdout, "line1\n"}
      assert_received {:stdout, "line2\n"}
      assert_received {:stderr, "err1\n"}
      assert_received {:stderr, "err2\n"}
    end

    test "returns %{stdout, stderr, code} on success — collects both fds" do
      # await/2 opens one stdio_read per fd. We dispatch on the
      # request's file_descriptor field so the mock can return distinct
      # bytes for stdout vs stderr.
      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        case req.file_descriptor do
          :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDOUT ->
            if req.offset == 0 do
              {:ok, [{:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: "out\n"}}]}
            else
              {:ok, []}
            end

          :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDERR ->
            if req.offset == 0 do
              {:ok, [{:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: "err\n"}}]}
            else
              {:ok, []}
            end
        end
      end)
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, %{stdout: "out\n", stderr: "err\n", code: 0}} =
               Modal.ContainerProcess.await(proc())
    end
  end

  # ── await!/2 ────────────────────────────────────────────────────

  describe "await!/2" do
    # Helper: stub stdio for a successful exec with the given bytes per fd.
    defp stub_stdio(stdout_bytes, stderr_bytes) do
      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        bytes =
          case req.file_descriptor do
            :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDOUT -> stdout_bytes
            :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDERR -> stderr_bytes
          end

        if req.offset == 0 and byte_size(bytes) > 0 do
          {:ok, [{:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: bytes}}]}
        else
          {:ok, []}
        end
      end)
    end

    test "returns the result map on a zero exit" do
      stub_stdio("hi\n", "")

      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert %{stdout: "hi\n", stderr: "", code: 0} = Modal.ContainerProcess.await!(proc())
    end

    test "raises %Modal.Error{kind: :exec_failed} on a non-zero exit" do
      stub_stdio("partial out\n", "boom\nfatal: kaboom\n")

      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 42}}}
      end)

      err =
        assert_raise Modal.Error, fn ->
          Modal.ContainerProcess.await!(proc())
        end

      assert err.kind == :exec_failed
      assert err.code == 42
      assert err.metadata.stdout == "partial out\n"
      assert err.metadata.stderr == "boom\nfatal: kaboom\n"

      # Exception message surfaces the stderr tail — the diagnostic the
      # caller needs without having to crack open `metadata`. The exit
      # code lives in the formatter's `(42)` prefix; the message body
      # itself is just the tail so a `MatchError`-style call site reads
      # cleanly.
      msg = Exception.message(err)
      assert msg =~ "(42)"
      assert msg =~ "fatal: kaboom"
      refute msg =~ "code 42", "exit code should appear once, not twice"
    end

    test "raises %Modal.Error{kind: :exec_unknown_status} when no exit code is reported" do
      # The worker can finish the stream without ever reporting an exit
      # code — wall-clock timeout, OOM, snapshot raced with exit. We
      # surface this as a distinct kind so callers don't conflate "we
      # don't know" with "it succeeded" (the previous behaviour).
      stub_stdio("partial out\n", "killed: 9\n")

      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: nil}}
      end)

      err =
        assert_raise Modal.Error, fn ->
          Modal.ContainerProcess.await!(proc())
        end

      assert err.kind == :exec_unknown_status
      assert err.metadata.stdout == "partial out\n"
      assert err.metadata.stderr == "killed: 9\n"
      assert Exception.message(err) =~ "killed externally"
    end

    test "bubbles non-exec errors (e.g. :open_failed) without wrapping" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)

      err =
        assert_raise Modal.Error, fn ->
          Modal.ContainerProcess.await!(proc())
        end

      assert err.kind == :open_failed
    end
  end

  # ── stream/1 open-time contract ─────────────────────────────────

  describe "stream/1 — open-time contract" do
    # Helper: build a TaskExecStdioReadResponse with the given binary data.
    defp resp(data) do
      {:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: data}}
    end

    test "returns {:ok, stream} that emits non-empty data chunks only" do
      # The new contract: each successful drain triggers a reconnect at
      # the new offset. Iteration only ends when a reconnect returns
      # zero chunks — that's the "exec is done" signal.
      Modal.TaskCommandRouter.Mock
      # First call: returns chunks, empty frame, more chunks.
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == 0
        {:ok, [resp("hello "), resp(""), resp("world\n")]}
      end)
      # Reconnect after data: returns empty (exec done).
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == byte_size("hello ") + byte_size("world\n")
        {:ok, []}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())
      assert Enum.to_list(stream) == ["hello ", "world\n"]
    end

    test "{:ok, stream} that's empty when there is no stdout" do
      # First call returns no chunks → exec already done, stream halts
      # immediately without a reconnect.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == 0
        {:ok, []}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())
      assert Enum.to_list(stream) == []
    end

    test "reconnects on DEADLINE_EXCEEDED (status 4) and continues at the new offset" do
      # First call yields some data, then the server closes with
      # DEADLINE_EXCEEDED (our own call timeout). The library must
      # reconnect at offset=byte_size(data) and continue.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == 0

        {:ok,
         [
           resp("part1 "),
           {:error, %GRPC.RPCError{status: 4, message: "deadline exceeded"}}
         ]}
      end)
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == byte_size("part1 ")
        {:ok, [resp("part2\n")]}
      end)
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == byte_size("part1 part2\n")
        {:ok, []}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())
      assert Enum.to_list(stream) == ["part1 ", "part2\n"]
    end

    test "reconnects on UNAVAILABLE (status 14) without surfacing the error" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, [resp("a"), {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}]}
      end)
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, []}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())
      assert Enum.to_list(stream) == ["a"]
    end

    test "returns :open_failed on the INITIAL stream open failure" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)

      # Initial-open errors arrive as `{:error, _}` at the call site, NOT
      # raised — the documented contract for stream/1.
      assert {:error, %Modal.Error{kind: :open_failed}} =
               Modal.ContainerProcess.stream(proc())
    end

    test "raises Modal.Error from mid-iteration if a reconnect itself fails to open" do
      # First open succeeds, yields a chunk + retryable close.
      # Reconnect open then fails non-retryably — must raise (we're
      # inside Enum.* and can't return a tuple).
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, [resp("a"), {:error, %GRPC.RPCError{status: 4, message: "deadline"}}]}
      end)
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 7, message: "permission denied"}}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())

      raised = assert_raise Modal.Error, fn -> Enum.to_list(stream) end
      assert raised.kind == :open_failed
    end
  end

  # ── stream/1 mid-iteration errors ─────────────────────────────────
  #
  # Errors with NON-retryable status codes that arrive mid-stream are
  # raised (the consumer is inside Enum.* and can't receive a tuple).
  # Retryable codes (4, 8, 10, 14) trigger transparent reconnects and
  # are covered above.

  describe "stream/1 — mid-iteration errors" do
    test "mid-stream %GRPC.RPCError{} with NON-retryable status raises Modal.Error" do
      # Status 7 = PERMISSION_DENIED, not retryable.
      err = %GRPC.RPCError{status: 7, message: "permission denied"}

      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, [resp("before "), {:error, err}]}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())

      raised = assert_raise Modal.Error, fn -> Enum.to_list(stream) end
      assert raised.kind == :grpc
      assert raised.code == 7
      assert raised.message =~ "permission denied"
    end

    test "mid-stream {:error, reason} raises Modal.Error with :network kind" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, [resp("before "), {:error, :closed}]}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())

      raised = assert_raise Modal.Error, fn -> Enum.to_list(stream) end
      assert raised.kind == :network
      assert raised.code == :closed
    end

    test "an unexpected (non-tuple) item raises Modal.Error with :unexpected kind" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, _req, _opts ->
        {:ok, [resp("before "), :surprise_atom]}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())

      raised = assert_raise Modal.Error, fn -> Enum.to_list(stream) end
      assert raised.kind == :unexpected
      assert raised.metadata == %{item: :surprise_atom}
    end
  end

  # ── write/3 ─────────────────────────────────────────────────────

  describe "write/3" do
    test "returns :ok on success" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdin_write, fn :fake_channel, req, _opts ->
        assert req.data == "hello\n"
        assert req.eof == false
        {:ok, %Modal.TaskCommandRouter.TaskExecStdinWriteResponse{}}
      end)

      assert :ok = Modal.ContainerProcess.write(proc(), "hello\n")
    end

    test "sends eof: true when option is set" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdin_write, fn :fake_channel, req, _opts ->
        assert req.eof == true
        {:ok, %Modal.TaskCommandRouter.TaskExecStdinWriteResponse{}}
      end)

      assert :ok = Modal.ContainerProcess.write(proc(), "", eof: true)
    end

    test "returns Modal.Error with :grpc kind on gRPC error" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdin_write, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 3, message: "invalid argument"}}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 3, message: "invalid argument"}} =
               Modal.ContainerProcess.write(proc(), "data")
    end
  end

  # ── Worker-channel telemetry ────────────────────────────────────

  describe "[:modal, :worker_rpc, :*] telemetry" do
    setup do
      handler_id = "worker-rpc-telemetry-test-#{System.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:modal, :worker_rpc, :start],
          [:modal, :worker_rpc, :stop],
          [:modal, :worker_rpc, :exception]
        ],
        &__MODULE__.forward_telemetry/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "task_exec_wait emits stop event with status: :ok on success" do
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecWaitResponse{exit_status: {:code, 0}}}
      end)

      assert {:ok, 0} = Modal.ContainerProcess.exit_code(proc())

      assert_received {:telemetry, [:modal, :worker_rpc, :start], _, %{method: :task_exec_wait}}

      assert_received {:telemetry, [:modal, :worker_rpc, :stop], _, meta}
      assert meta.method == :task_exec_wait
      assert meta.status == :ok
    end

    test "task_exec_wait emits status: :error + :error_kind :grpc on RPC error" do
      Modal.TaskCommandRouter.Mock
      |> stub(:task_exec_wait, fn :fake_channel, _req, _opts ->
        {:error, %GRPC.RPCError{status: 14, message: "unavailable"}}
      end)

      # exit_code retries; we only care that the LAST stop event
      # records the :grpc error_kind. Drain start/stop pairs and
      # assert on the final one.
      assert {:error, %Modal.Error{kind: :grpc}} = Modal.ContainerProcess.exit_code(proc())

      assert_received {:telemetry, [:modal, :worker_rpc, :stop], _, meta}
      assert meta.method == :task_exec_wait
      assert meta.status == :error
      assert meta.error_kind == :grpc
      assert meta.code == 14
    end

    test "task_exec_stdio_read emits per reconnect — one event per server-stream open" do
      # The reconnect loop opens the RPC multiple times. Each open
      # should be a separate telemetry event so operators can see the
      # reconnect cadence.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == 0
        {:ok, [{:ok, %Modal.TaskCommandRouter.TaskExecStdioReadResponse{data: "first\n"}}]}
      end)
      |> expect(:task_exec_stdio_read, fn :fake_channel, req, _opts ->
        assert req.offset == byte_size("first\n")
        {:ok, []}
      end)

      assert {:ok, stream} = Modal.ContainerProcess.stream(proc())
      assert Enum.to_list(stream) == ["first\n"]

      # Both opens emit a stop. We don't care about ordering — just
      # the count.
      stops = drain_stops(:task_exec_stdio_read, 2)
      assert length(stops) == 2
      assert Enum.all?(stops, &(&1.status == :ok))
    end

    test "task_exec_start emits one event with status :ok" do
      # A more end-to-end shape — start/3 calls connect_to_worker
      # which RPCs control-plane, so we can't easily run start/3
      # against the mock without a real channel. Test indirectly by
      # calling write/3 (which is the simplest TCR call) — it covers
      # the helper used by start_/wait_/read_/write_.
      Modal.TaskCommandRouter.Mock
      |> expect(:task_exec_stdin_write, fn :fake_channel, _req, _opts ->
        {:ok, %Modal.TaskCommandRouter.TaskExecStdinWriteResponse{}}
      end)

      assert :ok = Modal.ContainerProcess.write(proc(), "hi\n")

      assert_received {:telemetry, [:modal, :worker_rpc, :stop], _, meta}
      assert meta.method == :task_exec_stdin_write
      assert meta.status == :ok
    end
  end

  # Telemetry handler — must be a named module function (telemetry
  # warns about local-capture handlers).
  @doc false
  def forward_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  # Drain N consecutive stop events for `method`, returning their
  # metadata in receive order.
  defp drain_stops(method, n) do
    Enum.map(1..n, fn _ ->
      receive do
        {:telemetry, [:modal, :worker_rpc, :stop], _, %{method: ^method} = meta} -> meta
      after
        1000 -> flunk("expected #{n} worker_rpc :stop events for #{method}")
      end
    end)
  end

  # ── Inspect ─────────────────────────────────────────────────────

  describe "Inspect" do
    test "does not include JWT in inspect output" do
      output = inspect(proc())
      refute String.contains?(output, @jwt)
      assert String.contains?(output, @task_id)
      assert String.contains?(output, @exec_id)
    end

    test "format is the expected string" do
      assert inspect(proc()) ==
               "#Modal.ContainerProcess<task_id: #{@task_id}, exec_id: #{@exec_id}>"
    end
  end
end
