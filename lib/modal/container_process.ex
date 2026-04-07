defmodule Modal.ContainerProcess do
  @moduledoc """
  A running command in a Modal Sandbox.

  Opens a direct gRPC channel to the worker node (separate from the control-plane
  channel in `Modal.Client`) and multiplexes stdout-streaming, stdin-writing,
  and exit-code polling over HTTP/2.

  ## Streaming stdout

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Modal.ContainerProcess.stream() |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)

  ## Collect all output at once

      {:ok, result} = Modal.ContainerProcess.await(proc)
      result.stdout  #=> "..."
      result.code    #=> 0

  Always close when done to release the worker gRPC channel:

      Modal.ContainerProcess.close(proc)

  If the calling process crashes, the channel is cleaned up automatically.

  ## JWT lifetime

  The JWT used to authenticate with the worker is obtained at exec time and
  stored on the struct. It has a finite lifetime (typically several hours).
  Long-running processes will log a warning when the JWT is about to expire.
  If the JWT expires mid-execution, calls will fail with `{:error, :jwt_expired}`.
  Create a new `ContainerProcess` via `Modal.Sandbox.exec/3` to obtain a fresh JWT.
  """

  require Logger

  alias Modal.TaskCommandRouter, as: TCR

  @wait_attempt_timeout 60_000
  # Warn when JWT has less than this many seconds remaining.
  @jwt_expiry_warning_secs 60
  @default_tcr_stub Modal.TaskCommandRouter.TaskCommandRouter.Stub

  defstruct [:channel, :task_id, :exec_id, :jwt, :jwt_exp, :tcr_stub, :monitor_pid]

  @opaque t :: %__MODULE__{
            channel: GRPC.Channel.t(),
            task_id: String.t(),
            exec_id: String.t(),
            jwt: String.t(),
            jwt_exp: non_neg_integer(),
            tcr_stub: module() | nil,
            monitor_pid: pid() | nil
          }

  @doc false
  @spec start(Modal.Sandbox.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def start(%Modal.Sandbox{} = sandbox, command, opts \\ []) do
    caller = self()

    with {:ok, task_id, _sandbox} <- Modal.Sandbox.get_task_id(sandbox),
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

      case stub.task_exec_start(channel, request, metadata: auth(jwt)) do
        {:ok, _} ->
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

        {:error, %GRPC.RPCError{} = err} ->
          GRPC.Stub.disconnect(channel)
          {:error, {:exec_start_failed, err.message}}
      end
    end
  end

  @doc """
  Returns a lazy `Stream` of stdout binary chunks.

  Opens a single gRPC server-streaming call. The stream is single-consumption —
  do not pass the returned stream to more than one `Enum.*` call.
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{} = proc) do
    with :ok <- check_jwt(proc) do
      request = %TCR.TaskExecStdioReadRequest{
        task_id: proc.task_id,
        exec_id: proc.exec_id,
        offset: 0
      }

      case tcr_stub(proc).task_exec_stdio_read(proc.channel, request, metadata: auth(proc.jwt)) do
        {:ok, grpc_enum} ->
          Stream.flat_map(grpc_enum, fn
            {:ok, %{data: data}} when byte_size(data) > 0 -> [data]
            _ -> []
          end)

        {:error, reason} ->
          raise "Modal.ContainerProcess.stream/1 failed to open stdout stream: #{inspect(reason)}"
      end
    else
      {:error, :jwt_expired} ->
        raise "Modal.ContainerProcess.stream/1: worker JWT has expired. " <>
                "Call Modal.Sandbox.exec/3 again to obtain a fresh ContainerProcess."
    end
  end

  @doc "Block until the process exits. Returns `{:ok, exit_code}`."
  @spec exit_code(t()) :: {:ok, integer() | nil} | {:error, term()}
  def exit_code(%__MODULE__{} = proc) do
    with :ok <- check_jwt(proc) do
      wait_loop(proc, 0)
    end
  end

  @doc "Write to stdin."
  @spec write(t(), binary(), keyword()) :: :ok | {:error, term()}
  def write(%__MODULE__{} = proc, data, opts \\ []) do
    request = %TCR.TaskExecStdinWriteRequest{
      task_id: proc.task_id,
      exec_id: proc.exec_id,
      offset: Keyword.get(opts, :offset, 0),
      data: data,
      eof: Keyword.get(opts, :eof, false)
    }

    case tcr_stub(proc).task_exec_stdin_write(proc.channel, request, metadata: auth(proc.jwt)) do
      {:ok, _} -> :ok
      {:error, %GRPC.RPCError{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run to completion, collect all stdout, return exit code.

  Concurrently opens the stdout stream and polls for exit via HTTP/2
  multiplexing. The optional `timeout` (milliseconds, default `:infinity`)
  applies to the entire operation — both the exit-code poll AND the stdout
  collection. Returns `{:error, :timeout}` if exceeded.
  """
  @spec await(t(), keyword()) ::
          {:ok, %{stdout: String.t(), code: integer() | nil}}
          | {:error, :timeout}
          | {:error, term()}
  def await(%__MODULE__{} = proc, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)

    outer =
      Task.async(fn ->
        stdout_task = Task.async(fn -> proc |> stream() |> Enum.join() end)

        case exit_code(proc) do
          {:ok, code} ->
            stdout = Task.await(stdout_task, :infinity)
            {:ok, %{stdout: stdout, code: code}}

          {:error, reason} ->
            Task.shutdown(stdout_task, :brutal_kill)
            {:error, reason}
        end
      end)

    case Task.yield(outer, timeout) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(outer, :brutal_kill)
        {:error, :timeout}

      {:exit, reason} ->
        {:error, {:task_exit, reason}}
    end
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
        {:error, :jwt_expired}

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

  @wait_retry_delay Application.compile_env(:modal, :wait_retry_delay, 1_000)
  defp wait_retry_delay, do: @wait_retry_delay

  defp wait_loop(proc, attempts) do
    request = %TCR.TaskExecWaitRequest{task_id: proc.task_id, exec_id: proc.exec_id}

    case tcr_stub(proc).task_exec_wait(proc.channel, request,
           metadata: auth(proc.jwt),
           timeout: @wait_attempt_timeout
         ) do
      {:ok, resp} ->
        code =
          case resp.exit_status do
            {:code, c} -> c
            {:signal, s} -> 128 + s
            _ -> nil
          end

        {:ok, code}

      {:error, _} when attempts < 100 ->
        with :ok <- check_jwt(proc) do
          Process.sleep(Modal.Backoff.delay(attempts, wait_retry_delay()))
          wait_loop(proc, attempts + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

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
    end
  end

  defp tcr_stub(%__MODULE__{tcr_stub: nil}), do: @default_tcr_stub
  defp tcr_stub(%__MODULE__{tcr_stub: stub}), do: stub

  defp auth(jwt), do: %{"authorization" => "Bearer #{jwt}"}

  # ── Inspect — redact JWT and raw channel ─────────────────────────

  defimpl Inspect do
    def inspect(%Modal.ContainerProcess{} = proc, _opts) do
      "#Modal.ContainerProcess<task_id: #{proc.task_id}, exec_id: #{proc.exec_id}>"
    end
  end
end
