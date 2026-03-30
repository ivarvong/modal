defmodule Modal.ContainerProcess do
  @moduledoc """
  A running command in a Modal Sandbox.

  Implements `Enumerable` for streaming stdout. Supports concurrent
  stdin writes and exit code polling via HTTP/2 multiplexing on a
  shared gRPC channel to the worker.

  ## Streaming stdout

      proc = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)

  ## Interactive stdin/stdout

      proc = Modal.Sandbox.exec(sandbox, ["python3", "-i"])
      Modal.ContainerProcess.write(proc, "print(2+2)\\n")
      [line] = Enum.take(proc, 1)

  ## Collect all output at once

      {:ok, result} = Modal.ContainerProcess.await(proc)
      result.stdout  #=> "..."
      result.code    #=> 0

  Always close when done:

      Modal.ContainerProcess.close(proc)
  """

  alias Modal.TaskCommandRouter, as: TCR
  alias Modal.TaskCommandRouter.TaskCommandRouter.Stub, as: TCRStub

  @wait_attempt_timeout 60_000
  @wait_retry_delay 1_000

  defstruct [:channel, :task_id, :exec_id, :sandbox, :jwt]

  @type t :: %__MODULE__{
          channel: GRPC.Channel.t(),
          task_id: String.t(),
          exec_id: String.t(),
          sandbox: Modal.Sandbox.t(),
          jwt: String.t()
        }

  @doc false
  def start(%Modal.Sandbox{} = sandbox, command, opts \\ []) do
    with {:ok, task_id} <- Modal.Sandbox.get_task_id(sandbox),
         {:ok, channel, jwt} <- connect_to_worker(sandbox.client, task_id) do
      exec_id = "ex-#{System.unique_integer([:positive, :monotonic])}"

      request = %TCR.TaskExecStartRequest{
        task_id: task_id,
        exec_id: exec_id,
        command_args: command,
        stdout_config: :TASK_EXEC_STDOUT_CONFIG_PIPE,
        stderr_config: :TASK_EXEC_STDERR_CONFIG_PIPE,
        timeout_secs: Keyword.get(opts, :timeout_secs, 300),
        workdir: Keyword.get(opts, :workdir, "")
      }

      case TCRStub.task_exec_start(channel, request, metadata: auth(jwt)) do
        {:ok, _} ->
          %__MODULE__{
            channel: channel,
            task_id: task_id,
            exec_id: exec_id,
            sandbox: sandbox,
            jwt: jwt
          }

        {:error, %GRPC.RPCError{} = err} ->
          GRPC.Stub.disconnect(channel)
          raise "exec_start failed: #{err.message}"
      end
    else
      {:error, reason} -> raise "ContainerProcess.start failed: #{inspect(reason)}"
    end
  end

  @doc "Block until the process exits. Returns `{:ok, exit_code}`."
  @spec exit_code(t()) :: {:ok, integer() | nil} | {:error, term()}
  def exit_code(%__MODULE__{} = proc) do
    wait_loop(proc, 0)
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

    case TCRStub.task_exec_stdin_write(proc.channel, request, metadata: auth(proc.jwt)) do
      {:ok, _} -> :ok
      {:error, %GRPC.RPCError{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run to completion, collect all stdout, return exit code.

  Streams stdout and waits for exit concurrently via HTTP/2 multiplexing.
  """
  @spec await(t()) :: {:ok, %{stdout: String.t(), code: integer() | nil}} | {:error, term()}
  def await(%__MODULE__{} = proc) do
    stdout_task = Task.async(fn -> Enum.join(proc) end)

    case exit_code(proc) do
      {:ok, code} ->
        stdout = Task.await(stdout_task, :infinity)
        {:ok, %{stdout: stdout, code: code}}

      {:error, reason} ->
        Task.shutdown(stdout_task)
        {:error, reason}
    end
  end

  @doc "Close the gRPC channel to the worker."
  @spec close(t()) :: :ok
  def close(%__MODULE__{channel: channel}) do
    GRPC.Stub.disconnect(channel)
    :ok
  end

  # ── Wait with infinite retry ────────────────────────────────────

  defp wait_loop(proc, attempts) do
    request = %TCR.TaskExecWaitRequest{task_id: proc.task_id, exec_id: proc.exec_id}

    case TCRStub.task_exec_wait(proc.channel, request,
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
        Process.sleep(@wait_retry_delay)
        wait_loop(proc, attempts + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Connection ──────────────────────────────────────────────────

  defp connect_to_worker(client, task_id) do
    with {:ok, resp} <-
           Modal.Client.rpc(
             client,
             :task_get_command_router_access,
             %Modal.Client.TaskGetCommandRouterAccessRequest{task_id: task_id}
           ),
         {:ok, channel} <-
           GRPC.Stub.connect(resp.url,
             cred:
               GRPC.Credential.new(
                 ssl: [cacerts: :public_key.cacerts_get(), verify: :verify_peer, depth: 4]
               ),
             headers: [{"authorization", "Bearer #{resp.jwt}"}]
           ) do
      {:ok, channel, resp.jwt}
    end
  end

  defp auth(jwt), do: %{"authorization" => "Bearer #{jwt}"}

  # ── Enumerable (stdout streaming) ───────────────────────────────
  #
  # The gRPC server-streaming RPC returns {:ok, enum} where enum
  # yields {:ok, %{data: binary}} items. We unwrap the data bytes
  # and yield them as plain binaries.

  defimpl Enumerable do
    def count(_), do: {:error, __MODULE__}
    def member?(_, _), do: {:error, __MODULE__}
    def slice(_), do: {:error, __MODULE__}

    def reduce(%Modal.ContainerProcess{} = proc, acc, fun) do
      request = %Modal.TaskCommandRouter.TaskExecStdioReadRequest{
        task_id: proc.task_id,
        exec_id: proc.exec_id,
        offset: 0
      }

      case Modal.TaskCommandRouter.TaskCommandRouter.Stub.task_exec_stdio_read(
             proc.channel,
             request,
             metadata: %{"authorization" => "Bearer #{proc.jwt}"}
           ) do
        {:ok, enum} ->
          enum
          |> Stream.flat_map(fn
            {:ok, %{data: data}} when byte_size(data) > 0 -> [data]
            _ -> []
          end)
          |> Enumerable.reduce(acc, fun)

        {:error, _} ->
          {:done, elem(acc, 1)}
      end
    end
  end
end
