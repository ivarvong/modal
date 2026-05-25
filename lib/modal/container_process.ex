defmodule Modal.ContainerProcess do
  @moduledoc """
  A running command in a Modal Sandbox.

  Opens a direct gRPC channel to the worker node (separate from the control-plane
  channel in `Modal.Client`) and multiplexes stdout-streaming, stdin-writing,
  and exit-code polling over HTTP/2.

  ## Streaming stdout

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      {:ok, stream} = Modal.ContainerProcess.stream(proc)
      stream |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)

  ## Collect all output at once

      {:ok, result} = Modal.ContainerProcess.await(proc)
      result.stdout  #=> "..."
      result.stderr  #=> "..."
      result.code    #=> 0

      # Raise on non-zero exit; bubbles `%Modal.Error{kind: :exec_failed}`
      # with stdout/stderr in `:metadata`.
      result = Modal.ContainerProcess.await!(proc)

  Always close when done to release the worker gRPC channel:

      Modal.ContainerProcess.close(proc)

  If the calling process crashes, the channel is cleaned up automatically.

  ## JWT lifetime

  The JWT used to authenticate with the worker is obtained at exec time and
  stored on the struct. It has a finite lifetime (typically several hours).
  Long-running processes will log a warning when the JWT is about to expire.
  If the JWT expires mid-execution, calls will fail with
  `{:error, %Modal.Error{kind: :jwt_expired}}`. Create a new `ContainerProcess`
  via `Modal.Sandbox.exec/3` to obtain a fresh JWT.
  """

  require Logger

  alias Modal.TaskCommandRouter, as: TCR

  @wait_attempt_timeout 60_000
  # Warn when JWT has less than this many seconds remaining.
  @jwt_expiry_warning_secs 60
  @default_tcr_stub Modal.TaskCommandRouter.TaskCommandRouter.Stub

  defstruct [:channel, :task_id, :exec_id, :jwt, :jwt_exp, :tcr_stub, :monitor_pid]

  @type t :: %__MODULE__{
          channel: GRPC.Channel.t(),
          task_id: String.t(),
          exec_id: String.t(),
          jwt: String.t(),
          jwt_exp: non_neg_integer(),
          tcr_stub: module() | nil,
          monitor_pid: pid() | nil
        }

  @doc false
  @spec start(Modal.Sandbox.t(), [String.t()], keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def start(%Modal.Sandbox{} = sandbox, command, opts \\ []) do
    caller = self()

    with {:ok, task_id} <- Modal.Sandbox.get_task_id(sandbox),
         {:ok, channel, jwt} <- connect_to_worker(sandbox.client, task_id) do
      exec_id =
        "ex-#{System.unique_integer([:positive, :monotonic])}-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"

      tcr = Keyword.get(opts, :tcr_stub)

      pty_info =
        case Keyword.get(opts, :pty, false) do
          false ->
            nil

          true ->
            %Modal.Client.PTYInfo{
              enabled: true,
              winsz_rows: 24,
              winsz_cols: 80,
              env_term: "xterm-256color",
              pty_type: :PTY_TYPE_SHELL,
              no_terminate_on_idle_stdin: true
            }

          %Modal.Client.PTYInfo{} = info ->
            info
        end

      request = %TCR.TaskExecStartRequest{
        task_id: task_id,
        exec_id: exec_id,
        command_args: command,
        stdout_config: :TASK_EXEC_STDOUT_CONFIG_PIPE,
        stderr_config: :TASK_EXEC_STDERR_CONFIG_PIPE,
        timeout_secs: Keyword.get(opts, :timeout_secs, 300),
        workdir: Keyword.get(opts, :workdir, ""),
        pty_info: pty_info
      }

      stub = tcr || @default_tcr_stub

      result =
        span(:task_exec_start, fn ->
          stub.task_exec_start(channel, request, metadata: auth(jwt))
        end)

      finalize_start(result, caller, channel, task_id, exec_id, jwt, tcr)
    end
  end

  defp finalize_start({:ok, _}, caller, channel, task_id, exec_id, jwt, tcr) do
    # Spawn a monitor that cleans up the gRPC channel if the caller dies.
    monitor_pid = start_channel_monitor(channel, caller)

    proc = %__MODULE__{
      channel: channel,
      task_id: task_id,
      exec_id: exec_id,
      jwt: jwt,
      jwt_exp: Modal.JWT.parse_exp(jwt),
      tcr_stub: tcr,
      monitor_pid: monitor_pid
    }

    {:ok, proc}
  end

  defp finalize_start({:error, %GRPC.RPCError{} = err}, _caller, channel, _, _, _, _) do
    GRPC.Stub.disconnect(channel)
    {:error, Modal.Error.exec_start_failed(err.message)}
  end

  # Per-call timeout for one gRPC stdio_read invocation. The Modal
  # worker only flushes pending stdout AND closes the stream cleanly on
  # exec-exit when the call has a finite deadline; with `:infinity` the
  # server holds the connection open waiting for further input, even
  # after the exec is done — output stays buffered and never reaches
  # the client.
  #
  # Empirically against the live API: a 5s call timeout yields prompt
  # flushes (sub-second for short execs that exit immediately) and
  # tight reconnect cadence (one extra RPC per 5s of long-running
  # output). Larger timeouts (30s+) reproducibly cause the server to
  # hold the stream open for the full deadline before flushing, which
  # makes interactive output feel laggy. Smaller timeouts (1s) work
  # but produce excessive reconnect chatter.
  @stdio_read_call_timeout_ms 5_000

  @doc """
  Returns `{:ok, stream}` where `stream` is a lazy `Stream` of binary
  chunks from the requested file descriptor, or `{:error, %Modal.Error{}}`
  if the stream couldn't be opened.

  ## Options

    * `:fd` — which file descriptor to read from: `:stdout` (default) or
      `:stderr`. The two streams are independent — to collect both at once
      open one of each (or use `await/2`, which does this for you).

  ## Errors at open time (returned as `{:error, %Modal.Error{}}`)

    * `kind: :jwt_expired` — the worker JWT for this process has expired;
      call `Modal.Sandbox.exec/3` again to obtain a fresh `ContainerProcess`.
    * `kind: :open_failed` — the underlying gRPC server-stream call could
      not be opened (transport failure, permission, etc.). The underlying
      reason is in `:code`.

  ## Errors during iteration (raised — Elixir Stream convention)

  Transport errors that arrive after the stream is opened (e.g. mid-stream
  `GRPC.RPCError` or connection drop) raise `Modal.Error`. This matches the
  surface of `File.stream!/3` and friends — stream consumers cannot return
  tuples from inside an `Enum.*` call. Callers who want to recover from
  mid-stream errors must wrap the consumption in `try/rescue`.

  The stream is single-consumption: do not pass it to more than one `Enum.*`
  call.

  ## Protocol details

  Modal's `TaskExecStdioRead` RPC is a server-streaming call that the
  client is expected to reopen across the lifetime of an exec. Each call
  has a finite deadline; when the deadline approaches, the worker
  flushes any buffered output and closes the stream cleanly. The client
  reconnects with the new `offset` (sum of bytes already consumed) until
  the exec exits, at which point the next call returns 0 frames and
  EOFs immediately. This mirrors the reference Go and JS SDKs.

  The reconnect loop is transparent to consumers — the returned `Stream`
  yields binary chunks in order, and only EOF or a non-retryable error
  ends iteration.

  ## Example

      case Modal.ContainerProcess.stream(proc) do
        {:ok, stream} ->
          Enum.each(stream, &IO.write/1)

        {:error, %Modal.Error{kind: :jwt_expired}} ->
          # Re-exec to get a fresh ContainerProcess.
          ...
      end

      # Stream stderr instead:
      {:ok, errs} = Modal.ContainerProcess.stream(proc, fd: :stderr)
  """
  @spec stream(t(), keyword()) :: {:ok, Enumerable.t()} | {:error, Modal.Error.t()}
  def stream(proc, opts \\ [])

  def stream(%__MODULE__{} = proc, opts) when is_list(opts) do
    fd = fd_for(Keyword.get(opts, :fd, :stdout))

    with :ok <- check_jwt(proc),
         # Probe-open the first stream so JWT-expired and open-failure
         # errors surface as `{:error, _}` at this call site (the
         # documented contract), not as an exception inside an `Enum.*`
         # consumer.
         {:ok, first_enum} <- open_stdio_chunk(proc, 0, fd) do
      {:ok, resumable_stream(proc, first_enum, fd)}
    end
  end

  # The Modal proto's `TaskExecStdioFileDescriptor` enum tags each read
  # with the fd the server should send. We accept the friendlier atom at
  # the call site and translate here so the proto enum never leaks out.
  defp fd_for(:stdout), do: :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDOUT
  defp fd_for(:stderr), do: :TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDERR

  defp fd_for(other),
    do: raise(ArgumentError, "expected :fd to be :stdout or :stderr, got #{inspect(other)}")

  # Build a resumable Stream over many sequential `task_exec_stdio_read`
  # calls.
  #
  # State passed through `Stream.resource/3`: `{enum | nil, offset}`.
  # - `enum` is the currently-open gRPC server stream; `nil` means
  #   "open a fresh one on the next pull".
  # - `offset` is the running byte count we've consumed; sent as the
  #   `offset` field on the next reconnect.
  #
  # Each next_fun call drains one open gRPC stream end-to-end (one
  # server-side flush cycle), then decides whether to terminate or
  # reconnect:
  #   - Clean EOF with zero new chunks  → exec done, halt.
  #   - Clean EOF with chunks           → reconnect; more data may be coming.
  #   - Retryable error (4/8/10/14)     → reconnect at the same offset.
  #   - Non-retryable error             → raise.
  defp resumable_stream(proc, first_enum, fd) do
    start_fun = fn -> {first_enum, 0} end

    next_fun = fn
      {nil, offset} ->
        case open_stdio_chunk(proc, offset, fd) do
          {:ok, enum} -> pull_one(enum, offset)
          {:error, %Modal.Error{} = e} -> raise e
        end

      {enum, offset} ->
        pull_one(enum, offset)
    end

    after_fun = fn _state -> :ok end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  # Drain the current gRPC stream to its natural end, returning the
  # accumulated chunks and a Stream.resource-shaped continuation. Raises
  # on a non-retryable mid-iteration error (the documented contract).
  defp pull_one(enum, offset) do
    {chunks, new_offset, terminator} = drain_call(enum, offset)

    case terminator do
      :eof when chunks == [] ->
        # Server flushed nothing and closed cleanly — the exec has
        # exited and there is no more output.
        {:halt, {nil, new_offset}}

      :eof ->
        # We got data this round and the stream closed cleanly. The
        # close may have been deadline-driven (our call timeout) or
        # exec-driven (exec finished). Reconnect to find out — the
        # next round will either return zero chunks (exec done) or
        # more data.
        {chunks, {nil, new_offset}}

      {:retryable, _err} ->
        # Server closed with a retryable code — almost always
        # DEADLINE_EXCEEDED from our own call timeout. Reconnect.
        {chunks, {nil, new_offset}}

      {:fatal, err} ->
        raise err
    end
  end

  defp drain_call(enum, offset) do
    Enum.reduce(enum, {[], offset}, fn item, {chunks, off} ->
      case item do
        {:ok, %{data: data}} when byte_size(data) > 0 ->
          {[data | chunks], off + byte_size(data)}

        {:ok, _empty_frame} ->
          {chunks, off}

        {:error, %GRPC.RPCError{status: status, message: msg}} when status in [4, 8, 10, 14] ->
          # Retryable per Modal's reference clients:
          #   4 DEADLINE_EXCEEDED, 8 RESOURCE_EXHAUSTED,
          #   10 ABORTED, 14 UNAVAILABLE.
          throw({:retryable, chunks, off, Modal.Error.grpc(status, msg)})

        {:error, %GRPC.RPCError{status: status, message: msg}} ->
          throw({:fatal, chunks, off, Modal.Error.grpc(status, msg)})

        {:error, reason} ->
          throw({:fatal, chunks, off, Modal.Error.network(reason)})

        other ->
          throw({:fatal, chunks, off, Modal.Error.unexpected(other)})
      end
    end)
    |> then(fn {chunks, off} -> {Enum.reverse(chunks), off, :eof} end)
  catch
    {kind, chunks, off, err} when kind in [:retryable, :fatal] ->
      {Enum.reverse(chunks), off, {kind, err}}
  end

  defp open_stdio_chunk(proc, offset, fd) do
    request = %TCR.TaskExecStdioReadRequest{
      task_id: proc.task_id,
      exec_id: proc.exec_id,
      offset: offset,
      file_descriptor: fd
    }

    # The call timeout is what lets the server know when to flush. The
    # grpc-elixir gun adapter doubles it for the await ceiling
    # (`timeout * 2`), so the local ceiling is ~2× this value.
    opts = [metadata: auth(proc.jwt), timeout: @stdio_read_call_timeout_ms]

    case span(:task_exec_stdio_read, fn ->
           tcr_stub(proc).task_exec_stdio_read(proc.channel, request, opts)
         end) do
      {:ok, enum} -> {:ok, enum}
      {:error, reason} -> {:error, Modal.Error.open_failed(reason)}
    end
  end

  @doc "Block until the process exits. Returns `{:ok, exit_code}`."
  @spec exit_code(t()) :: {:ok, integer() | nil} | {:error, Modal.Error.t()}
  def exit_code(%__MODULE__{} = proc) do
    with :ok <- check_jwt(proc) do
      wait_loop(proc, 0)
    end
  end

  @doc """
  Write to stdin.

  Honours the same JWT-expiry guard as `stream/1` and `exit_code/1`: if the
  worker JWT has already expired, returns `{:error, %Modal.Error{kind:
  :jwt_expired}}` immediately rather than letting the write fail on the
  server with an opaque permission error.
  """
  @spec write(t(), binary(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def write(%__MODULE__{} = proc, data, opts \\ []) do
    with :ok <- check_jwt(proc) do
      request = %TCR.TaskExecStdinWriteRequest{
        task_id: proc.task_id,
        exec_id: proc.exec_id,
        offset: Keyword.get(opts, :offset, 0),
        data: data,
        eof: Keyword.get(opts, :eof, false)
      }

      result =
        span(:task_exec_stdin_write, fn ->
          tcr_stub(proc).task_exec_stdin_write(proc.channel, request, metadata: auth(proc.jwt))
        end)

      to_write_result(result)
    end
  end

  defp to_write_result({:ok, _}), do: :ok

  defp to_write_result({:error, %GRPC.RPCError{status: s, message: m}}),
    do: {:error, Modal.Error.grpc(s, m)}

  defp to_write_result({:error, reason}), do: {:error, Modal.Error.network(reason)}

  @doc """
  Run to completion, collect stdout and stderr, return exit code.

  Concurrently opens the stdout and stderr streams and polls for exit
  via HTTP/2 multiplexing (one channel, three logical streams).

  ## Options

    * `:timeout` — wall-clock milliseconds for the whole operation
      (default `:infinity`). Returns `{:error, %Modal.Error{kind:
      :timeout}}` if exceeded.
    * `:on_stdout` — 1-arity callback fired per stdout chunk as it
      arrives. Chunks are ALSO collected into the result's `:stdout`
      — the callback is for side effects (progress bars, prefixed
      live output, forwarding to a log sink). Wrap with
      `line_buffered/1` for one invocation per `\\n`-terminated
      line. Default: no-op.
    * `:on_stderr` — same shape, for stderr.

  ## Result shape

      {:ok, %{stdout: binary(), stderr: binary(), code: integer() | nil}}

  `:code` is the integer exit code, or `128 + signal` for signal exits,
  or `nil` if the worker didn't report one. See `await!/2` for a
  raising variant that bubbles non-zero exits as
  `%Modal.Error{kind: :exec_failed}` and missing exit codes as
  `%Modal.Error{kind: :exec_unknown_status}`. Pick based on whether
  a non-zero exit is a normal result or a bug — same domain decision
  as `Modal.Sandbox.exec_streaming/3` (which fuses `exec + await +
  close` for the common case).

  ## Live streaming example

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      result = Modal.ContainerProcess.await!(proc,
        on_stdout: Modal.ContainerProcess.line_buffered(&IO.puts/1)
      )
      Modal.ContainerProcess.close(proc)

  See also `Modal.Sandbox.exec_streaming/3` for the common shape that
  fuses `exec + await + close` into a single call.
  """
  @spec await(t(), keyword()) ::
          {:ok, %{stdout: String.t(), stderr: String.t(), code: integer() | nil}}
          | {:error, Modal.Error.t()}
  def await(%__MODULE__{} = proc, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    on_stdout = Keyword.get(opts, :on_stdout, &noop/1)
    on_stderr = Keyword.get(opts, :on_stderr, &noop/1)

    # We can't simply open the streams here and pass them to child
    # tasks: the underlying gun process sends server-streaming frames
    # to the *opening* PID's mailbox, so a child iterating a stream
    # opened by the parent blocks forever. But callers rely on early
    # error detection (`:jwt_expired`, `:open_failed`) from this
    # function returning a tuple, so we probe-open here to surface
    # those errors, then let each child task re-open its own stream
    # for the actual consumption. The probe RPC and the consumer RPC
    # are both `task_exec_stdio_read` calls — two per `await/2` on
    # the success path. Modal returns from these in tens of
    # milliseconds, so the doubled RPC count is cheaper than losing
    # the up-front error contract.
    with :ok <- check_jwt(proc),
         {:ok, _stdout_probe} <- open_stdio_chunk(proc, 0, fd_for(:stdout)),
         {:ok, _stderr_probe} <- open_stdio_chunk(proc, 0, fd_for(:stderr)) do
      await_with_streams(proc, timeout, on_stdout, on_stderr)
    else
      {:error, %Modal.Error{} = e} -> {:error, e}
    end
  end

  defp noop(_chunk), do: :ok

  @doc """
  Like `await/2` but raises `%Modal.Error{kind: :exec_failed}` on a
  non-zero exit, and bubbles any other `%Modal.Error{}` as-is.

  This is the right default for "run a command and use its output" call
  sites — the alternative is `{:ok, %{code: 0}} = await(proc)` which
  raises a `MatchError` on failure with no diagnostic. The raised
  `%Modal.Error{}` carries the exit code in `:code` and the captured
  stdout/stderr in `:metadata`.

      result = Modal.ContainerProcess.await!(proc)
      # %{stdout: "...", stderr: "...", code: 0}

  Rescue when you need to recover:

      try do
        Modal.ContainerProcess.await!(proc)
      rescue
        e in Modal.Error ->
          # e.code, e.metadata.stdout, e.metadata.stderr
          ...
      end
  """
  @spec await!(t(), keyword()) :: %{
          stdout: String.t(),
          stderr: String.t(),
          code: integer() | nil
        }
  def await!(%__MODULE__{} = proc, opts \\ []) do
    case await(proc, opts) do
      {:ok, %{code: 0} = result} ->
        result

      {:ok, %{code: nil, stdout: stdout, stderr: stderr}} ->
        raise Modal.Error.exec_unknown_status(stdout, stderr)

      {:ok, %{code: code, stdout: stdout, stderr: stderr}} ->
        raise Modal.Error.exec_failed(code, stdout, stderr)

      {:error, %Modal.Error{} = e} ->
        raise e
    end
  end

  defp await_with_streams(proc, timeout, on_stdout, on_stderr) do
    outer =
      Task.async(fn ->
        collect_streams_and_exit(proc, on_stdout, on_stderr)
      end)

    case Task.yield(outer, timeout) do
      {:ok, result} -> result
      nil -> shutdown_and_return(outer, {:error, Modal.Error.timeout()})
      {:exit, reason} -> {:error, Modal.Error.task_crashed(:exit, reason)}
    end
  end

  # Grace period for the stream collectors to reach EOF after exec
  # exit. Modal's worker flushes pending stdio promptly when an exec
  # exits, but a stream that produced no data (typical: stderr from a
  # successful program that wrote only to stdout) takes up to one
  # `@stdio_read_call_timeout_ms` cycle to see a clean :eof — and
  # often more if the worker buffers across the exit. Three seconds
  # covers the worst case empirically without making fast paths
  # noticeably slower (cheap programs return within the first hundred
  # milliseconds).
  @drain_grace_ms 3_000

  defp collect_streams_and_exit(proc, on_stdout, on_stderr) do
    # Each collector opens its stream *inside* its own Task so the gun
    # call's response frames land in that task's mailbox. The previous
    # version pre-opened the streams in the parent and passed the
    # Enumerable to the children — frames went to the parent and the
    # child's iteration blocked forever.
    stdout_task = Task.async(fn -> consume_stream(proc, :stdout, on_stdout) end)
    stderr_task = Task.async(fn -> consume_stream(proc, :stderr, on_stderr) end)

    case exit_code(proc) do
      {:ok, code} ->
        # Stream-collecting tasks may still be blocked in the
        # reconnect loop waiting for EOF. Give them a grace period
        # to drain naturally, then `shutdown` whatever's left so a
        # silent stderr doesn't hold the whole await/2 hostage.
        stdout = await_or_shutdown(stdout_task)
        stderr = await_or_shutdown(stderr_task)
        {:ok, %{stdout: stdout, stderr: stderr, code: code}}

      {:error, reason} ->
        Task.shutdown(stdout_task, :brutal_kill)
        Task.shutdown(stderr_task, :brutal_kill)
        {:error, reason}
    end
  end

  # Open and consume the stream for `fd` from inside the calling
  # process. If the open itself fails (jwt expired, gRPC unavailable),
  # we silently return "" — the open-failure surface lives on
  # `stream/2`'s tuple return when callers want it; await/2's
  # contract is to deliver what could be collected and let the exit
  # code carry the success/failure signal.
  defp consume_stream(proc, fd, callback) do
    case stream(proc, fd: fd) do
      {:ok, stream} -> collect_with_callback(stream, callback)
      {:error, _} -> ""
    end
  rescue
    # Mid-iteration errors (network drop, non-retryable gRPC) raise
    # from inside Enum.reduce. Match the original "exit_code is the
    # signal of truth" contract by absorbing them here and returning
    # whatever was collected before the raise.
    _ -> ""
  end

  # Wait up to `@drain_grace_ms` for `task` to finish; if it does,
  # return its value. Otherwise brutal_kill the task and return the
  # empty string (post-exit trailing chunks are lost — typically a
  # final newline or two; the on_chunk callback has already seen
  # everything that did arrive in time).
  defp await_or_shutdown(task) do
    case Task.yield(task, @drain_grace_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, value} -> value
      _ -> ""
    end
  end

  # Fold the stream, firing `callback` per chunk for side effects AND
  # accumulating chunks for the result. Reverse-then-iolist-flatten is
  # O(n) and avoids the per-chunk `<>` quadratic blowup that naive
  # `acc <> chunk` would produce.
  defp collect_with_callback(stream, callback) do
    stream
    |> Enum.reduce([], fn chunk, acc ->
      callback.(chunk)
      [chunk | acc]
    end)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp shutdown_and_return(task, return_value) do
    Task.shutdown(task, :brutal_kill)
    return_value
  end

  @doc "Close the gRPC channel to the worker."
  @spec close(t()) :: :ok
  def close(%__MODULE__{channel: channel, monitor_pid: monitor_pid}) do
    if monitor_pid, do: send(monitor_pid, :close)
    GRPC.Stub.disconnect(channel)
    :ok
  end

  # ── Channel monitor ─────────────────────────────────────────────

  defp start_channel_monitor(channel, caller) do
    parent = self()

    pid =
      spawn(fn ->
        ref = Process.monitor(caller)
        send(parent, {self(), :monitor_ready})

        receive do
          {:DOWN, ^ref, :process, ^caller, _reason} ->
            GRPC.Stub.disconnect(channel)

          :close ->
            :ok
        end
      end)

    # Block until the monitor is watching the caller — closes the race where
    # the caller could crash before Process.monitor/1 runs.
    receive do
      {^pid, :monitor_ready} -> pid
    end
  end

  # ── JWT expiry ───────────────────────────────────────────────────

  defp check_jwt(%__MODULE__{jwt_exp: 0}), do: :ok

  defp check_jwt(%__MODULE__{jwt_exp: exp}) do
    now = System.os_time(:second)

    cond do
      now >= exp ->
        {:error, Modal.Error.jwt_expired()}

      now >= exp - @jwt_expiry_warning_secs ->
        Logger.warning(
          "[modal] worker JWT expires in #{exp - now}s — exec may fail. " <>
            "Call Modal.Sandbox.exec/3 to obtain a fresh ContainerProcess."
        )

        :ok

      true ->
        :ok
    end
  end

  # ── Wait with retry ──────────────────────────────────────────────

  # ~5 min of cumulative backoff at base=1s, max=30s — covers a worker
  # paging in slow Docker layers, brief network blips, and Modal-side
  # restarts. Non-transient errors short-circuit immediately; this cap
  # only bites on truly stuck servers.
  @max_wait_attempts 100

  @wait_retry_delay Application.compile_env(:modal, :wait_retry_delay, 1_000)
  defp wait_retry_delay, do: @wait_retry_delay

  defp wait_loop(proc, attempts) do
    request = %TCR.TaskExecWaitRequest{task_id: proc.task_id, exec_id: proc.exec_id}

    case span(:task_exec_wait, fn ->
           tcr_stub(proc).task_exec_wait(proc.channel, request,
             metadata: auth(proc.jwt),
             timeout: @wait_attempt_timeout
           )
         end) do
      {:ok, resp} ->
        code =
          case resp.exit_status do
            {:code, c} -> c
            {:signal, s} -> 128 + s
            _ -> nil
          end

        {:ok, code}

      {:error, reason} ->
        err = normalize_error(reason)
        handle_wait_error(err, proc, attempts)
    end
  end

  # Transient (network, deadline_exceeded, unavailable, etc.) → backoff
  # and retry up to @max_wait_attempts. Non-transient (permission_denied,
  # not_found, jwt_expired, …) → surface immediately. Previously every
  # error spun for the full 100 attempts; a hard auth failure took
  # minutes to surface.
  defp handle_wait_error(%Modal.Error{} = err, proc, attempts) do
    cond do
      not Modal.Error.transient?(err) ->
        {:error, err}

      attempts >= @max_wait_attempts ->
        {:error, err}

      true ->
        with :ok <- check_jwt(proc) do
          Process.sleep(Modal.Backoff.delay(attempts, wait_retry_delay()))
          wait_loop(proc, attempts + 1)
        end
    end
  end

  defp normalize_error(%Modal.Error{} = e), do: e
  defp normalize_error(%GRPC.RPCError{status: s, message: m}), do: Modal.Error.grpc(s, m)
  defp normalize_error(reason), do: Modal.Error.network(reason)

  # ── Connection ───────────────────────────────────────────────────

  defp connect_to_worker(client, task_id) do
    with {:ok, resp} <-
           Modal.RPC.call(
             client,
             :TaskGetCommandRouterAccess,
             %Modal.Client.TaskGetCommandRouterAccessRequest{task_id: task_id}
           ),
         {:ok, channel} <-
           GRPC.Stub.connect(resp.url,
             cred:
               GRPC.Credential.new(
                 ssl: [cacertfile: CAStore.file_path(), verify: :verify_peer, depth: 4]
               ),
             headers: [{"authorization", "Bearer #{resp.jwt}"}]
           ) do
      {:ok, channel, resp.jwt}
    else
      {:error, %Modal.Error{} = e} -> {:error, e}
      {:error, reason} -> {:error, Modal.Error.network(reason)}
    end
  end

  defp tcr_stub(%__MODULE__{tcr_stub: nil}), do: @default_tcr_stub
  defp tcr_stub(%__MODULE__{tcr_stub: stub}), do: stub

  defp auth(jwt), do: %{"authorization" => "Bearer #{jwt}"}

  # ── line_buffered/1 — stream chunk → line callback adapter ──────

  @doc """
  Adapter that turns a chunk callback into a line-at-a-time callback,
  buffering across chunks until a complete `\\n`-terminated line is
  available.

  `Modal.ContainerProcess.stream/2`, `await/2`'s `:on_stdout`/`:on_stderr`
  callbacks, and `Modal.Image.get_or_create/3`'s `:on_log` all deliver
  raw byte chunks — a chunk can contain a partial line, multiple lines,
  or a partial-then-newline-then-partial. Most call sites that prefix
  output or log per-line want exactly one invocation per `\\n`-terminated
  line; this wrapper buffers across chunks and dispatches when a line
  is complete.

      proc = Modal.Sandbox.exec!(sandbox, ["pytest", "-v"])
      cb = Modal.ContainerProcess.line_buffered(fn line ->
        IO.puts("[\#{candidate_id}] " <> line)
      end)

      {:ok, stream} = Modal.ContainerProcess.stream(proc)
      Enum.each(stream, cb)

  Trailing partial lines (text after the final `\\n`) are held in a
  per-process buffer and never dispatched. Most program output ends
  with a newline, so the dropped tail is empty in practice; callers
  that need byte-for-byte fidelity should consume the raw stream.

  Buffer lives in the calling process's process dictionary, keyed by
  a unique reference. Two concurrent `line_buffered/1` instances in
  the same process don't collide; the entry is small (under 1KB in
  steady state) and is GC'd when the process exits.

  This used to live on `Modal.Image` as a build-log helper.
  `Modal.Image.line_buffered/1` is preserved as a delegate for
  backwards compatibility.
  """
  @spec line_buffered((String.t() -> any())) :: (binary() -> :ok)
  def line_buffered(line_callback) when is_function(line_callback, 1) do
    # `make_ref/0` gives a unique key per invocation so the same caller
    # process can hold multiple independent line buffers without
    # interference (e.g., one stream prefixed for stdout and another
    # for stderr, both via `line_buffered/1`).
    key = {__MODULE__, :line_buffer, make_ref()}

    fn chunk when is_binary(chunk) ->
      buffer = Process.get(key, "") <> chunk

      case String.split(buffer, "\n") do
        [no_newline_yet] ->
          # No complete line yet — keep accumulating.
          Process.put(key, no_newline_yet)

        pieces ->
          # Every element except the last is a complete line. The last
          # is whatever came after the final `\n` (often empty for a
          # chunk that ended cleanly; otherwise a partial line that
          # waits for more bytes).
          {complete, [trailing]} = Enum.split(pieces, -1)
          Enum.each(complete, line_callback)
          Process.put(key, trailing)
      end

      :ok
    end
  end

  # ── Telemetry — worker-channel RPCs ──────────────────────────────
  #
  # The four `task_exec_*` calls below go directly to the per-task
  # gRPC channel (a different transport from the control-plane RPCs
  # in `Modal.RPC`), so they need their own event family. Operators
  # listening for `[:modal, :rpc, :*]` see the control plane; those
  # listening for `[:modal, :worker_rpc, :*]` see the per-exec
  # traffic — exec start, every stdio-read reconnect, every wait
  # poll, every stdin write. Metadata mirrors `Modal.RPC`'s shape
  # (`:method`, `:status`, optional `:error_kind`) so a single
  # handler can subscribe to both event families with the same
  # bucketing logic.
  defp span(method, fun) do
    :telemetry.span([:modal, :worker_rpc], %{method: method}, fn ->
      result = fun.()
      {result, worker_rpc_stop_metadata(method, result)}
    end)
  end

  defp worker_rpc_stop_metadata(method, result) do
    base = %{method: method}

    case result do
      {:ok, _} ->
        Map.put(base, :status, :ok)

      {:error, %GRPC.RPCError{status: code}} ->
        # Mirror the grpc kind name used in Modal.Error so dashboards
        # subscribing to both event families bucket the same way.
        base |> Map.put(:status, :error) |> Map.put(:error_kind, :grpc) |> Map.put(:code, code)

      {:error, _other} ->
        Map.put(base, :status, :error)
    end
  end

  # ── Inspect — redact JWT and raw channel ─────────────────────────

  defimpl Inspect do
    def inspect(%Modal.ContainerProcess{} = proc, _opts) do
      "#Modal.ContainerProcess<task_id: #{proc.task_id}, exec_id: #{proc.exec_id}>"
    end
  end
end
