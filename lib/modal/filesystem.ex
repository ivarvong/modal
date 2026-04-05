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
  @spec read_file(Sandbox.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read_file(%Sandbox{} = sb, path) do
    with {:ok, task_id, _sb} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_open(sb.client, task_id, path, "r"),
         {:ok, data} <- fs_read(sb.client, task_id, fd),
         :ok <- fs_close(sb.client, task_id, fd) do
      {:ok, IO.iodata_to_binary(data)}
    end
  end

  @doc "Like `read_file/2` but raises on error."
  @spec read_file!(Sandbox.t(), String.t()) :: binary()
  def read_file!(%Sandbox{} = sb, path) do
    case read_file(sb, path) do
      {:ok, content} -> content
      {:error, reason} -> raise "Modal.Filesystem.read_file! failed: #{inspect(reason)}"
    end
  end

  @doc "Write a file. Returns `:ok`."
  @spec write_file(Sandbox.t(), String.t(), binary()) :: :ok | {:error, term()}
  def write_file(%Sandbox{} = sb, path, content) do
    with {:ok, task_id, _sb} <- Sandbox.get_task_id(sb),
         {:ok, fd} <- fs_open(sb.client, task_id, path, "w"),
         :ok <- fs_write_chunks(sb.client, task_id, fd, content),
         :ok <- fs_flush(sb.client, task_id, fd) do
      fs_close(sb.client, task_id, fd)
    end
  end

  @doc "Like `write_file/3` but raises on error."
  @spec write_file!(Sandbox.t(), String.t(), binary()) :: :ok
  def write_file!(%Sandbox{} = sb, path, content) do
    case write_file(sb, path, content) do
      :ok -> :ok
      {:error, reason} -> raise "Modal.Filesystem.write_file! failed: #{inspect(reason)}"
    end
  end

  @doc "List directory. Returns `{:ok, [filename]}`."
  @spec ls(Sandbox.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def ls(%Sandbox{} = sb, path \\ "/") do
    with {:ok, task_id, _sb} <- Sandbox.get_task_id(sb),
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

  @doc "Create directory."
  @spec mkdir(Sandbox.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def mkdir(%Sandbox{} = sb, path, opts \\ []) do
    oneof =
      {:file_mkdir_request,
       %Modal.Client.ContainerFileMkdirRequest{
         path: path,
         make_parents: Keyword.get(opts, :parents, true)
       }}

    with {:ok, task_id, _sb} <- Sandbox.get_task_id(sb),
         {:ok, resp} <- fs_call(sb.client, task_id, oneof),
         {:ok, _} <- fs_wait(sb.client, resp.exec_id) do
      :ok
    end
  end

  @doc "Remove file or directory."
  @spec rm(Sandbox.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def rm(%Sandbox{} = sb, path, opts \\ []) do
    oneof =
      {:file_rm_request,
       %Modal.Client.ContainerFileRmRequest{
         path: path,
         recursive: Keyword.get(opts, :recursive, false)
       }}

    with {:ok, task_id, _sb} <- Sandbox.get_task_id(sb),
         {:ok, resp} <- fs_call(sb.client, task_id, oneof),
         {:ok, _} <- fs_wait(sb.client, resp.exec_id) do
      :ok
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
    oneof = {:file_read_request, %Modal.Client.ContainerFileReadRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof) do
      fs_wait(client, resp.exec_id)
    end
  end

  defp fs_write_chunks(client, task_id, fd, data) do
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
    oneof = {:file_flush_request, %Modal.Client.ContainerFileFlushRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof),
         {:ok, _} <- fs_wait(client, resp.exec_id) do
      :ok
    end
  end

  defp fs_close(client, task_id, fd) do
    oneof = {:file_close_request, %Modal.Client.ContainerFileCloseRequest{file_descriptor: fd}}

    with {:ok, resp} <- fs_call(client, task_id, oneof),
         {:ok, _} <- fs_wait(client, resp.exec_id) do
      :ok
    end
  end

  # ── Low-level helpers ────────────────────────────────────────────

  defp fs_call(client, task_id, oneof) do
    request = %Modal.Client.ContainerFilesystemExecRequest{
      file_exec_request_oneof: oneof,
      task_id: task_id
    }

    RPC.call(client, :ContainerFilesystemExec, request)
  end

  # Collects the output of a ContainerFilesystemExecGetOutput stream using
  # a pure reducer — no Agent, no per-call process.
  defp fs_wait(client, exec_id, retries \\ 10) do
    request = %Modal.Client.ContainerFilesystemExecGetOutputRequest{
      exec_id: exec_id,
      timeout: 55.0
    }

    initial = %{data: [], error: nil}

    case RPC.stream_reduce(
           client,
           :ContainerFilesystemExecGetOutput,
           request,
           initial,
           &fs_reducer/2,
           60_000
         ) do
      {:ok, %{error: error}} when error not in [nil, ""] ->
        {:error, {:filesystem_error, error.error_message}}

      {:ok, %{data: data}} ->
        {:ok, Enum.reverse(data)}

      {:error, reason} when retries > 0 ->
        if transient_error?({:error, reason}) do
          Process.sleep(Modal.Backoff.delay(retries, fs_retry_delay()))
          fs_wait(client, exec_id, retries - 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fs_reducer(%{error: error} = _batch, acc) when error not in [nil, ""] do
    {:halt, %{acc | error: error}}
  end

  defp fs_reducer(batch, acc) do
    new_data =
      if batch.output != [],
        do: Enum.reverse(batch.output) ++ acc.data,
        else: acc.data

    if batch.eof,
      do: {:halt, %{acc | data: new_data}},
      else: {:cont, %{acc | data: new_data}}
  end

  # Network errors are transient; gRPC application errors are permanent.
  defp transient_error?({:error, {:network, _}}), do: true
  defp transient_error?(_), do: false

  # Configurable so tests can set it to 0.
  defp fs_retry_delay, do: Application.get_env(:modal, :fs_retry_delay, 1_000)

  defp parse_ls_output(raw) do
    case Jason.decode(raw) do
      {:ok, %{"paths" => paths}} -> {:ok, paths}
      _ -> {:ok, raw |> String.trim() |> String.split("\n", trim: true)}
    end
  end

  @doc false
  def chunk_binary(data, chunk_size \\ @write_chunk_size),
    do: do_chunk(data, chunk_size, 0, [])

  defp do_chunk(data, _size, offset, acc) when offset >= byte_size(data),
    do: Enum.reverse(acc)

  defp do_chunk(data, size, offset, acc) do
    len = min(size, byte_size(data) - offset)
    do_chunk(data, size, offset + len, [binary_part(data, offset, len) | acc])
  end
end
