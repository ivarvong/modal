defmodule Modal.Telemetry do
  @moduledoc """
  Telemetry events emitted by `Modal.*`. Single source of truth — both
  `Modal.RPC` and `Modal.ContainerProcess` instrument through
  `:telemetry.span/3` against these prefixes.

  ## Event families

  Two families, same metadata shape:

  | Prefix                   | What fires it                                          |
  | ------------------------ | ------------------------------------------------------ |
  | `[:modal, :rpc, …]`      | Control-plane RPCs (App, Sandbox, Image, Secret, Volume) |
  | `[:modal, :worker_rpc, …]` | Per-exec RPCs (`task_exec_start` / `stdio_read` / `wait` / `stdin`) |

  Each family emits `:start`, `:stop`, and `:exception`.

  ## Metadata

  **`:start`** (control-plane):

      %{method: atom, kind: :unary | :stream | :stream_reduce}

  **`:start`** (worker-channel):

      %{method: atom}

  **`:stop`** (both families, on success):

      %{method: atom, ..., status: :ok}

  **`:stop`** (both families, on failure):

      %{method: atom, ..., status: :error, error_kind: atom, code: integer | nil}

  `:error_kind` mirrors `Modal.Error`'s `:kind` field (`:grpc`,
  `:network`, `:timeout`, `:overloaded`, `:jwt_expired`, …). `:code` is
  present when the underlying error carries a numeric status (e.g. a
  gRPC status code) and `nil` otherwise. Handlers that don't read these
  keys are unaffected — they're additive.

  **`:exception`** carries `:kind` (`:error | :exit | :throw`), `:reason`,
  and `:stacktrace`, per `:telemetry.span/3`'s default behaviour.

  ## Quick start

  Wire both families into your existing telemetry pipeline:

      :telemetry.attach_many(
        "my-app-modal",
        Modal.Telemetry.events(),
        fn event, measurements, metadata, _config ->
          :telemetry.execute(
            [:my_app | event],
            measurements,
            metadata
          )
        end,
        nil
      )

  Or attach a default development logger that prints each `:stop`:

      Modal.Telemetry.attach_default_logger(level: :debug)

  ## Why two families and not one

  The control-plane goes over `Modal.Client`'s shared gRPC channel to
  `api.modal.com`. The worker channel is per-sandbox: each
  `Modal.ContainerProcess` opens its own gRPC connection directly to
  the task's worker. Operators almost always want to slice the two
  separately — the control-plane is the SaaS dependency, the worker
  channel is "how fast is *my* compute talking back to me." Same shape,
  same handler if you want it to be, but different prefixes so you can
  graph them separately without a metadata predicate.

  ## Stability

  Event names, metadata key set, and the shape of `:status` /
  `:error_kind` / `:code` are SemVer-protected. New keys may be added
  to metadata as additive (existing handlers continue to work);
  renaming or removing a key is a major-version change.
  """

  @rpc_start [:modal, :rpc, :start]
  @rpc_stop [:modal, :rpc, :stop]
  @rpc_exception [:modal, :rpc, :exception]
  @worker_rpc_start [:modal, :worker_rpc, :start]
  @worker_rpc_stop [:modal, :worker_rpc, :stop]
  @worker_rpc_exception [:modal, :worker_rpc, :exception]

  @events [
    @rpc_start,
    @rpc_stop,
    @rpc_exception,
    @worker_rpc_start,
    @worker_rpc_stop,
    @worker_rpc_exception
  ]

  @doc """
  Every event this library emits. Pass to `:telemetry.attach_many/4`.
  """
  @spec events() :: [[atom()], ...]
  def events, do: @events

  @doc """
  Attach a Logger handler that prints each `:stop` event at the given
  level (default `:debug`). Convenient for development; for production
  metrics, wire `events/0` into your own handler instead.

  ## Options

    * `:level` — `:debug | :info | :warning | :error` (default `:debug`)
    * `:handler_id` — handler id, useful if you want to detach later
      (default `"modal-default-logger"`)

  ## Example

      iex> Modal.Telemetry.attach_default_logger()
      :ok
      iex> Modal.Telemetry.attach_default_logger(level: :info, handler_id: "my-id")
      :ok
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    handler_id = Keyword.get(opts, :handler_id, "modal-default-logger")

    :telemetry.attach_many(
      handler_id,
      [@rpc_stop, @worker_rpc_stop],
      &__MODULE__.handle_log_event/4,
      %{level: level}
    )
  end

  @doc """
  Detach a handler attached via `attach_default_logger/1`.
  """
  @spec detach_default_logger(String.t()) :: :ok | {:error, :not_found}
  def detach_default_logger(handler_id \\ "modal-default-logger") do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_log_event([:modal, family, :stop], %{duration: dur_native}, metadata, %{level: level}) do
    ms = System.convert_time_unit(dur_native, :native, :millisecond)
    method = metadata[:method]
    status = metadata[:status]

    line =
      case status do
        :ok ->
          "[modal] #{family} #{method} #{ms}ms ok"

        :error ->
          kind = metadata[:error_kind] || :unknown
          code = if metadata[:code], do: " code=#{metadata[:code]}", else: ""
          "[modal] #{family} #{method} #{ms}ms error kind=#{kind}#{code}"
      end

    require Logger
    Logger.log(level, line)
  end
end
