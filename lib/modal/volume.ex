defmodule Modal.Volume do
  @moduledoc """
  Modal Volume — persistent storage that can be mounted into a sandbox at
  a path. Holds files across sandbox lifetimes and across machines.

  Two distinct surfaces in this module:

    * **Lifecycle + content RPCs** — `get_or_create/3`, `delete/2`,
      `put_file/4`. Manage volumes and seed their contents from the
      orchestrator.
    * **The `%Modal.Volume{}` struct** — a typed mount handle passed
      to `Modal.Sandbox.create/2` via `:volumes`. Holds the volume id,
      the in-container path, and a `:read_only` flag.

  ## Example — seed-from-orchestrator + read-only mount

      {:ok, vol_id} = Modal.Volume.get_or_create(client, "my-input-data")

      # Push a config from outside (no sandbox needed for the write):
      :ok = Modal.Volume.put_file(client, vol_id, "config.json", config_json)

      # Mount it read-only into every worker sandbox; they all see
      # the same committed contents.
      mount = %Modal.Volume{id: vol_id, path: "/data", read_only: true}
      sandbox = Modal.Sandbox.create!(client, app: app, volumes: [mount], ...)
      {:ok, "..."} = Modal.Filesystem.read_file(sandbox, "/data/config.json")

  ## Cross-sandbox WRITES — the commit/reload contract

  Modal's volume model is "writes from a mounted container are
  worker-local until *commit* fires; another container sees them only
  after *reload*." Both `VolumeCommit` and `VolumeReload` are
  authenticated to a specific running container — they can't be driven
  from the orchestrator (the API rejects them with `"can only be
  called on a mounted volume inside a container"`).

  In Modal's reference SDKs those calls work because the SDK is
  running *inside* the container. This library is normally the
  *orchestrator* (outside the container), where `commit/2` / `reload/2`
  are rejected with `FAILED_PRECONDITION` — so most callers never touch
  them. They are still exposed (see `commit/2` / `reload/2`, each with
  the caveat documented) for the one context that does work: an Elixir
  node running *inside* a Modal Sandbox with the volume mounted.

  Three patterns work from where this library lives:

    * **Single-sandbox volume** — mount, write via `Modal.Filesystem`,
      read, terminate. The container-local view is always consistent.
    * **Seed-from-orchestrator** (recommended for read-only inputs):
      `put_file/4` writes the file from the orchestrator straight
      into the volume's durable storage; every sandbox that mounts
      the volume afterwards sees it on first read. No commit needed.
    * **Container-side commit** — install Modal's Python SDK in your
      container image and exec a small shim to call
      `volume.commit()` / `volume.reload()`. Heavier; only needed
      when writes have to flow OUT of a running sandbox to others.
  """

  alias Modal.RPC

  @enforce_keys [:id, :path]
  defstruct [:id, :path, read_only: false]

  @type t :: %__MODULE__{
          id: String.t(),
          path: String.t(),
          read_only: boolean()
        }

  # ── Lifecycle RPCs ──────────────────────────────────────────────

  @doc """
  Look up a volume by name, creating it if it doesn't exist. Returns
  `{:ok, volume_id}`.

  Volumes are scoped to the environment; the same `:deployment_name`
  resolves to the same `volume_id` across processes and across runs of
  the same client. Mirrors Python's
  `Volume.from_name(name, create_if_missing=True)`.

  ## Options

    * `:environment_name` — non-default environment (default `""` =
      account default).
    * `:version` — `:v2` (default, the modern content-addressed
      filesystem) or `:v1` (legacy; only supported for interop with
      existing v1 volumes). `:v2` is required to use `put_file/5`
      from the orchestrator — v1 only supports container-side writes
      via Modal's Python SDK.
  """
  @spec get_or_create(GenServer.server(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Modal.Error.t()}
  def get_or_create(client, deployment_name, opts \\ []) when is_binary(deployment_name) do
    request = %Modal.Client.VolumeGetOrCreateRequest{
      deployment_name: deployment_name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING,
      version: fs_version(Keyword.get(opts, :version, :v2))
    }

    with {:ok, resp} <- RPC.call(client, :VolumeGetOrCreate, request) do
      {:ok, resp.volume_id}
    end
  end

  defp fs_version(:v1), do: :VOLUME_FS_VERSION_V1
  defp fs_version(:v2), do: :VOLUME_FS_VERSION_V2

  defp fs_version(other),
    do: raise(ArgumentError, ":version must be :v1 or :v2, got #{inspect(other)}")

  @doc "Like `get_or_create/3` but raises on error and returns the bare id."
  @spec get_or_create!(GenServer.server(), String.t(), keyword()) :: String.t()
  def get_or_create!(client, deployment_name, opts \\ []) do
    case get_or_create(client, deployment_name, opts) do
      {:ok, id} -> id
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc "Delete a volume by id. Returns `:ok` whether or not the volume existed."
  @spec delete(GenServer.server(), String.t()) :: :ok | {:error, Modal.Error.t()}
  def delete(client, volume_id) when is_binary(volume_id) do
    request = %Modal.Client.VolumeDeleteRequest{volume_id: volume_id}
    with {:ok, _} <- RPC.call(client, :VolumeDelete, request), do: :ok
  end

  # VolumeList is server-paginated (≤100 per page, newest-first); we walk
  # every page so the caller sees one flat list. Each page filters to
  # volumes created strictly before a cursor, so the first page starts at
  # "now" and each subsequent page resumes from the oldest item we've seen.
  @list_page_size 100

  @doc """
  List named volumes in an environment, newest first. Returns
  `{:ok, [map]}`, one map per volume with `:volume_id`, `:name`, and
  `:created_at` (a Unix timestamp, float seconds).

      {:ok, vols} = Modal.Volume.list(client)
      stale = Enum.filter(vols, &String.starts_with?(&1.name, "scratch-"))
      Enum.each(stale, &Modal.Volume.delete(client, &1.volume_id))

  Pagination is handled internally — the result is the full list unless
  capped with `:max_objects`.

  ## Options

    * `:environment_name` — non-default environment (default `""`).
    * `:max_objects` — cap the number returned (default: all). Must be
      non-negative.
    * `:created_before` — only volumes created before this Unix timestamp
      (float seconds). Defaults to the current time.
  """
  @spec list(GenServer.server(), keyword()) :: {:ok, [map()]} | {:error, Modal.Error.t()}
  def list(client, opts \\ []) do
    env = Keyword.get(opts, :environment_name, "")
    max = Keyword.get(opts, :max_objects)
    before = Keyword.get(opts, :created_before, System.os_time(:millisecond) / 1000.0)

    if is_integer(max) and max < 0 do
      {:error, Modal.Error.validation_msg(":max_objects cannot be negative, got #{max}")}
    else
      list_pages(client, env, max, before, [])
    end
  end

  defp list_pages(client, env, max, before, acc) do
    page_size =
      if is_integer(max), do: min(@list_page_size, max - length(acc)), else: @list_page_size

    request = %Modal.Client.VolumeListRequest{
      environment_name: env,
      pagination: %Modal.Client.ListPagination{max_objects: page_size, created_before: before}
    }

    with {:ok, resp} <- RPC.call(client, :VolumeList, request) do
      acc = acc ++ Enum.map(resp.items, &volume_list_item_to_map/1)
      done? = length(resp.items) < page_size or (is_integer(max) and length(acc) >= max)

      cond do
        done? and is_integer(max) ->
          {:ok, Enum.take(acc, max)}

        done? ->
          {:ok, acc}

        true ->
          list_pages(
            client,
            env,
            max,
            List.last(resp.items).metadata.creation_info.created_at,
            acc
          )
      end
    end
  end

  defp volume_list_item_to_map(item) do
    %{
      volume_id: item.volume_id,
      name: item.metadata.name,
      created_at: item.metadata.creation_info.created_at
    }
  end

  # ── put_file/4 — orchestrator-side blob upload ──────────────────

  # Modal's content-addressed block size for VolumePutFiles2. The
  # client computes one SHA256 per 8MiB block; the server returns
  # presigned PUT URLs for blocks it doesn't already have.
  @block_size 8 * 1024 * 1024

  @doc """
  Write a file into a Modal volume from the orchestrator (no sandbox
  required on the writer side).

  The file's content is uploaded directly to Modal's content-addressed
  block store; sandboxes that mount the volume afterwards see the
  file on first read with no commit/reload dance needed. This is the
  primary path for "seed a volume with input data, then fan out N
  read-only consumers."

  ## Example

      :ok = Modal.Volume.put_file(client, "vo-abc", "config.json", body)
      :ok = Modal.Volume.put_file(client, "vo-abc", "data/input.csv", csv)

      sandbox =
        Modal.Sandbox.create!(client,
          app: app,
          volumes: [%Modal.Volume{id: "vo-abc", path: "/data", read_only: true}],
          ...
        )

      {:ok, ^body} = Modal.Filesystem.read_file(sandbox, "/data/config.json")

  ## Protocol

  Two `VolumePutFiles2` RPCs plus one HTTPS PUT per call (when the
  server doesn't already have the block; an existing block is a
  single-RPC no-op — the deduplication is content-addressed).

  1. First call sends the file's metadata + block SHA256s.
  2. Server returns missing-block presigned PUT URLs, if any.
  3. Client uploads each missing block via HTTPS PUT.
  4. Second call sends the same metadata with PUT-response bodies
     attached so the server can validate.

  Re-uploading the same content is idempotent and effectively free
  on the wire (one RPC, no HTTP PUT).

  ## Options

    * `:mode` — Unix mode bits for the file (default `0o644`).
    * `:overwrite` — boolean (default `true`). When `false`, the
      server refuses to overwrite an existing file at the same path
      and returns `%Modal.Error{kind: :grpc, code: 6}` (ALREADY_EXISTS).
    * `:timeout` — HTTP PUT wall-clock ms (default `60_000`).

  ## Limitations (v1)

  Currently supports single-block files (≤ 8 MiB). Larger files
  return `%Modal.Error{kind: :validation}`. Multi-block support is
  tracked — until then, large blobs need to land via a container-side
  Python shim or be split by the caller into ≤8 MiB chunks.
  """
  @spec put_file(GenServer.server(), String.t(), String.t(), binary(), keyword()) ::
          :ok | {:error, Modal.Error.t()}
  def put_file(client, volume_id, remote_path, content, opts \\ [])
      when is_binary(volume_id) and is_binary(remote_path) and is_binary(content) do
    cond do
      remote_path == "" or String.ends_with?(remote_path, "/") ->
        {:error,
         Modal.Error.validation_msg(
           "remote_path must refer to a file, not a directory (got #{inspect(remote_path)})"
         )}

      byte_size(content) > @block_size ->
        {:error,
         Modal.Error.validation_msg(
           "Modal.Volume.put_file/5 currently supports files ≤ #{@block_size} bytes (8 MiB); " <>
             "got #{byte_size(content)} bytes. Multi-block upload is tracked as a follow-up."
         )}

      true ->
        do_put_file(client, volume_id, remote_path, content, opts)
    end
  end

  @doc "Like `put_file/5` but raises on error."
  @spec put_file!(GenServer.server(), String.t(), String.t(), binary(), keyword()) :: :ok
  def put_file!(client, volume_id, remote_path, content, opts \\ []) do
    case put_file(client, volume_id, remote_path, content, opts) do
      :ok -> :ok
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  defp do_put_file(client, volume_id, remote_path, content, opts) do
    sha = :crypto.hash(:sha256, content)
    mode = Keyword.get(opts, :mode, 0o644)
    overwrite? = Keyword.get(opts, :overwrite, true)
    put_timeout = Keyword.get(opts, :timeout, 60_000)

    base_request = fn block_put_response ->
      %Modal.Client.VolumePutFiles2Request{
        volume_id: volume_id,
        disallow_overwrite_existing_files: not overwrite?,
        files: [
          %Modal.Client.VolumePutFiles2Request.File{
            path: remote_path,
            size: byte_size(content),
            mode: mode,
            blocks: [
              %Modal.Client.VolumePutFiles2Request.Block{
                contents_sha256: sha,
                put_response: block_put_response
              }
            ]
          }
        ]
      }
    end

    # Phase 1: probe — server tells us if the block already exists.
    with {:ok, resp} <- RPC.call(client, :VolumePutFiles2, base_request.(nil)) do
      handle_probe_response(resp.missing_blocks, client, base_request, content, put_timeout)
    end
  end

  defp handle_probe_response([], _client, _base_request, _content, _timeout) do
    # Content already in the block store. Single-RPC no-op.
    :ok
  end

  defp handle_probe_response([missing], client, base_request, content, put_timeout) do
    # Phase 2: PUT the block bytes; phase 3: confirm.
    with {:ok, put_response} <- http_put_block(missing.put_url, content, put_timeout),
         {:ok, %{missing_blocks: []}} <-
           RPC.call(client, :VolumePutFiles2, base_request.(put_response)) do
      :ok
    else
      {:ok, %{missing_blocks: still_missing}} ->
        {:error,
         Modal.Error.unexpected(
           "server still reports #{length(still_missing)} missing blocks after upload " <>
             "(SHA mismatch? Network corruption?)"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp handle_probe_response(many, _client, _base_request, _content, _timeout) do
    # We sent one block; server reported more than one missing.
    # Defensive — shouldn't happen for a single-block file.
    {:error,
     Modal.Error.unexpected(
       "expected ≤1 missing block for a single-block file, got #{length(many)}"
     )}
  end

  # HTTP PUT via Req. Block-store URLs are presigned S3-style; the
  # storage backend's PUT response gets ferried back to the second
  # VolumePutFiles2 call as `Block.put_response` bytes, so we ask Req
  # to leave the body undecoded.
  defp http_put_block(put_url, content, timeout_ms) do
    case Req.put(put_url,
           body: content,
           headers: [{"content-type", "application/octet-stream"}],
           receive_timeout: timeout_ms,
           connect_options: [timeout: 10_000],
           decode_body: false,
           # `retry: false` because the surrounding `VolumePutFiles2`
           # protocol is content-addressed and idempotent at its own
           # level; an HTTP-level retry would duplicate work that the
           # outer protocol already handles cheaply.
           retry: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         Modal.Error.network({:blob_upload, status, body |> to_string() |> String.slice(0, 512)})}

      {:error, reason} ->
        {:error, Modal.Error.network({:blob_upload, reason})}
    end
  end

  # ── Read APIs ───────────────────────────────────────────────────

  @doc """
  List files in a volume (or in a subpath of it).

  ## Options

    * `:path` — directory to list. Defaults to `"/"` (volume root).
    * `:recursive` — `true` to descend; default `false`.
    * `:max_entries` — cap on returned entries. Modal defaults if
      unset.

  Returns `{:ok, [%{path:, type:, size:, mtime:}, ...]}` — each
  entry's `:type` is `:file | :directory | :symlink | :fifo |
  :socket`. Returns `{:error, %Modal.Error{}}` on RPC failure.
  """
  @spec list_files(GenServer.server(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, Modal.Error.t()}
  def list_files(client, volume_id, opts \\ []) when is_binary(volume_id) do
    # VolumeListFiles2 is the v2-volume endpoint and is server-
    # streaming (entries arrive in batches as the listing walks the
    # tree). The legacy VolumeListFiles returns INVALID_ARGUMENT
    # "Operation not supported for v2 volumes" on the current Modal
    # API — caught live.
    request = %Modal.Client.VolumeListFiles2Request{
      volume_id: volume_id,
      path: Keyword.get(opts, :path, "/"),
      recursive: Keyword.get(opts, :recursive, false),
      max_entries: Keyword.get(opts, :max_entries)
    }

    with {:ok, responses} <- RPC.stream(client, :VolumeListFiles2, request) do
      entries =
        responses
        |> Enum.flat_map(& &1.entries)
        |> Enum.map(&file_entry_to_map/1)

      {:ok, entries}
    end
  end

  @doc """
  Read a file from a volume into memory.

  Modal serves the bytes via a presigned URL (content-addressed
  block store) — for small files this fits in one round-trip; for
  larger ones the response carries multiple `get_urls` we
  concatenate transparently.

  Returns `{:ok, binary}` or `{:error, %Modal.Error{}}`. For files
  missing from the volume, the error is `:grpc` with code 5
  (NOT_FOUND).

  ## Options

    * `:timeout` — per-block HTTP timeout in ms (default 60_000).
  """
  @spec get_file(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Modal.Error.t()}
  def get_file(client, volume_id, remote_path, opts \\ [])
      when is_binary(volume_id) and is_binary(remote_path) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    request = %Modal.Client.VolumeGetFile2Request{
      volume_id: volume_id,
      path: remote_path,
      start: 0,
      len: 0
    }

    with {:ok, resp} <- RPC.call(client, :VolumeGetFile2, request) do
      fetch_blocks(resp.get_urls, timeout)
    end
  end

  @doc "Like `get_file/4` but raises on error."
  @spec get_file!(GenServer.server(), String.t(), String.t(), keyword()) :: binary()
  def get_file!(client, volume_id, remote_path, opts \\ []) do
    case get_file(client, volume_id, remote_path, opts) do
      {:ok, content} -> content
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Tell the server that any in-flight writes on this volume should
  be made visible to the *current* mounted container.

  ## Worker-side only

  Modal's API rejects `VolumeReload` from outside a function
  container — it returns `gRPC FAILED_PRECONDITION (9): "reload()
  can only be called from within a running function"`. The intended
  caller is a long-running worker that wants to see writes
  another process made; from an Elixir orchestrator (no Modal
  mount), there's nothing to reload.

  This wrapper exists for the case where you're running an Elixir
  agent *inside* a Modal Sandbox (via `Modal.Sandbox.exec` of a
  release) that mounted the volume — in that context, `reload/2`
  works as expected.
  """
  @spec reload(GenServer.server(), String.t()) :: :ok | {:error, Modal.Error.t()}
  def reload(client, volume_id) when is_binary(volume_id) do
    request = %Modal.Client.VolumeReloadRequest{volume_id: volume_id}
    with {:ok, _} <- RPC.call(client, :VolumeReload, request), do: :ok
  end

  @doc """
  Commit pending writes on this volume from inside a container that
  has mounted it. Forces an immediate checkpoint of any buffered
  writes the worker has made.

  ## Worker-side only

  Like `reload/2`, this is rejected from the orchestrator side with
  `gRPC FAILED_PRECONDITION (9): "commit() can only be called on a
  mounted volume inside a container"`. For orchestrator-side writes,
  `put_file/5` already lands the data durably without a commit —
  Modal's block store is content-addressed.
  """
  @spec commit(GenServer.server(), String.t()) :: :ok | {:error, Modal.Error.t()}
  def commit(client, volume_id) when is_binary(volume_id) do
    request = %Modal.Client.VolumeCommitRequest{volume_id: volume_id}
    with {:ok, _} <- RPC.call(client, :VolumeCommit, request), do: :ok
  end

  # ── Read helpers ────────────────────────────────────────────────

  defp file_entry_to_map(%Modal.Client.FileEntry{} = e) do
    %{path: e.path, type: file_type(e.type), size: e.size, mtime: e.mtime}
  end

  defp file_type(:FILE), do: :file
  defp file_type(:DIRECTORY), do: :directory
  defp file_type(:SYMLINK), do: :symlink
  defp file_type(:FIFO), do: :fifo
  defp file_type(:SOCKET), do: :socket
  defp file_type(_), do: :unknown

  defp fetch_blocks([], _timeout), do: {:ok, ""}

  defp fetch_blocks(urls, timeout) do
    # Concatenate the bytes of each presigned block URL in order.
    # For single-block files (the common case) this is one GET.
    Enum.reduce_while(urls, {:ok, []}, fn url, {:ok, acc} ->
      case Req.get(url, receive_timeout: timeout, decode_body: false, retry: false) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:cont, {:ok, [body | acc]}}

        {:ok, %Req.Response{status: status}} ->
          {:halt, {:error, Modal.Error.network({:blob_download, status})}}

        {:error, reason} ->
          {:halt, {:error, Modal.Error.network({:blob_download, reason})}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}
      err -> err
    end
  end
end
