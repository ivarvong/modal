defmodule Modal.Filesystem do
  @moduledoc """
  File I/O on running sandboxes via `ContainerFilesystemExec`.

      Modal.Filesystem.read_file(sandbox, "/etc/hostname")
      Modal.Filesystem.write_file(sandbox, "/tmp/test.txt", "hello")
      Modal.Filesystem.ls(sandbox, "/work")
  """

  alias Modal.{RPC, Sandbox}

  @write_chunk_size 16 * 1024 * 1024

  @doc "Read a file. Returns `{:ok, content}`."
  def read_file(%Sandbox{} = sb, path) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_exec(sb.client, task_id, {:file_open_request, open_req(path, "r")}),
         {:ok, chunks} <- fs_output(sb.client, fd.exec_id),
         {:ok, _} <- fs_close(sb.client, task_id, fd.file_descriptor) do
      {:ok, IO.iodata_to_binary(chunks)}
    end
  end

  @doc "Write a file. Returns `:ok`."
  def write_file(%Sandbox{} = sb, path, content) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_exec(sb.client, task_id, {:file_open_request, open_req(path, "w")}),
         :ok <- write_chunks(sb.client, task_id, fd.file_descriptor, content),
         {:ok, _} <- fs_flush(sb.client, task_id, fd.file_descriptor),
         {:ok, _} <- fs_close(sb.client, task_id, fd.file_descriptor) do
      :ok
    end
  end

  @doc "List directory. Returns `{:ok, [filename]}`."
  def ls(%Sandbox{} = sb, path \\ "/") do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, resp} <-
           fs_exec(
             sb.client,
             task_id,
             {:file_ls_request, %Modal.Client.ContainerFileLsRequest{path: path}}
           ),
         {:ok, chunks} <- fs_output(sb.client, resp.exec_id) do
      {:ok, chunks |> IO.iodata_to_binary() |> String.trim() |> String.split("\n", trim: true)}
    end
  end

  @doc "Create directory."
  def mkdir(%Sandbox{} = sb, path, opts \\ []) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb) do
      oneof =
        {:file_mkdir_request,
         %Modal.Client.ContainerFileMkdirRequest{
           path: path,
           make_parents: Keyword.get(opts, :parents, true)
         }}

      with {:ok, resp} <- fs_exec(sb.client, task_id, oneof),
           {:ok, _} <- fs_output(sb.client, resp.exec_id),
           do: :ok
    end
  end

  @doc "Remove file or directory."
  def rm(%Sandbox{} = sb, path, opts \\ []) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb) do
      oneof =
        {:file_rm_request,
         %Modal.Client.ContainerFileRmRequest{
           path: path,
           recursive: Keyword.get(opts, :recursive, false)
         }}

      with {:ok, resp} <- fs_exec(sb.client, task_id, oneof),
           {:ok, _} <- fs_output(sb.client, resp.exec_id),
           do: :ok
    end
  end

  # ── Internals ───────────────────────────────────────────────────

  defp open_req(path, mode), do: %Modal.Client.ContainerFileOpenRequest{path: path, mode: mode}

  defp fs_exec(client, task_id, oneof) do
    request = %Modal.Client.ContainerFilesystemExecRequest{
      file_exec_request_oneof: oneof,
      task_id: task_id
    }

    with {:ok, resp} <- RPC.call(client, :ContainerFilesystemExec, request),
         {:ok, _} <- fs_output(client, resp.exec_id) do
      {:ok, resp}
    end
  end

  defp fs_flush(client, task_id, fd) do
    fs_exec(
      client,
      task_id,
      {:file_flush_request, %Modal.Client.ContainerFileFlushRequest{file_descriptor: fd}}
    )
  end

  defp fs_close(client, task_id, fd) do
    fs_exec(
      client,
      task_id,
      {:file_close_request, %Modal.Client.ContainerFileCloseRequest{file_descriptor: fd}}
    )
  end

  defp write_chunks(client, task_id, fd, data) do
    data
    |> chunk_binary()
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      oneof =
        {:file_write_request,
         %Modal.Client.ContainerFileWriteRequest{file_descriptor: fd, data: chunk}}

      case fs_exec(client, task_id, oneof) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp chunk_binary(data), do: chunk_binary(data, 0, [])
  defp chunk_binary(data, offset, acc) when offset >= byte_size(data), do: Enum.reverse(acc)

  defp chunk_binary(data, offset, acc) do
    size = min(@write_chunk_size, byte_size(data) - offset)
    chunk_binary(data, offset + size, [binary_part(data, offset, size) | acc])
  end

  defp fs_output(client, exec_id, retries \\ 10) do
    request = %Modal.Client.ContainerFilesystemExecGetOutputRequest{
      exec_id: exec_id,
      timeout: 55.0
    }

    case RPC.stream(client, :ContainerFilesystemExecGetOutput, request) do
      {:ok, batches} ->
        if error = Enum.find_value(batches, & &1.error) do
          {:error, {:filesystem_error, error.error_message}}
        else
          {:ok, Enum.flat_map(batches, & &1.output)}
        end

      {:error, _} when retries > 0 ->
        Process.sleep(1_000)
        fs_output(client, exec_id, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
