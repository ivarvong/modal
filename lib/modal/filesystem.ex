defmodule Modal.Filesystem do
  @moduledoc """
  Sandbox-side filesystem operations via `ContainerFilesystemExec`.

  Mirrors the `sandbox.filesystem.*` namespace in Modal's reference Python
  client. This is the canonical home for filesystem operations:

      :ok            = Modal.Filesystem.write_file(sandbox, "/tmp/test.txt", "hello")
      {:ok, "hello"} = Modal.Filesystem.read_file(sandbox, "/tmp/test.txt")
      {:ok, files}   = Modal.Filesystem.ls(sandbox, "/tmp")
      :ok            = Modal.Filesystem.mkdir(sandbox, "/tmp/a/b", parents: true)
      :ok            = Modal.Filesystem.rm(sandbox, "/tmp/a", recursive: true)

  `Modal.Sandbox` also exposes thin delegates (`Modal.Sandbox.read_file/2`,
  etc.) as convenience aliases. Both spellings call into this module; prefer
  whichever reads better at the call site.

  ## RPC cost

  Each operation here is a *paired* RPC: one `ContainerFilesystemExec`
  to enqueue the work + one `ContainerFilesystemExecGetOutput` to wait
  for the result. `read_file/2` and `write_file/3` are heavier still —
  they decompose into open + read-or-write + close, so a single
  small-file read is ~6 wire RPCs.

  This is fine for low-frequency ops (config files, test fixtures,
  diff application). For bulk scaffolding — writing N files at sandbox
  boot, common in coding-agent workflows — `write_files/2` fans out
  the writes via `Task.async_stream/3` so the wall-clock cost is
  closer to one slow write, not N.
  """

  alias Modal.{RPC, Sandbox}

  @write_chunk_size 16 * 1024 * 1024

  @doc "Read a file. Returns `{:ok, content}`."
  @spec read_file(Sandbox.t(), String.t()) :: {:ok, binary()} | {:error, Modal.Error.t()}
  def read_file(%Sandbox{} = sb, path) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
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
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc "Write a file. Returns `:ok`."
  @spec write_file(Sandbox.t(), String.t(), binary()) :: :ok | {:error, Modal.Error.t()}
  def write_file(%Sandbox{} = sb, path, content) do
    with {:ok, task_id} <- Sandbox.get_task_id(sb),
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
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Write multiple files to the sandbox in parallel. Returns `:ok` only
  when every write succeeds; partial failures surface as a list of
  `{path, %Modal.Error{}}` pairs so the caller can act on what failed
  without losing what didn't.

      :ok =
        Modal.Filesystem.write_files(sandbox, [
          {"/work/src/main.py", main_src},
          {"/work/tests/test_main.py", test_src},
          {"/work/pyproject.toml", manifest}
        ])

  Each underlying `write_file/3` is ~5 RPCs (open + write + flush +
  close); 10 files sequentially is ~50 sequential round-trips.
  `write_files/2` pipelines the BEAM-side dispatch so 10 client tasks
  fire concurrently, capped by `Modal.Client`'s `:max_concurrency`.

  How much wall-clock that saves depends on how parallel Modal's
  worker is for filesystem ops against the same sandbox — observed
  empirically to be partial-but-not-perfect. The unambiguous wins
  are the API shape (one call instead of N) and the failure
  semantics (per-path errors aggregated).

  Files do not need to share a directory. Parent directories must
  already exist — call `mkdir/3` first if you're materialising a
  fresh tree.

  ## Options

    * `:max_concurrency` — overrides the default (the length of the
      list). Useful when the file count is large and you want to keep
      the per-client RPC queue from saturating against other
      concurrent traffic.
    * `:timeout` — per-write wall-clock ms ceiling (default 60_000).

  ## Errors

  Returns `:ok` when every write returned `:ok`. Returns
  `{:error, errors}` where `errors` is a non-empty
  `[{path, %Modal.Error{}}]` list when any failed. The success/failure
  determination is per-file — there is no "rollback" for files that
  succeeded before another failed.
  """
  @spec write_files(Sandbox.t(), [{String.t(), binary()}], keyword()) ::
          :ok | {:error, [{String.t(), Modal.Error.t()}]}
  def write_files(%Sandbox{} = sb, files, opts \\ []) when is_list(files) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, max(length(files), 1))

    errors =
      files
      |> Task.async_stream(
        fn {path, content} -> {path, write_file(sb, path, content)} end,
        ordered: false,
        max_concurrency: max_concurrency,
        timeout: timeout + 5_000,
        # If a task crashes or times out, Task.async_stream normally
        # returns `{:exit, reason}` with the input lost — we'd see a
        # bare reason with no way to map it back to a path. With
        # `zip_input_on_exit: true` (Elixir 1.14+) the input tuple is
        # zipped back into the exit, so `extract_write_error/1` can
        # recover the failing path for the caller-facing error list.
        zip_input_on_exit: true
      )
      |> Enum.flat_map(&extract_write_error/1)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Like `write_files/3` but raises `%Modal.Error{kind: :filesystem_error}`
  on any failure, with the failing paths embedded in the message and
  the per-path errors in `:metadata.failures`.
  """
  @spec write_files!(Sandbox.t(), [{String.t(), binary()}], keyword()) :: :ok
  def write_files!(%Sandbox{} = sb, files, opts \\ []) do
    case write_files(sb, files, opts) do
      :ok ->
        :ok

      {:error, failures} ->
        paths = Enum.map_join(failures, ", ", fn {p, _} -> p end)

        raise %Modal.Error{
          kind: :filesystem_error,
          message: "write_files failed for #{length(failures)} path(s): #{paths}",
          metadata: %{failures: failures}
        }
    end
  end

  @doc false
  # Exposed via @doc false (not part of the public API) so the
  # path-correlation contract for `:exit` results can be tested
  # without driving a real Task.async_stream crash through Mox.
  def extract_write_error({:ok, {_path, :ok}}), do: []
  def extract_write_error({:ok, {path, {:error, %Modal.Error{} = err}}}), do: [{path, err}]

  # With `zip_input_on_exit: true`, `:exit` carries the original input
  # tuple — recover the path so the caller can correlate the failure.
  # `reason` may be `:timeout` (per Task.async_stream's `:timeout`
  # option) or any other exit reason from the crashing task.
  def extract_write_error({:exit, {{path, _content}, reason}}),
    do: [{path, Modal.Error.task_crashed(:exit, reason)}]

  @doc "List directory. Returns `{:ok, [filename]}`."
  @spec ls(Sandbox.t(), String.t()) :: {:ok, [String.t()]} | {:error, Modal.Error.t()}
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

  @doc "Create directory."
  @spec mkdir(Sandbox.t(), String.t(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def mkdir(%Sandbox{} = sb, path, opts \\ []) do
    oneof =
      {:file_mkdir_request,
       %Modal.Client.ContainerFileMkdirRequest{
         path: path,
         make_parents: Keyword.get(opts, :parents, true)
       }}

    with {:ok, task_id} <- Sandbox.get_task_id(sb),
         {:ok, resp} <- fs_call(sb.client, task_id, oneof),
         {:ok, _} <- fs_wait(sb.client, resp.exec_id) do
      :ok
    end
  end

  @doc "Remove file or directory."
  @spec rm(Sandbox.t(), String.t(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def rm(%Sandbox{} = sb, path, opts \\ []) do
    oneof =
      {:file_rm_request,
       %Modal.Client.ContainerFileRmRequest{
         path: path,
         recursive: Keyword.get(opts, :recursive, false)
       }}

    with {:ok, task_id} <- Sandbox.get_task_id(sb),
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
        {:file_write_request, %Modal.Client.ContainerFileWriteRequest{file_descriptor: fd, data: chunk}}

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
        {:error, Modal.Error.filesystem_error(error.error_message)}

      {:ok, %{data: data}} ->
        {:ok, Enum.reverse(data)}

      {:error, %Modal.Error{} = err} when retries > 0 ->
        if Modal.Error.transient?(err) do
          Process.sleep(Modal.Backoff.delay(retries, fs_retry_delay()))
          fs_wait(client, exec_id, retries - 1)
        else
          {:error, err}
        end

      {:error, err} ->
        {:error, err}
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

  @fs_retry_delay Application.compile_env(:modal, :fs_retry_delay, 1_000)
  defp fs_retry_delay, do: @fs_retry_delay

  defp parse_ls_output(raw) do
    case Jason.decode(raw) do
      {:ok, %{"paths" => paths}} -> {:ok, paths}
      _ -> {:ok, raw |> String.trim() |> String.split("\n", trim: true)}
    end
  end

  @doc false
  @spec chunk_binary(binary(), pos_integer()) :: [binary()]
  def chunk_binary(data, chunk_size \\ @write_chunk_size),
    do: do_chunk(data, chunk_size, 0, [])

  defp do_chunk(data, _size, offset, acc) when offset >= byte_size(data),
    do: Enum.reverse(acc)

  defp do_chunk(data, size, offset, acc) do
    len = min(size, byte_size(data) - offset)
    do_chunk(data, size, offset + len, [binary_part(data, offset, len) | acc])
  end
end
