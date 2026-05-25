defmodule Modal.Image do
  @moduledoc """
  Modal container image management — build (or fetch from cache) an
  image from Dockerfile commands, then attach it to a sandbox via
  `Modal.Sandbox.create/2`'s `:image_id`.

      {:ok, image_id, status} =
        Modal.Image.get_or_create(client, [
          "FROM python:3.14-slim",
          "RUN pip install --no-cache-dir requests"
        ], app: app)

      # status is :cached when the content-addressed layer stack
      # matched an existing image, :built when a fresh build ran.

  ## Build logs

  Pass `:on_log` to stream the build's stdout/stderr to wherever you
  want — chunks are byte-oriented, so wrap with `line_buffered/1` for
  one invocation per `\\n`-terminated line (the typical case for
  prefixing or per-line logging):

      Modal.Image.get_or_create(client, layers,
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts("  | " <> line) end)
      )

  On a cache hit, `:on_log` fires zero times. On failure, the full
  build log is preserved in `%Modal.Error{kind: :image_build_failed,
  metadata: %{logs: …}}` regardless of whether `:on_log` was set.

  ## Caching

  Images are content-addressed by the full layer stack. Two
  `get_or_create/3` calls with identical layer lists return the same
  `image_id` and `status: :cached` — the second call is a single
  round-trip RPC, no build. This is the load-bearing primitive for
  every "fast per-request sandbox" pattern in `scripts/`.
  """

  require Logger
  alias Modal.RPC

  @doc """
  Get or create a container image from Dockerfile commands.

  Pass the owning app via `app: %Modal.App{}` (recommended — see
  `Modal.App.lookup/3`) or `app_id: "ap-..."`. Calling with neither is
  permitted for backwards compatibility (the build is then scoped to no
  app), but the resulting image cannot be attached to a sandbox in
  another app.

  Waits for the image build to complete. Returns `{:ok, image_id, status}` where
  `status` is `:cached` if the image already existed or `:built` if it was just
  built from scratch.

  Note: this function returns a 3-tuple. Use `{:ok, image_id, _status}` when
  only the image ID is needed in a `with` chain.

  ## Options

    * `:app` / `:app_id` — owning app (see above).
    * `:on_log` — 1-arity callback invoked for each non-empty `task_logs`
      chunk emitted during the build. Use this to stream build output
      somewhere visible (`on_log: &IO.write/1` for stdout). The callback
      receives a **binary chunk** — chunks are byte-oriented and may
      contain partial lines or multiple newlines; the boundaries reflect
      whatever Modal's worker happens to flush. If you want one
      invocation per complete line (typical for prefixing or per-line
      logging), wrap the callback with `Modal.Image.line_buffered/1`.
      Default: no-op.

  ## Failures

  When the build returns a non-success status, the returned
  `%Modal.Error{kind: :image_build_failed}` carries the full build log
  in `:metadata.logs` (whether or not `:on_log` was set) so callers
  always have the diagnostic available. The exception message includes
  the stderr-style tail (last few lines).

      case Modal.Image.get_or_create(client, dockerfile, app: app, on_log: &IO.write/1) do
        {:ok, image_id, _status} ->
          ...

        {:error, %Modal.Error{kind: :image_build_failed, metadata: %{logs: logs}}} ->
          File.write!("build.log", logs)
      end
  """
  @spec get_or_create(GenServer.server(), [String.t()], keyword()) ::
          {:ok, String.t(), :cached | :built} | {:error, Modal.Error.t()}
  def get_or_create(client, dockerfile_commands, opts \\ []) do
    with {:ok, app_id} <- resolve_app_id_or_blank(opts),
         {:ok, on_log} <- validate_on_log(Keyword.get(opts, :on_log, fn _chunk -> :ok end)) do
      image = %Modal.Client.Image{dockerfile_commands: dockerfile_commands}
      request = %Modal.Client.ImageGetOrCreateRequest{image: image, app_id: app_id}

      with {:ok, resp} <- RPC.call(client, :ImageGetOrCreate, request),
           {:ok, status} <- await_build(client, resp.image_id, on_log) do
        {:ok, resp.image_id, status}
      end
    end
  end

  defp validate_on_log(fun) when is_function(fun, 1), do: {:ok, fun}

  defp validate_on_log(other),
    do:
      {:error,
       Modal.Error.validation_msg(
         "Modal.Image.get_or_create/3 :on_log must be a 1-arity function, got #{inspect(other)}"
       )}

  @doc """
  Adapter that turns an `:on_log` byte-chunk callback into a
  line-at-a-time callback. See `Modal.ContainerProcess.line_buffered/1`
  for the full contract and rationale — same implementation, exposed
  here so `Modal.Image.get_or_create/3` callers can spell it locally.

      Modal.Image.get_or_create(client, dockerfile,
        app: app,
        on_log: Modal.Image.line_buffered(fn line ->
          Logger.info("[build] " <> line)
        end)
      )
  """
  @spec line_buffered((String.t() -> any())) :: (binary() -> :ok)
  defdelegate line_buffered(line_callback), to: Modal.ContainerProcess

  # Image is the one module where missing `:app`/`:app_id` is allowed —
  # the image build itself works without an app, and Modal.App.resolve_app_id/1
  # treats absence as an error. We translate that one error back to an
  # empty string here so the existing "no app" callers keep working.
  defp resolve_app_id_or_blank(opts) do
    case Modal.App.resolve_app_id(opts) do
      {:ok, app_id, _opts} ->
        {:ok, app_id}

      {:error, %Modal.Error{kind: :validation, message: msg}} ->
        if msg =~ "missing app" do
          {:ok, ""}
        else
          {:error, %Modal.Error{kind: :validation, message: msg}}
        end
    end
  end

  # Streaming consumer for the ImageJoinStreaming RPC. Folds log chunks
  # into the accumulator (so the failure path can hand callers a full
  # log) and invokes `:on_log` per chunk for live streaming. Halts on
  # the first non-success result status; otherwise runs to completion
  # and reports `:built` vs. `:cached` based on whether any task_logs
  # were observed (cached builds emit none).
  defp await_build(client, image_id, on_log) do
    request = %Modal.Client.ImageJoinStreamingRequest{
      image_id: image_id,
      timeout: 1800.0,
      include_logs_for_finished: false
    }

    initial = %{log_chunks: [], had_logs: false, failure: nil}
    reducer = build_reducer(on_log)

    case RPC.stream_reduce(client, :ImageJoinStreaming, request, initial, reducer, 1_820_000) do
      {:ok, %{failure: nil, had_logs: had_logs}} ->
        {:ok, if(had_logs, do: :built, else: :cached)}

      {:ok, %{failure: status, log_chunks: chunks}} ->
        logs = chunks |> Enum.reverse() |> IO.iodata_to_binary()
        Logger.error("[modal] image build failed: #{status}")
        {:error, Modal.Error.image_build_failed(status, logs)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Build a stream-reduce reducer that:
  #   1. Streams every non-empty task_log chunk through `:on_log` for
  #      live output (caller chooses where it goes).
  #   2. Accumulates chunks as iodata in reverse for the failure-path
  #      buffer (cheap append, one O(n) flatten on the error branch).
  #   3. Halts on the first non-success result status so the caller
  #      sees the failure promptly without draining the rest of the
  #      stream.
  defp build_reducer(on_log) do
    fn resp, acc ->
      acc = ingest_logs(resp.task_logs, acc, on_log)

      if failure_status?(resp.result) do
        {:halt, %{acc | failure: resp.result.status}}
      else
        {:cont, acc}
      end
    end
  end

  defp ingest_logs(task_logs, acc, on_log) do
    Enum.reduce(task_logs, acc, &absorb_log_entry(&1, &2, on_log))
  end

  defp absorb_log_entry(%{data: ""}, acc, _on_log), do: acc

  defp absorb_log_entry(%{data: data}, acc, on_log) when is_binary(data) do
    on_log.(data)
    %{acc | log_chunks: [data | acc.log_chunks], had_logs: true}
  end

  defp absorb_log_entry(_log, acc, _on_log), do: acc

  defp failure_status?(nil), do: false

  defp failure_status?(%{status: status}),
    do: status not in [:GENERIC_STATUS_UNSPECIFIED, :GENERIC_STATUS_SUCCESS]
end
