defmodule Modal.Error do
  @moduledoc """
  Structured error returned by every operation in this library that can fail.

  ## Pattern matching

      case Modal.Sandbox.exec(sandbox, ["pytest", "-v"]) do
        {:ok, proc} ->
          ...

        {:error, %Modal.Error{kind: :grpc, code: 7}} ->
          # gRPC PERMISSION_DENIED

        {:error, %Modal.Error{kind: :network, code: :closed}} ->
          # transport drop — consider retry

        {:error, %Modal.Error{kind: :jwt_expired}} ->
          # re-exec to get a fresh ContainerProcess

        {:error, %Modal.Error{kind: :timeout}} ->
          # the call exceeded its deadline
      end

  ## Raising

  `Modal.Error` is also an Elixir `Exception`. The library raises it from
  inside `Enum.*` consumers (where a tuple can't be returned), and callers
  can rescue it:

      try do
        proc |> Modal.ContainerProcess.stream() |> elem(1) |> Enum.each(&IO.write/1)
      rescue
        e in Modal.Error -> Logger.error(Exception.message(e))
      end

  ## Kinds

  | kind                  | code               | meaning                                     |
  | --------------------- | ------------------ | ------------------------------------------- |
  | `:grpc`               | gRPC status int    | gRPC application-level error                |
  | `:network`            | transport reason   | transport-level failure (often retryable)   |
  | `:timeout`            | `nil`              | operation exceeded its deadline             |
  | `:overloaded`         | `nil`              | `Modal.Client` is at `:max_concurrency`     |
  | `:validation`         | `nil`              | options validation failed                   |
  | `:jwt_expired`        | `nil`              | worker JWT expired — re-exec required       |
  | `:task_crashed`       | `:error`/`:exit`/`:throw` | dispatch task crashed                |
  | `:image_build_failed` | image status atom  | image build returned non-success            |
  | `:snapshot_failed`    | snapshot status    | sandbox/fs snapshot returned non-success    |
  | `:filesystem_error`   | `nil`              | filesystem op (read/write/ls/...) failed    |
  | `:open_failed`        | underlying reason  | could not open a server-streaming RPC       |
  | `:exec_start_failed`  | `nil`              | `TaskExecStart` RPC failed                  |
  | `:exec_failed`        | exit code (int)    | exec ran to completion with a non-zero exit |
  | `:exec_unknown_status`| `nil`              | exec finished but no exit code was reported |
  | `:function_failed`    | `nil`              | remote function/generator raised or failed  |
  | `:output_expired`     | `nil`              | call output expired or its input was lost   |
  | `:credentials_missing`| `nil`              | `Modal.Credentials.load/1` couldn't find any |
  | `:unexpected`         | `nil`              | streaming RPC yielded an unexpected item    |

  Additional details live in `:metadata` — e.g. `:snapshot_failed` carries
  `:scope` (`:vm` or `:fs`), `:task_crashed` carries the original `:reason`,
  `:exec_failed` carries `:stdout` and `:stderr` (the captured output up to
  the moment of exit).
  """

  @type kind ::
          :grpc
          | :network
          | :timeout
          | :overloaded
          | :validation
          | :jwt_expired
          | :task_crashed
          | :image_build_failed
          | :snapshot_failed
          | :filesystem_error
          | :open_failed
          | :exec_start_failed
          | :exec_failed
          | :exec_unknown_status
          | :function_failed
          | :output_expired
          | :credentials_missing
          | :unexpected

  @type t :: %__MODULE__{
          kind: kind(),
          code: term() | nil,
          message: String.t() | nil,
          metadata: map()
        }

  defexception [:kind, :code, :message, metadata: %{}]

  @impl true
  def message(%__MODULE__{kind: k, code: nil, message: nil}),
    do: "Modal error: #{k}"

  def message(%__MODULE__{kind: k, code: c, message: nil}),
    do: "Modal #{k} error (#{inspect(c)})"

  def message(%__MODULE__{kind: k, code: nil, message: m}),
    do: "Modal #{k} error: #{m}"

  def message(%__MODULE__{kind: k, code: c, message: m}),
    do: "Modal #{k} error (#{inspect(c)}): #{m}"

  # ── Constructors ────────────────────────────────────────────────────

  @doc "gRPC application-level error."
  @spec grpc(non_neg_integer(), String.t()) :: t()
  def grpc(status, msg) when is_integer(status) and is_binary(msg) do
    %__MODULE__{kind: :grpc, code: status, message: msg}
  end

  @doc "Transport-level error. `reason` is opaque (atom or term)."
  @spec network(term()) :: t()
  def network(reason) do
    %__MODULE__{kind: :network, code: reason, message: inspect(reason)}
  end

  @doc "Operation exceeded its deadline."
  @spec timeout() :: t()
  def timeout, do: %__MODULE__{kind: :timeout}

  @doc """
  A function call produced no result and has no inputs still running — its
  output expired (already consumed or garbage-collected) or its input was
  lost (e.g. worker preemption with no retry). Terminal: the result is gone;
  re-`invoke`/`spawn` the call to run it again.
  """
  @spec output_expired() :: t()
  def output_expired, do: %__MODULE__{kind: :output_expired}

  @doc "`Modal.Client` is at `:max_concurrency`."
  @spec overloaded() :: t()
  def overloaded, do: %__MODULE__{kind: :overloaded}

  @doc "Options validation failed — typically wraps a `NimbleOptions.ValidationError`."
  @spec validation(Exception.t()) :: t()
  def validation(exception) do
    %__MODULE__{
      kind: :validation,
      message: Exception.message(exception),
      metadata: %{exception: exception}
    }
  end

  @doc "Options validation failed with a custom message (no underlying exception)."
  @spec validation_msg(String.t()) :: t()
  def validation_msg(msg) when is_binary(msg) do
    %__MODULE__{kind: :validation, message: msg}
  end

  @doc "Worker JWT for a `ContainerProcess` has expired."
  @spec jwt_expired() :: t()
  def jwt_expired, do: %__MODULE__{kind: :jwt_expired}

  @doc "Dispatch task crashed mid-RPC."
  @spec task_crashed(:error | :exit | :throw, term()) :: t()
  def task_crashed(kind, reason) when kind in [:error, :exit, :throw] do
    %__MODULE__{
      kind: :task_crashed,
      code: kind,
      message: "dispatch task #{kind}: #{inspect(reason)}",
      metadata: %{reason: reason}
    }
  end

  @doc """
  An image build returned a non-success status (e.g. `:GENERIC_STATUS_FAILURE`).

  `logs` is the full text of the build's `task_logs` stream up to the
  point of failure — typically what you'd want to dump into a diagnostic
  channel. Lives in `:metadata.logs` and the last few lines are surfaced
  in the exception message.
  """
  @spec image_build_failed(atom(), String.t()) :: t()
  def image_build_failed(status, logs \\ "") when is_binary(logs) do
    %__MODULE__{
      kind: :image_build_failed,
      code: status,
      # The formatter prints `(status)` already; the message body is
      # the tail of the build log (or a fallback when no logs streamed).
      message: stderr_tail(logs, "image build failed", 5),
      metadata: %{logs: logs}
    }
  end

  @doc "A sandbox snapshot returned non-success. `scope` is `:vm` or `:fs`."
  @spec snapshot_failed(:vm | :fs, atom()) :: t()
  def snapshot_failed(scope, status) when scope in [:vm, :fs] do
    %__MODULE__{kind: :snapshot_failed, code: status, metadata: %{scope: scope}}
  end

  @doc "A filesystem operation reported an error message."
  @spec filesystem_error(String.t()) :: t()
  def filesystem_error(msg) do
    %__MODULE__{kind: :filesystem_error, message: msg}
  end

  @doc "A server-streaming RPC failed to open."
  @spec open_failed(term()) :: t()
  def open_failed(reason) do
    %__MODULE__{
      kind: :open_failed,
      code: reason,
      message: "could not open server-streaming RPC: #{inspect(reason)}"
    }
  end

  @doc "`TaskExecStart` RPC failed before the process could start."
  @spec exec_start_failed(String.t()) :: t()
  def exec_start_failed(msg) do
    %__MODULE__{kind: :exec_start_failed, message: msg}
  end

  @doc """
  Exec ran to completion with a non-zero exit code.

  `:code` is the exit code (signal exits are mapped to `128 + signal` by
  `Modal.ContainerProcess.await/2`). The captured stdout/stderr at the
  moment of exit are in `:metadata`, and the formatted exception message
  is the tail of stderr so `MatchError`-style call sites diagnose
  themselves without the caller having to crack open metadata.
  """
  @spec exec_failed(integer(), String.t(), String.t()) :: t()
  def exec_failed(code, stdout, stderr) when is_integer(code) do
    %__MODULE__{
      kind: :exec_failed,
      code: code,
      # The formatter (`message/1`) already prints `(code)`, so we don't
      # repeat the number. The body is the stderr tail (the actually-useful
      # diagnostic) — except for a signal exit (128 + signal), where the
      # command was *killed* rather than returning non-zero: there we name
      # the signal and the usual culprits, so a bare 137 isn't a mystery.
      message: exec_failed_message(code, stderr),
      metadata: %{stdout: stdout, stderr: stderr}
    }
  end

  defp exec_failed_message(code, stderr) when code > 128 do
    hint =
      "killed by signal #{code - 128} — likely an exec :timeout_secs, the " <>
        "sandbox's :timeout_secs, or an out-of-memory kill"

    case stderr_tail(stderr, "") do
      "" -> hint
      tail -> hint <> "; " <> tail
    end
  end

  defp exec_failed_message(_code, stderr), do: stderr_tail(stderr, "non-zero exit")

  # Last `take` lines of `stderr` (trimmed), or `fallback` when stderr is
  # empty. The cap is small on purpose — exception messages get printed
  # to logs / shells where multi-screen dumps are hostile.
  defp stderr_tail(stderr, fallback, take \\ 3)
  defp stderr_tail("", fallback, _take), do: fallback

  defp stderr_tail(stderr, _fallback, take) when is_binary(stderr) do
    stderr
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.take(-take)
    |> Enum.join("\n")
  end

  @doc """
  Exec finished but the worker didn't report an exit code. Almost
  always means the sandbox was killed by something external — wall-clock
  `:timeout_secs` fired, OOM kill, worker termination, or a snapshot
  raced with exec exit.

  Distinct from `:exec_failed` (where we know the exit code) so callers
  can decide separately whether to retry on "we have no signal" vs. "the
  program exited non-zero."
  """
  @spec exec_unknown_status(String.t(), String.t()) :: t()
  def exec_unknown_status(stdout, stderr) when is_binary(stdout) and is_binary(stderr) do
    base =
      "exec finished without an exit code — sandbox likely killed " <>
        "externally (wall-clock timeout, OOM, or worker terminated)"

    message =
      case stderr_tail(stderr, "") do
        "" -> base
        tail -> base <> " — " <> tail
      end

    %__MODULE__{
      kind: :exec_unknown_status,
      message: message,
      metadata: %{stdout: stdout, stderr: stderr}
    }
  end

  @doc """
  A remote Modal Function invocation raised an exception. `:metadata`
  carries `:exception` (the Python exception class + message) and
  `:traceback` (the formatted traceback string, if any).
  """
  @spec function_failed(String.t(), String.t() | nil) :: t()
  def function_failed(exception, traceback \\ nil) do
    %__MODULE__{
      kind: :function_failed,
      message: exception,
      metadata: %{exception: exception, traceback: traceback}
    }
  end

  @doc "A streaming RPC yielded an item shape the client could not classify."
  @spec unexpected(term()) :: t()
  def unexpected(item) do
    %__MODULE__{
      kind: :unexpected,
      message: "unexpected stream item: #{inspect(item)}",
      metadata: %{item: item}
    }
  end

  # ── Predicates ──────────────────────────────────────────────────────

  # gRPC canonical codes that are conventionally retryable for idempotent
  # poll-style RPCs:
  #   4  DEADLINE_EXCEEDED — the server timed out on a long-poll; retry.
  #   8  RESOURCE_EXHAUSTED — backpressure; retry after backoff.
  #   10 ABORTED — concurrency conflict; safe to retry idempotent ops.
  #   14 UNAVAILABLE — typical transient server error.
  # We do NOT include 13 (INTERNAL) or 2 (UNKNOWN) — those usually
  # indicate a real bug and retrying spams logs without making progress.
  @retryable_grpc_codes [4, 8, 10, 14]

  @doc """
  True if the error represents a transient condition worth retrying:

    * `:network` — transport drop / refused connection
    * `:open_failed` — server-streaming RPC failed to open
    * `:grpc` with a retryable canonical code (DEADLINE_EXCEEDED,
      RESOURCE_EXHAUSTED, ABORTED, UNAVAILABLE)

  Used by `Modal.Filesystem` and other poll-style call sites that want
  to back off and retry instead of bubbling a transient failure to the
  caller. Callers can still inspect `:kind`/`:code` directly if they
  need a finer-grained policy.
  """
  @spec transient?(t()) :: boolean()
  def transient?(%__MODULE__{kind: kind}) when kind in [:network, :open_failed], do: true
  def transient?(%__MODULE__{kind: :grpc, code: code}), do: code in @retryable_grpc_codes
  def transient?(%__MODULE__{}), do: false
end
