defmodule Modal.ContainerProcess do
  @moduledoc """
  A running command in a Modal Sandbox.

  Implements `Enumerable` -- iterate to stream stdout chunks.

      proc = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)

  For the code-interpreter pattern:

      proc = Modal.Sandbox.exec(sandbox, ["python", "-i"])
      Modal.ContainerProcess.write(proc, "print(2+2)\\n")
      [line] = proc |> Enum.take(1)
      Modal.ContainerProcess.write(proc, "exit()\\n", eof: true)

  Close when done to release the data plane connection:

      Modal.ContainerProcess.close(proc)
  """

  defstruct [:dp, :sandbox, :exec_id]

  @type t :: %__MODULE__{
          dp: pid(),
          sandbox: Modal.Sandbox.t(),
          exec_id: String.t()
        }

  @doc false
  def start(%Modal.Sandbox{} = sandbox, command, opts \\ []) do
    {:ok, dp} = Modal.DataPlane.start_link(sandbox.client, sandbox.id)
    {:ok, exec_id} = Modal.DataPlane.exec_start(dp, command, opts)

    %__MODULE__{dp: dp, sandbox: sandbox, exec_id: exec_id}
  end

  @doc "Get the exit code. Blocks until the process finishes."
  @spec exit_code(t()) :: {:ok, integer() | nil} | {:error, term()}
  def exit_code(%__MODULE__{} = proc) do
    case Modal.DataPlane.exec_wait(proc.dp, proc.exec_id) do
      {:ok, %{code: code}} -> {:ok, code}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Write to stdin."
  @spec write(t(), binary(), keyword()) :: :ok | {:error, term()}
  def write(%__MODULE__{} = proc, data, opts \\ []) do
    Modal.DataPlane.exec_stdin_write(proc.dp, proc.exec_id, data, opts)
  end

  @doc "Run to completion and return all stdout + exit code."
  @spec await(t()) :: {:ok, %{stdout: String.t(), code: integer() | nil}} | {:error, term()}
  def await(%__MODULE__{} = proc) do
    case Modal.DataPlane.exec_wait(proc.dp, proc.exec_id) do
      {:ok, %{code: code}} ->
        stdout = collect_stdout(proc)
        {:ok, %{stdout: stdout, code: code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Close the data plane connection."
  @spec close(t()) :: :ok
  def close(%__MODULE__{dp: dp}) do
    if Process.alive?(dp), do: GenServer.stop(dp), else: :ok
  end

  defp collect_stdout(proc) do
    case Modal.DataPlane.exec_stdio_read(proc.dp, proc.exec_id) do
      {:ok, data} -> data
      {:error, _} -> ""
    end
  end

  # ── Enumerable (streams stdout chunks) ──────────────────────────

  defimpl Enumerable do
    def count(_), do: {:error, __MODULE__}
    def member?(_, _), do: {:error, __MODULE__}
    def slice(_), do: {:error, __MODULE__}

    def reduce(%Modal.ContainerProcess{} = proc, acc, fun) do
      case Modal.DataPlane.exec_stdio_stream(proc.dp, proc.exec_id) do
        {:ok, stream_pid} ->
          do_reduce(stream_pid, acc, fun)

        {:error, _} ->
          {:done, acc}
      end
    end

    defp do_reduce(_stream, {:halt, acc}, _fun), do: {:halted, acc}

    defp do_reduce(stream, {:suspend, acc}, fun),
      do: {:suspended, acc, &do_reduce(stream, &1, fun)}

    defp do_reduce(stream, {:cont, acc}, fun) do
      case Modal.DataPlane.StdioStream.next(stream) do
        {:ok, data} -> do_reduce(stream, fun.(data, acc), fun)
        :done -> {:done, acc}
      end
    end
  end
end
