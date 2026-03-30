defmodule Modal.Filesystem do
  @moduledoc """
  File I/O on running sandboxes via `ContainerFilesystemExec`.

  Called through `Modal.Sandbox` delegates:

      Modal.Sandbox.read_file(sandbox, "/etc/hostname")
      Modal.Sandbox.write_file(sandbox, "/tmp/test.txt", "hello")
      Modal.Sandbox.ls(sandbox, "/work")
  """

  alias Modal.{RPC, Sandbox}

  @write_chunk_size 16 * 1024 * 1024

  @doc "Read a file. Returns `{:ok, content}`."
  def read_file(%Sandbox{} = sb, path) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_open(sb.client, task_id, path, "r"),
         {:ok, data} <- fs_read(sb.client, task_id, fd),
         :ok <- fs_close(sb.client, task_id, fd) do
      {:ok, IO.iodata_to_binary(data)}
    end
  end

  @doc "Write a file. Returns `:ok`."
  def write_file(%Sandbox{} = sb, path, content) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_open(sb.client, task_id, path, "w"),
         :ok <- fs_write(sb.client, task_id, fd, content),
         :ok <- fs_flush(sb.client, task_id, fd) do
      fs_close(sb.client, task_id, fd)
    end
  end

  @doc "List directory. Returns `{:ok, [filename]}`."
  def ls(%Sandbox{} = sb, path \\ "/") do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, resp} <-
           fs_call(
             sb.client,
             task_id,
             {:file_ls_request, %Modal.Client.ContainerFileLsRequest{path: path}}
           ),
         {:ok, data} <- fs_wait(sb.client, resp.exec_id) do
      parse_ls_output(IO.iodata_to_binary(data))
    end
  end

  defp parse_ls_output(raw) do
    case Jason.decode(raw) do
      {:ok, %{"paths" => paths}} -> {:ok, paths}
      _ -> {:ok, raw |> String.trim() |> String.split("\n", trim: true)}
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

      with {:ok, resp} <- fs_call(sb.client, task_id, oneof),
           {:ok, _} <- fs_wait(sb.client, resp.exec_id) do
        :ok
      end
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

      with {:ok, resp} <- fs_call(sb.client, task_id, oneof),
           {:ok, _} <- fs_wait(sb.client, resp.exec_id) do
        :ok
      end
    end
  end

  # ── Open / Read / Write / Flush / Close ─────────────────────────

  defp fs_open(client, task_id, path, mode) do
    oneof = {:file_open_request, %Modal.Client.ContainerFileOpenRequest{path: path, mode: mode}}

    with {:ok, resp} <- fs_call(client, task_id, oneof),
         {:ok, _} <- fs_wait(client, resp.exec_id) do
      {:ok, resp.file_descriptor}
    end
  end

  defp fs_read(client, task_id, fd) do
    oneof =
      {:file_read_request, %Modal.Client.ContainerFileReadRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof) do
      fs_wait(client, resp.exec_id)
    end
  end

  defp fs_write(client, task_id, fd, data) do
    data
    |> chunk_binary()
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      oneof =
        {:file_write_request,
         %Modal.Client.ContainerFileWriteRequest{file_descriptor: fd, data: chunk}}

      with {:ok, resp} <- fs_call(client, task_id, oneof),
           {:ok, _} <- fs_wait(client, resp.exec_id) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp fs_flush(client, task_id, fd) do
    oneof =
      {:file_flush_request, %Modal.Client.ContainerFileFlushRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof),
         {:ok, _} <- fs_wait(client, resp.exec_id) do
      :ok
    end
  end

  defp fs_close(client, task_id, fd) do
    oneof =
      {:file_close_request, %Modal.Client.ContainerFileCloseRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof),
         {:ok, _} <- fs_wait(client, resp.exec_id) do
      :ok
    end
  end

  # ── Low-level helpers ───────────────────────────────────────────

  defp fs_call(client, task_id, oneof) do
    request = %Modal.Client.ContainerFilesystemExecRequest{
      file_exec_request_oneof: oneof,
      task_id: task_id
    }

    RPC.call(client, :ContainerFilesystemExec, request)
  end

  defp fs_wait(client, exec_id, retries \\ 10) do
    request = %Modal.Client.ContainerFilesystemExecGetOutputRequest{
      exec_id: exec_id,
      timeout: 55.0
    }

    caller = self()

    result =
      RPC.stream_each(
        client,
        :ContainerFilesystemExecGetOutput,
        request,
        &handle_fs_batch(&1, caller),
        60_000
      )

    {data, error} = collect_fs_messages()

    cond do
      error != nil ->
        {:error, {:filesystem_error, error.error_message}}

      result == :ok ->
        {:ok, data}

      retries > 0 ->
        Process.sleep(1_000)
        fs_wait(client, exec_id, retries - 1)

      true ->
        {:error, result}
    end
  end

  defp handle_fs_batch({:data, batch}, caller) do
    if batch.error do
      send(caller, {:fs_error, batch.error})
      :halt
    else
      if batch.output != [], do: send(caller, {:fs_data, batch.output})
      if batch.eof, do: :halt, else: :ok
    end
  end

  defp handle_fs_batch(:done, _caller), do: :ok

  defp collect_fs_messages(data \\ [], error \\ nil) do
    receive do
      {:fs_data, chunks} -> collect_fs_messages(data ++ chunks, error)
      {:fs_error, err} -> collect_fs_messages(data, err)
    after
      0 -> {data, error}
    end
  end

  defp chunk_binary(data), do: chunk_binary(data, 0, [])
  defp chunk_binary(data, offset, acc) when offset >= byte_size(data), do: Enum.reverse(acc)

  defp chunk_binary(data, offset, acc) do
    size = min(@write_chunk_size, byte_size(data) - offset)
    chunk_binary(data, offset + size, [binary_part(data, offset, size) | acc])
  end
end
