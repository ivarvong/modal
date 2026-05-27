defmodule Modal.Sandbox do
  @moduledoc """
  Modal Sandbox lifecycle.

      sandbox = Modal.Sandbox.create!(client, app_id: app_id, cmd: ["sleep", "infinity"])

      {:ok, proc}   = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      {:ok, stream} = Modal.ContainerProcess.stream(proc)
      Enum.each(stream, &IO.write/1)
      Modal.ContainerProcess.exit_code(proc)  #=> {:ok, 0}

      Modal.Sandbox.terminate(sandbox)
  """

  alias Modal.RPC

  require Logger

  defstruct [:id, :name, :client, :monitor_pid]

  @type t :: %__MODULE__{
          id: String.t(),
          # The name passed to `from_name/3`, or `nil` for sandboxes
          # created via `create/2`. Carried for debugging — server is
          # the source of truth for whether the name is still valid.
          name: String.t() | nil,
          client: GenServer.server(),
          # PID of a per-sandbox monitor process spawned when
          # `:terminate_on_caller_exit` is true. `nil` otherwise.
          # Internal — callers should not depend on this field.
          monitor_pid: pid() | nil
        }

  # GRPC status code 4 = DEADLINE_EXCEEDED — how SandboxWait(timeout: 0)
  # signals "still running" rather than an actual error.
  @grpc_deadline_exceeded 4

  @create_opts [
    app_id: [type: :string, required: true],
    cmd: [type: {:list, :string}, default: []],
    # The image to boot from. Required — Modal sandboxes have no
    # useful "no image" mode, and the server's "" response is opaque;
    # raising at the option-validation layer surfaces the missing field
    # clearly. Get the id from `Modal.Image.get_or_create/3`.
    image_id: [type: :string, required: true],
    # Sandbox wall-clock timeout in seconds. Matches the proto field name.
    timeout_secs: [type: :pos_integer, default: 300],
    # Idle timeout in seconds.
    #   * `nil` (default) — leave unset on the wire. Modal applies its
    #     server-side default, which is "no idle timeout" (the sandbox
    #     stays up until `:timeout_secs` fires or the caller terminates).
    #   * `0` — same as `nil` (treated as "disabled"). This is a
    #     deliberate departure from the proto, where `0` on the wire
    #     means "die immediately when the entrypoint goes idle" — a
    #     footgun for callers who omit the field and end up with an
    #     instant-death sandbox.
    #   * positive integer — terminate after N idle seconds.
    idle_timeout_secs: [type: {:or, [nil, :non_neg_integer]}],
    name: [type: :string, default: ""],
    workdir: [type: :string, default: "/root"],
    memory_mb: [type: :non_neg_integer, default: 0],
    # Fractional CPU cores, matching Python SDK convention (e.g. 0.5, 1.0, 2.0).
    # Accepts integer or float; converted to millicores via `trunc/1`, so
    # `cpu: 1.2345` becomes `1234` millicores (the sub-millicore fraction
    # is dropped silently). Prefer `:cpu_millis` for callers that need to
    # express an exact integer millicore count without surprise truncation.
    cpu: [type: {:or, [:float, :integer]}, default: 0],
    # Exact CPU millicores. Mutually exclusive with `:cpu` — passing both
    # is a validation error. 1000 = one full core; 2500 = 2.5 cores.
    cpu_millis: [type: :non_neg_integer],
    gpu: [type: :string],
    gpu_count: [type: :pos_integer, default: 1],
    disk_mb: [type: :non_neg_integer, default: 0],
    ports: [type: {:list, :pos_integer}, default: []],
    # `Modal.Volume` structs (recommended) or plain maps with `:id`, `:path`,
    # and optional `:read_only`. NimbleOptions can't express "list of struct OR
    # list of map" without escaping to `:any`, so we validate the element shape
    # in `build_volume/1` instead — a misshaped entry raises a clear
    # ArgumentError at request-build time rather than silently sending nils.
    volumes: [type: {:list, :any}, default: []],
    # Accepts a single region string or a list of strings.
    regions: [type: {:or, [:string, {:list, :string}]}],
    secret_ids: [type: {:list, :string}, default: []],
    snapshot: [type: :boolean, default: false],
    block_network: [type: :boolean, default: false],
    # First-class egress control. Three shapes:
    #
    #   * `:open` — no restrictions (Modal default; same as omitting).
    #   * `:blocked` — deny all egress (equivalent to `block_network: true`,
    #     but expressed via the modern `NetworkAccess` proto field).
    #   * `{:allowlist, [cidr, ...]}` — deny everything except the listed
    #     CIDR ranges. Use `Modal.Sandbox.github_cidrs/0` to populate
    #     from GitHub's published IP list.
    #
    # CIDR allowlisting works cleanly for endpoints with stable IPs
    # (GitHub, many cloud-provider control planes). It's brittle for
    # SaaS endpoints fronted by CDNs (Anthropic via CloudFront,
    # OpenAI, etc.) — for those, set `:blocked` and run an in-container
    # forward proxy (tinyproxy/squid) that does hostname allowlisting.
    network_access: [
      type: {:custom, __MODULE__, :validate_network_access, []}
    ],
    proxy_id: [
      type: :string,
      doc: """
      Attach a `Modal.Proxy` for outbound traffic — the sandbox's
      egress routes through the proxy's static IP. Use when the
      *target* service needs to allowlist your source IP (the
      inverse of `:network_access`).

          {:ok, proxy} = Modal.Proxy.get(client, "customer-db")
          Modal.Sandbox.create(client, ..., proxy_id: proxy.id)
      """
    ],
    cloud_bucket_mounts: [
      type: {:list, :any},
      default: [],
      doc: """
      List of `%Modal.CloudBucket{}` structs to mount inside the
      sandbox. S3 / R2 / GCS buckets appear as filesystem paths —
      no upload step, no Volume sync.

          %Modal.CloudBucket{
            bucket_name: "training-data",
            type: :s3,
            mount_path: "/data",
            secret_id: aws_secret,
            read_only: true
          }
      """
    ],
    i6pn: [
      type: :boolean,
      default: false,
      doc: """
      Enable Modal's i6pn (internal IPv6 network) for this sandbox.
      Containers in the same app reach each other on a private IPv6
      mesh — the wire for distributed training, parameter servers,
      or any peer-to-peer pattern between Modal containers. Each
      container gets an i6pn address discoverable via Modal's
      runtime (typically `os.environ["MODAL_I6PN_ADDR"]` on the
      Python side).
      """
    ],
    verbose: [type: :boolean, default: false],
    # Auto-terminate the sandbox if the calling process exits before
    # `Modal.Sandbox.terminate/1` is called. Closes the silent-money-leak
    # footgun where a Phoenix request handler dies mid-flight and
    # leaves the sandbox running.
    #
    # Accepted values:
    #
    #   * `false` (default) — no watchdog (caller owns the lifetime,
    #     leak risk).
    #   * `true` — watchdog enabled; logs `Logger.warning` when it
    #     fires. Right when an unexpected caller-exit IS the bug you
    #     want to know about.
    #   * `:silent` — watchdog enabled; no log. Right when caller-exit
    #     is the expected cleanup path (e.g., speculative cancellation,
    #     `Task.async_stream` racing N candidates and dropping the
    #     losers).
    #   * `:debug | :info | :warning | :error` — watchdog enabled;
    #     logs at the given level when it fires.
    terminate_on_caller_exit: [
      type: {:in, [false, true, :silent, :debug, :info, :warning, :error]},
      default: false
    ]
  ]

  # ── Lifecycle ───────────────────────────────────────────────────

  @doc """
  Create a sandbox. Returns `{:ok, %Modal.Sandbox{}}`.

  ## Options

  #{NimbleOptions.docs(@create_opts)}
  """
  @spec create(GenServer.server(), keyword()) :: {:ok, t()} | {:error, Modal.Error.t()}
  def create(client, opts) do
    caller = self()

    with {:ok, app_id, opts} <- Modal.App.resolve_app_id(opts),
         opts = opts |> Keyword.put(:app_id, app_id) |> coerce_opts(),
         {:ok, validated} <- validate_opts(opts, @create_opts),
         {:ok, validated} <- validate_extras(validated),
         request = %Modal.Client.SandboxCreateRequest{
           app_id: validated[:app_id],
           definition: build_definition(validated)
         },
         {:ok, resp} <- RPC.call(client, :SandboxCreate, request) do
      sandbox = %__MODULE__{id: resp.sandbox_id, client: client}

      sandbox =
        case watchdog_config(validated[:terminate_on_caller_exit]) do
          :disabled ->
            sandbox

          {:enabled, log_level} ->
            %{sandbox | monitor_pid: start_terminate_monitor(sandbox, caller, log_level)}
        end

      {:ok, sandbox}
    end
  end

  defp validate_opts(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = err} -> {:error, Modal.Error.validation(err)}
    end
  end

  # Cross-field invariants that NimbleOptions can't express: cpu vs
  # cpu_millis mutual exclusivity, and per-element shape validation on
  # `:volumes` (struct or {id, path}-bearing map). Run after the
  # NimbleOptions pass so we only validate type-correct inputs; returns
  # `{:error, %Modal.Error{kind: :validation}}` on the same shape as
  # NimbleOptions failures so callers see one consistent error tuple.
  defp validate_extras(opts) do
    with :ok <- validate_cpu_exclusivity(opts),
         :ok <- validate_volume_shapes(opts) do
      {:ok, opts}
    end
  end

  defp validate_cpu_exclusivity(opts) do
    has_cpu = (opts[:cpu] || 0) != 0
    has_millis = Keyword.has_key?(opts, :cpu_millis)

    if has_cpu and has_millis do
      {:error,
       Modal.Error.validation_msg(
         "Modal.Sandbox.create/2 accepts either :cpu (fractional cores) or " <>
           ":cpu_millis (exact millicores), not both. Got cpu=#{inspect(opts[:cpu])} " <>
           "and cpu_millis=#{inspect(opts[:cpu_millis])}."
       )}
    else
      :ok
    end
  end

  defp validate_volume_shapes(opts) do
    opts[:volumes]
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      case validate_volume_entry(entry) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_volume_entry(%Modal.Volume{}), do: :ok

  defp validate_volume_entry(v) when is_map(v) do
    id = Map.get(v, :id) || Map.get(v, "id")
    path = Map.get(v, :path) || Map.get(v, "path")

    if is_binary(id) and is_binary(path) do
      :ok
    else
      {:error,
       Modal.Error.validation_msg(
         "Modal.Sandbox volume entry requires :id and :path as strings, " <>
           "got #{inspect(v)}. Prefer %Modal.Volume{id: ..., path: ...}."
       )}
    end
  end

  defp validate_volume_entry(other) do
    {:error,
     Modal.Error.validation_msg(
       "Modal.Sandbox volumes must be %Modal.Volume{} structs or maps " <>
         "with :id and :path, got #{inspect(other)}."
     )}
  end

  @doc "Like `create/2` but raises on error."
  @spec create!(GenServer.server(), keyword()) :: t()
  def create!(client, opts) do
    case create(client, opts) do
      {:ok, sandbox} -> sandbox
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Resource-scoped helper: create a sandbox, hand it to `fun`, terminate
  on the way out. The sandbox is **always** terminated — successful
  return, exception raised inside `fun`, or caller process killed
  mid-execution (caller-exit via the watchdog).

  Equivalent to (modulo the watchdog):

      sandbox = Modal.Sandbox.create!(client, opts)
      try do
        fun.(sandbox)
      after
        Modal.Sandbox.terminate(sandbox)
      end

  Returns whatever `fun` returns. Raises on create failure (mirrors
  `create!/2`); for caller-recoverable create errors, use `create/2`
  directly.

  This is the right shape for "boot a sandbox, do a few things, throw
  it away" — file I/O probes, one-off shell commands that don't fit
  `run!/2` (which forces a single exec), or any multi-step workflow
  where you want guaranteed cleanup without writing the `try/after`
  yourself.

  Internally enables `:terminate_on_caller_exit: :silent` unless the
  caller already passed a value for that option, so a brutal_kill of
  the caller process between `create` and `terminate` still cleans
  up Modal-side without log noise. Pass `terminate_on_caller_exit:
  false` to opt out, or `:warning` to surface caller-exit cleanups in
  the log.

  ## Example

      out = Modal.Sandbox.with_sandbox(client, [app: app, image_id: img], fn sandbox ->
        :ok = Modal.Filesystem.write_file(sandbox, "/tmp/x", "hello")
        Modal.Sandbox.exec_streaming!(sandbox, ["cat", "/tmp/x"])
      end)
      # %{stdout: "hello", stderr: "", code: 0}
  """
  @spec with_sandbox(GenServer.server(), keyword(), (t() -> result)) :: result when result: var
  def with_sandbox(client, opts, fun) when is_function(fun, 1) do
    opts = Keyword.put_new(opts, :terminate_on_caller_exit, :silent)
    sandbox = create!(client, opts)

    try do
      fun.(sandbox)
    after
      _ = terminate(sandbox)
    end
  end

  @doc "Terminate a sandbox."
  @spec terminate(t()) :: :ok | {:error, Modal.Error.t()}
  def terminate(%__MODULE__{} = sb) do
    # If the sandbox was created with `terminate_on_caller_exit: true`,
    # cancel the watchdog before sending the terminate RPC — otherwise a
    # caller who terminates explicitly then exits would race the
    # watchdog into a redundant (idempotent but log-noisy) terminate.
    if sb.monitor_pid, do: send(sb.monitor_pid, :cancel)
    request = %Modal.Client.SandboxTerminateRequest{sandbox_id: sb.id}
    with {:ok, _} <- RPC.call(sb.client, :SandboxTerminate, request), do: :ok
  end

  @doc """
  Block until the sandbox finishes (its entrypoint exits or it is
  terminated). Returns the server's `SandboxWaitResponse` on completion.

  Use `poll/1` for a non-blocking check.

  ## Options

    * `:timeout_secs` — server-side wait timeout in seconds. `0` returns
      immediately ("is it finished now?"). Default `30.0`.
  """
  @spec wait(t(), keyword()) :: {:ok, term()} | {:error, Modal.Error.t()}
  def wait(%__MODULE__{} = sb, opts \\ []) do
    timeout_secs = Keyword.get(opts, :timeout_secs, 30.0)
    request = %Modal.Client.SandboxWaitRequest{sandbox_id: sb.id, timeout: timeout_secs}
    # call_no_retry: DEADLINE_EXCEEDED on SandboxWait means "still
    # running" (intentional poll semantics — see poll/1). Retrying
    # at the RPC layer would compound the wait beyond the caller's
    # :timeout_secs budget.
    RPC.call_no_retry(sb.client, :SandboxWait, request)
  end

  @doc """
  Non-blocking status check. Returns `{:ok, nil}` if still running,
  `{:ok, result}` if finished.

  Implemented as `wait(sandbox, timeout_secs: 0)` with the deadline-exceeded
  branch translated to `{:ok, nil}`.
  """
  @spec poll(t()) :: {:ok, term() | nil} | {:error, Modal.Error.t()}
  def poll(%__MODULE__{} = sb) do
    case wait(sb, timeout_secs: 0) do
      {:ok, %{result: nil}} -> {:ok, nil}
      {:ok, resp} -> {:ok, resp}
      {:error, %Modal.Error{kind: :grpc, code: @grpc_deadline_exceeded}} -> {:ok, nil}
      other -> other
    end
  end

  @doc """
  Block until the sandbox passes its readiness probe.

  ## Options

    * `:timeout_secs` — server-side wait timeout in seconds. Default `120.0`.
  """
  @spec wait_until_ready(t(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def wait_until_ready(%__MODULE__{} = sb, opts \\ []) do
    timeout_secs = Keyword.get(opts, :timeout_secs, 120.0)

    request = %Modal.Client.SandboxWaitUntilReadyRequest{
      sandbox_id: sb.id,
      timeout: timeout_secs
    }

    # call_no_retry: same poll semantics as SandboxWait — DEADLINE_EXCEEDED
    # carries domain meaning ("not ready yet"), not "retry me."
    with {:ok, _} <- RPC.call_no_retry(sb.client, :SandboxWaitUntilReady, request), do: :ok
  end

  @doc """
  Get task ID (waits for boot). Returns `{:ok, task_id}`.

  The result is cached on the `Modal.Client`, keyed by sandbox ID, so
  subsequent calls for the same sandbox short-circuit without an RPC.
  This means `Modal.Sandbox` itself stays a plain value — callers don't
  need to thread an updated struct through their call sites.

      {:ok, task_id} = Modal.Sandbox.get_task_id(sandbox)
      :ok = Modal.Filesystem.write_file(sandbox, "/tmp/a.txt", "hello")
      :ok = Modal.Filesystem.write_file(sandbox, "/tmp/b.txt", "world")
  """
  @spec get_task_id(t(), keyword()) :: {:ok, String.t()} | {:error, Modal.Error.t()}
  def get_task_id(%__MODULE__{} = sb, opts \\ []) do
    case RPC.lookup_task_id(sb.client, sb.id) do
      {:ok, task_id} ->
        {:ok, task_id}

      :miss ->
        request = %Modal.Client.SandboxGetTaskIdRequest{
          sandbox_id: sb.id,
          timeout: Keyword.get(opts, :timeout_secs, 30.0),
          wait_until_ready: true
        }

        with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTaskId, request) do
          RPC.cache_task_id(sb.client, sb.id, resp.task_id)
          {:ok, resp.task_id}
        end
    end
  end

  @doc """
  Look up a sandbox by name. Returns a `%Modal.Sandbox{}` populated
  with the looked-up id; the `:name` you searched by is preserved on
  the struct so `IO.inspect/1` and debug logs carry the breadcrumb.

  ## Options

    * `:environment_name` — Modal environment (default workspace default)
    * `:app_name` — narrow the lookup to a specific app
  """
  @spec from_name(GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def from_name(client, name, opts \\ []) do
    request = %Modal.Client.SandboxGetFromNameRequest{
      sandbox_name: name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      app_name: Keyword.get(opts, :app_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :SandboxGetFromName, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, name: name, client: client}}
    end
  end

  @doc """
  List sandboxes.

  Returns `{:ok, [map()]}` where each map mirrors Modal's proto
  `SandboxInfo` fields (`:id`, `:app_id`, `:created_at`,
  `:task_info`, `:tags`). Pattern-match on the keys you care about;
  the shape may grow over time as Modal adds fields. Internal proto
  structs are not exposed.

  ## Options

    * `:app_id` — filter by app id (default `""` = all apps)
    * `:include_finished` — include terminated sandboxes (default `false`)
    * `:environment_name` — Modal environment (default workspace default)
  """
  @spec list(GenServer.server(), keyword()) :: {:ok, [map()]} | {:error, Modal.Error.t()}
  def list(client, opts \\ []) do
    request = %Modal.Client.SandboxListRequest{
      app_id: Keyword.get(opts, :app_id, ""),
      include_finished: Keyword.get(opts, :include_finished, false),
      environment_name: Keyword.get(opts, :environment_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :SandboxList, request) do
      {:ok, Enum.map(resp.sandboxes, &sandbox_list_item_to_map/1)}
    end
  end

  defp sandbox_list_item_to_map(item) when is_map(item) do
    item
    |> Map.from_struct()
    |> Map.delete(:__unknown_fields__)
  end

  defp sandbox_list_item_to_map(item), do: item

  # ── Exec ────────────────────────────────────────────────────────

  @doc """
  Execute a command. Returns `{:ok, %Modal.ContainerProcess{}}` or
  `{:error, reason}`.

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)

  ## Options

    * `:workdir` — working directory for the command.
    * `:pty` — `true` for a default PTY, or a `%Modal.Client.PTYInfo{}`.
    * `:timeout_secs` — worker-side kill timeout: the command is SIGKILLed
      if it doesn't exit within it (surfacing as exit 137). Unset by
      default — the command runs until it finishes or the sandbox's own
      `:timeout_secs` fires. Matches the Python SDK's `exec(timeout=None)`.
  """
  @spec exec(t(), [String.t()], keyword()) ::
          {:ok, Modal.ContainerProcess.t()} | {:error, Modal.Error.t()}
  def exec(%__MODULE__{} = sb, command, opts \\ []) do
    Modal.ContainerProcess.start(sb, command, opts)
  end

  @doc "Like `exec/3` but raises on error."
  @spec exec!(t(), [String.t()], keyword()) :: Modal.ContainerProcess.t()
  def exec!(%__MODULE__{} = sb, command, opts \\ []) do
    case exec(sb, command, opts) do
      {:ok, proc} -> proc
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Exec a command, stream output through callbacks AND collect it, and
  await the exit — all in one call. Fuses `exec/3 + await/2 + close/1`.

  Right shape for "fire a command in an existing sandbox, watch its
  output live, get the result." For "boot + run + tear-down" use
  `Modal.Sandbox.run/2` instead.

  ## When to use this vs. `exec_streaming!/3`

  Standard Elixir bang/non-bang convention applies — the choice is a
  **domain** decision about what counts as a normal result:

    * `exec_streaming/3` (this function) when a non-zero exit is one
      of the answers you want to handle. Probes that may legitimately
      fail (does this URL respond? does this dep exist?), running
      user-supplied code, test runs where you want to inspect the
      output even on failure, anything where "the command exited
      non-zero" is a valid signal to act on.

    * `exec_streaming!/3` when a non-zero exit means "this workflow
      is broken." A build step that must succeed for the next step
      to make sense, a migration that has to apply cleanly, a
      pre-flight sanity check. The bang variant raises
      `%Modal.Error{kind: :exec_failed}` (or `:exec_unknown_status`)
      so the failure path lands in your supervisor / `try/rescue`
      with the stderr tail in the exception message — no need to
      pattern-match `{:ok, %{code: 0}}` everywhere.

  ## Example

      # Non-bang: handle non-zero as a result
      case Modal.Sandbox.exec_streaming(sandbox, ["pytest", "-v"]) do
        {:ok, %{code: 0}} -> :pass
        {:ok, %{code: _, stderr: err}} -> {:fail, err}
        {:error, %Modal.Error{} = e} -> {:transport_error, e}
      end

      # Bang: non-zero is a bug
      result = Modal.Sandbox.exec_streaming!(sandbox, ["mix", "deps.get"],
        on_stdout: Modal.ContainerProcess.line_buffered(&IO.puts/1)
      )
      # %{stdout: "...", stderr: "", code: 0}

  ## Options

    * `:on_stdout` — 1-arity callback fired per stdout chunk. Chunks
      are ALSO collected into `:stdout`. Wrap with
      `Modal.ContainerProcess.line_buffered/1` for one invocation per
      `\\n`-terminated line. Default: no-op.
    * `:on_stderr` — same shape, for stderr.
    * `:timeout` — **client-side** wall-clock ms for awaiting output
      (default `:infinity`). On expiry, `await/2` returns/raises a
      `:timeout` — the command keeps running on the worker.
    * `:exec_opts` — extra opts forwarded to `Modal.Sandbox.exec/3`
      (`:workdir`, `:pty`, `:timeout_secs`, …).

  > #### Two different timeouts {: .warning}
  >
  > `:timeout` (above) is how long *this client* waits. `exec_opts:
  > [timeout_secs: n]` is the **worker-side** cap — the worker SIGKILLs
  > the command after `n` seconds (surfacing as exit 137, the sandbox
  > untouched). `:timeout_secs` is unset by default (no per-exec cap; the
  > sandbox's own `:timeout_secs` governs), so `timeout: :infinity` truly
  > means "wait forever" rather than being silently capped.

  Returns the same result shape as `Modal.ContainerProcess.await/2`.
  Always calls `Modal.ContainerProcess.close/1` on the way out
  (success, exception, or caller crash mid-await), so the worker
  channel is released without bookkeeping.
  """
  @spec exec_streaming(t(), [String.t()], keyword()) ::
          {:ok, %{stdout: String.t(), stderr: String.t(), code: integer() | nil}}
          | {:error, Modal.Error.t()}
  def exec_streaming(%__MODULE__{} = sb, cmd, opts \\ []) do
    {await_opts, exec_streaming_opts} = Keyword.split(opts, [:on_stdout, :on_stderr, :timeout])

    with :ok <- validate_exec_streaming_opts(exec_streaming_opts) do
      exec_opts = Keyword.get(exec_streaming_opts, :exec_opts, [])

      with {:ok, proc} <- exec(sb, cmd, exec_opts) do
        try do
          Modal.ContainerProcess.await(proc, await_opts)
        after
          Modal.ContainerProcess.close(proc)
        end
      end
    end
  end

  # `Keyword.split/2` silently drops unknown keys, which means typos
  # like `on_log:` (copy-pasted from `Image.get_or_create/3`) vanish
  # without any feedback. Validate the residual keys explicitly so a
  # typo surfaces as a validation error instead of a silent no-op.
  @valid_exec_streaming_residual [:exec_opts]
  defp validate_exec_streaming_opts(opts) do
    case Keyword.keys(opts) -- @valid_exec_streaming_residual do
      [] ->
        :ok

      unknown ->
        {:error,
         Modal.Error.validation_msg(
           "Modal.Sandbox.exec_streaming/3 got unknown option(s): #{inspect(unknown)}. " <>
             "Valid options: :on_stdout, :on_stderr, :timeout, :exec_opts."
         )}
    end
  end

  @doc """
  Like `exec_streaming/3` but raises:

    * `%Modal.Error{kind: :exec_failed}` on a non-zero exit (carries
      stdout / stderr / code in `:metadata`),
    * `%Modal.Error{kind: :exec_unknown_status}` when the worker
      didn't report an exit code,
    * any other `%Modal.Error{}` bubbles as-is.

  Same options as `exec_streaming/3`. Idiomatic when "non-zero is a
  bug" — the failure path becomes a stacktrace with the stderr tail in
  the message, instead of `MatchError` on `{:ok, %{code: 0}} = …`.
  """
  @spec exec_streaming!(t(), [String.t()], keyword()) :: %{
          stdout: String.t(),
          stderr: String.t(),
          code: integer() | nil
        }
  def exec_streaming!(%__MODULE__{} = sb, cmd, opts \\ []) do
    sb |> exec_streaming(cmd, opts) |> raise_on_failure!()
  end

  # ── One-shot run ────────────────────────────────────────────────

  @doc """
  Create a sandbox, exec a command, collect output, and terminate — all in one
  call. The `System.cmd/3` of Modal.

      {:ok, %{stdout: out, stderr: err, code: code}} =
        Modal.Sandbox.run(client,
          app_id: app,
          image_id: image,
          cmd: ["bash", "-c", "echo hi; echo oops >&2; exit 0"]
        )

  Internally the sandbox boots with a `sleep infinity` entrypoint and the
  command runs inside via `Modal.Sandbox.exec/3`. The sandbox is always
  terminated on the way out — successful exit, non-zero exit, raise, or
  caller exit mid-await. A `try/after` covers the first three; for a
  brutal `Process.exit(caller, :kill)` (which skips `after`), `run/2`
  defaults `:terminate_on_caller_exit` to `:silent` so the caller-exit
  watchdog still reaps the sandbox Modal-side. Either way, callers don't
  write the `try/after` themselves.

  See `run!/2` for the raising variant; see `exec_streaming/3` for the
  same shape against an *existing* sandbox (skips create + terminate).
  The bang/non-bang choice mirrors `exec_streaming/3`'s — use the
  non-bang when a non-zero exit is a valid result you want to handle,
  the bang when it should crash.

  ## Options

  Accepts every option `Modal.Sandbox.create/2` does, plus:

    * `:cmd` (required) — the command to exec inside the sandbox, e.g.
      `["bash", "-c", script]` or `["python", "-c", code]`.
    * `:await_timeout` — milliseconds to wait for the exec to finish
      (default `:infinity`). Distinct from `:timeout` (the sandbox's
      wall-clock timeout in seconds).
    * `:exec_opts` — extra opts to forward to `Modal.Sandbox.exec/3`
      (e.g. `[workdir: "/work"]`).
    * `:terminate_on_caller_exit` — defaults to `:silent` here so a hard
      caller kill (which skips the `try/after`) still cleans up. Pass
      `false` to opt out, or `true` / a log level to surface caller-exit
      cleanups in the log.

  See `run!/2` for a raising variant that bubbles non-zero exits as
  `%Modal.Error{kind: :exec_failed}`.
  """
  @spec run(GenServer.server(), keyword()) ::
          {:ok, %{stdout: String.t(), stderr: String.t(), code: integer() | nil}}
          | {:error, Modal.Error.t()}
  def run(client, opts) do
    {exec_cmd, opts} = Keyword.pop(opts, :cmd)

    with :ok <- validate_cmd(exec_cmd) do
      {await_timeout, opts} = Keyword.pop(opts, :await_timeout, :infinity)
      {exec_opts, opts} = Keyword.pop(opts, :exec_opts, [])

      # The exec command is what we want to run; the sandbox entrypoint
      # is just a way to keep the box alive long enough to exec into it.
      # Arm the caller-exit watchdog (unless the caller set it) so a
      # brutal kill mid-run — which skips the `after` below — still
      # reaps the sandbox. Mirrors `with_sandbox/3`.
      create_opts =
        opts
        |> Keyword.put(:cmd, ["sleep", "infinity"])
        |> Keyword.put_new(:terminate_on_caller_exit, :silent)

      with {:ok, sandbox} <- create(client, create_opts) do
        try do
          run_in_sandbox(sandbox, exec_cmd, exec_opts, await_timeout)
        after
          # Best-effort: don't mask a real error with a cleanup failure.
          # If the sandbox is already gone (the wall-clock timeout fired),
          # terminate will return a 404-ish error which we discard.
          _ = terminate(sandbox)
        end
      end
    end
  end

  defp validate_cmd(cmd) do
    if is_list(cmd) and Enum.all?(cmd, &is_binary/1) do
      :ok
    else
      {:error,
       Modal.Error.validation_msg("Modal.Sandbox.run/2 requires :cmd as a list of strings, got #{inspect(cmd)}")}
    end
  end

  defp run_in_sandbox(sandbox, exec_cmd, exec_opts, await_timeout) do
    with {:ok, proc} <- exec(sandbox, exec_cmd, exec_opts) do
      try do
        Modal.ContainerProcess.await(proc, timeout: await_timeout)
      after
        Modal.ContainerProcess.close(proc)
      end
    end
  end

  @doc """
  Like `run/2` but raises on a non-zero exit or any other error.

      result = Modal.Sandbox.run!(client,
        app_id: app, image_id: image,
        cmd: ["python", "-c", "print(40+2)"]
      )
      # %{stdout: "42\n", stderr: "", code: 0}

  Equivalent to `run/2` followed by the same non-zero handling as
  `Modal.ContainerProcess.await!/2` — `%Modal.Error{kind: :exec_failed}`
  with `:code`, `:stdout`, and `:stderr` available for diagnostics.
  """
  @spec run!(GenServer.server(), keyword()) :: %{
          stdout: String.t(),
          stderr: String.t(),
          code: integer() | nil
        }
  def run!(client, opts) do
    client |> run(opts) |> raise_on_failure!()
  end

  # Shared bang-variant tail for `run!/2` and `exec_streaming!/3`.
  # Both have the same job: unwrap an exec result, raise the right
  # `%Modal.Error{}` if the exit was non-zero or unknown, or bubble
  # any transport error. `@doc false` because callers should use the
  # bang variants directly — this helper exists for the symmetry and
  # for direct test coverage of the four branches.
  @doc false
  @spec raise_on_failure!(
          {:ok, %{stdout: String.t(), stderr: String.t(), code: integer() | nil}}
          | {:error, Modal.Error.t()}
        ) :: %{stdout: String.t(), stderr: String.t(), code: integer()}
  def raise_on_failure!({:ok, %{code: 0} = result}), do: result

  def raise_on_failure!({:ok, %{code: nil, stdout: stdout, stderr: stderr}}),
    do: raise(Modal.Error.exec_unknown_status(stdout, stderr))

  def raise_on_failure!({:ok, %{code: code, stdout: stdout, stderr: stderr}}),
    do: raise(Modal.Error.exec_failed(code, stdout, stderr))

  def raise_on_failure!({:error, %Modal.Error{} = err}), do: raise(err)

  # ── Stdin ───────────────────────────────────────────────────────

  @doc """
  Write to the sandbox entrypoint's stdin.

  ## Options

    * `:offset` — byte offset within the entrypoint's stdin stream
      (default `0`). Use to write multiple chunks in order without
      racing the server's reader. Symmetric with
      `Modal.ContainerProcess.write/3`'s `:offset`.
    * `:eof` — when `true`, close stdin after this write (default `false`).
  """
  @spec stdin_write(t(), binary(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def stdin_write(%__MODULE__{} = sb, data, opts \\ []) do
    request = %Modal.Client.SandboxStdinWriteRequest{
      sandbox_id: sb.id,
      input: data,
      index: Keyword.get(opts, :offset, 0),
      eof: Keyword.get(opts, :eof, false)
    }

    with {:ok, _} <- RPC.call(sb.client, :SandboxStdinWrite, request), do: :ok
  end

  # ── Logs ────────────────────────────────────────────────────────

  @doc """
  Fetch sandbox logs as a list of log entries.

  ## Options

    * `:fd` — `:stdout` (default) or `:stderr`
    * `:timeout_secs` — server-side wait timeout in seconds. Default `55.0`.
    * `:last_entry_id` — opaque pagination cursor; pass the `entry_id`
      of the last entry from a previous call to get entries after it.
  """
  @spec get_logs(t(), keyword()) :: {:ok, list()} | {:error, Modal.Error.t()}
  def get_logs(%__MODULE__{} = sb, opts \\ []) do
    request = %Modal.Client.SandboxGetLogsRequest{
      sandbox_id: sb.id,
      file_descriptor: fd_to_proto(Keyword.get(opts, :fd, :stdout)),
      timeout: Keyword.get(opts, :timeout_secs, 55.0),
      last_entry_id: Keyword.get(opts, :last_entry_id, "")
    }

    RPC.stream(sb.client, :SandboxGetLogs, request)
  end

  defp fd_to_proto(:stdout), do: :FILE_DESCRIPTOR_STDOUT
  defp fd_to_proto(:stderr), do: :FILE_DESCRIPTOR_STDERR

  # ── Tunnels ─────────────────────────────────────────────────────

  @doc """
  Fetch the HTTPS tunnels exposed for this sandbox. Returns
  `{:ok, %{container_port => %Modal.Tunnel{}}}` — a map keyed by the
  in-container port — or `{:error, %Modal.Error{}}`.

  Sandboxes only have tunnels for ports declared via the `:ports`
  option to `create/2`; an empty map means no ports were exposed
  (or they haven't been bound yet — the call blocks server-side for
  up to `:timeout_secs` waiting on tunnel registration).

      sandbox = Modal.Sandbox.create!(client, ports: [8000], ...)
      {:ok, tunnels} = Modal.Sandbox.tunnels(sandbox)
      tunnels[8000] |> Modal.Tunnel.url()
      #=> "https://ta-...-8000-....w.modal.host"

  Shape mirrors Python's `Sandbox.tunnels()` (which switched from a
  list to a `dict[int, Tunnel]` in v0.64.153 for exactly this
  ergonomics).

  ## Options

    * `:timeout_secs` — server-side wait timeout in seconds. Default `30.0`.
  """
  @spec tunnels(t(), keyword()) ::
          {:ok, %{pos_integer() => Modal.Tunnel.t()}} | {:error, Modal.Error.t()}
  def tunnels(%__MODULE__{} = sb, opts \\ []) do
    timeout_secs = Keyword.get(opts, :timeout_secs, 30.0)
    request = %Modal.Client.SandboxGetTunnelsRequest{sandbox_id: sb.id, timeout: timeout_secs}

    with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTunnels, request) do
      {:ok, Map.new(resp.tunnels, fn t -> {t.container_port, build_tunnel(t)} end)}
    end
  end

  defp build_tunnel(%Modal.Client.TunnelData{} = t) do
    %Modal.Tunnel{
      host: t.host,
      port: t.port,
      container_port: t.container_port,
      unencrypted_host: t.unencrypted_host,
      unencrypted_port: t.unencrypted_port
    }
  end

  @doc "Get an HTTP connect token."
  @spec connect_token(t(), keyword()) ::
          {:ok, %{url: String.t(), token: String.t()}} | {:error, Modal.Error.t()}
  def connect_token(%__MODULE__{} = sb, opts \\ []) do
    request = %Modal.Client.SandboxCreateConnectTokenRequest{
      sandbox_id: sb.id,
      user_metadata: Keyword.get(opts, :user_metadata, "")
    }

    with {:ok, resp} <- RPC.call(sb.client, :SandboxCreateConnectToken, request) do
      {:ok, %{url: resp.url, token: resp.token}}
    end
  end

  # ── Filesystem ───────────────────────────────────────────────────
  #
  # Thin delegates to `Modal.Filesystem` for ergonomic call sites that
  # already hold a `%Modal.Sandbox{}`. The canonical home for filesystem
  # operations is `Modal.Filesystem` (mirrors the `sandbox.filesystem.*`
  # namespace in Modal's reference Python client). Either spelling is
  # supported; both call into the same implementation.

  @doc "See `Modal.Filesystem.read_file/2`."
  defdelegate read_file(sandbox, path), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.read_file!/2`."
  defdelegate read_file!(sandbox, path), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.write_file/3`."
  defdelegate write_file(sandbox, path, content), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.write_file!/3`."
  defdelegate write_file!(sandbox, path, content), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.write_files/3`."
  defdelegate write_files(sandbox, files, opts \\ []), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.write_files!/3`."
  defdelegate write_files!(sandbox, files, opts \\ []), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.ls/2`."
  defdelegate ls(sandbox, path \\ "/"), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.mkdir/3`."
  defdelegate mkdir(sandbox, path, opts \\ []), to: Modal.Filesystem

  @doc "See `Modal.Filesystem.rm/3`."
  defdelegate rm(sandbox, path, opts \\ []), to: Modal.Filesystem

  # ── Snapshots ───────────────────────────────────────────────────

  @doc """
  Snapshot a running sandbox (full VM). Returns `{:ok, snapshot_id}`.

  ## Options

    * `:timeout_secs` — server-side wait timeout in seconds. Default `55.0`.
  """
  @spec snapshot(t(), keyword()) :: {:ok, String.t()} | {:error, Modal.Error.t()}
  def snapshot(%__MODULE__{} = sb, opts \\ []) do
    timeout_secs = Keyword.get(opts, :timeout_secs, 55.0)

    with {:ok, resp} <-
           RPC.call(sb.client, :SandboxSnapshot, %Modal.Client.SandboxSnapshotRequest{
             sandbox_id: sb.id
           }),
         {:ok, wait_resp} <-
           RPC.call(sb.client, :SandboxSnapshotWait, %Modal.Client.SandboxSnapshotWaitRequest{
             snapshot_id: resp.snapshot_id,
             timeout: timeout_secs
           }) do
      if wait_resp.result && wait_resp.result.status == :GENERIC_STATUS_SUCCESS do
        {:ok, resp.snapshot_id}
      else
        status = wait_resp.result && wait_resp.result.status
        {:error, Modal.Error.snapshot_failed(:vm, status)}
      end
    end
  end

  @doc "Restore from snapshot."
  @spec restore(GenServer.server(), String.t()) :: {:ok, t()} | {:error, Modal.Error.t()}
  def restore(client, snapshot_id) do
    request = %Modal.Client.SandboxRestoreRequest{snapshot_id: snapshot_id}

    with {:ok, resp} <- RPC.call(client, :SandboxRestore, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
    end
  end

  @doc """
  Snapshot the sandbox filesystem as a reusable image. Returns
  `{:ok, image_id}`.

  ## Options

    * `:timeout_secs` — server-side wait timeout in seconds. Default `55.0`.
  """
  @spec snapshot_filesystem(t(), keyword()) :: {:ok, String.t()} | {:error, Modal.Error.t()}
  def snapshot_filesystem(%__MODULE__{} = sb, opts \\ []) do
    request = %Modal.Client.SandboxSnapshotFsRequest{
      sandbox_id: sb.id,
      timeout: Keyword.get(opts, :timeout_secs, 55.0)
    }

    with {:ok, resp} <- RPC.call(sb.client, :SandboxSnapshotFs, request) do
      if resp.result && resp.result.status == :GENERIC_STATUS_SUCCESS do
        {:ok, resp.image_id}
      else
        status = resp.result && resp.result.status
        {:error, Modal.Error.snapshot_failed(:fs, status)}
      end
    end
  end

  # ── Option coercions (pre-NimbleOptions) ────────────────────────

  # Normalise option shapes that NimbleOptions can't express directly.
  # Runs before the schema so the schema only has to know one spelling.
  #
  #   * `:regions` as a single string → `[string]`
  defp coerce_opts(opts), do: coerce_regions(opts)

  defp coerce_regions(opts) do
    case Keyword.get(opts, :regions) do
      r when is_binary(r) -> Keyword.put(opts, :regions, [r])
      _ -> opts
    end
  end

  # `idle_timeout_secs` semantics differ from the proto field on the wire:
  # `nil`/`0` from the caller both mean "no idle timeout" and we leave
  # the proto field unset (Modal's server-side default). A positive int
  # passes through. The proto definition is `optional uint32` so an unset
  # field is genuinely distinct from `0` on the wire — sending `0`
  # would tell the worker to kill the sandbox the instant the entrypoint
  # goes idle.
  defp wire_idle_timeout(nil), do: nil
  defp wire_idle_timeout(0), do: nil
  defp wire_idle_timeout(n) when is_integer(n) and n > 0, do: n

  # ── Definition builder ──────────────────────────────────────────

  defp build_definition(opts) do
    %Modal.Client.Sandbox{
      entrypoint_args: opts[:cmd],
      image_id: opts[:image_id],
      timeout_secs: opts[:timeout_secs],
      idle_timeout_secs: wire_idle_timeout(opts[:idle_timeout_secs]),
      name: opts[:name],
      workdir: opts[:workdir],
      block_network: opts[:block_network],
      network_access: build_network_access(opts[:network_access]),
      proxy_id: opts[:proxy_id],
      i6pn_enabled: opts[:i6pn],
      cloud_bucket_mounts: Enum.map(opts[:cloud_bucket_mounts] || [], &build_bucket_mount/1),
      enable_snapshot: opts[:snapshot],
      verbose: opts[:verbose],
      direct_sandbox_commands_enabled: true,
      secret_ids: opts[:secret_ids],
      resources: build_resources(opts),
      open_ports_oneof: build_ports(opts),
      volume_mounts: Enum.map(opts[:volumes], &build_volume/1),
      scheduler_placement: build_scheduler(opts)
    }
  end

  defp build_resources(opts) do
    gpu =
      case opts[:gpu] do
        nil -> nil
        type -> %Modal.Client.GPUConfig{gpu_type: type, count: opts[:gpu_count]}
      end

    milli_cpu = resolve_milli_cpu(opts)

    if opts[:memory_mb] > 0 or milli_cpu > 0 or opts[:disk_mb] > 0 or gpu do
      %Modal.Client.Resources{
        memory_mb: opts[:memory_mb],
        milli_cpu: milli_cpu,
        gpu_config: gpu,
        ephemeral_disk_mb: opts[:disk_mb]
      }
    end
  end

  # `:cpu` and `:cpu_millis` mutual exclusivity is validated up front in
  # `validate_extras/1`; by the time we get here, at most one is set.
  defp resolve_milli_cpu(opts) do
    if Keyword.has_key?(opts, :cpu_millis),
      do: opts[:cpu_millis],
      else: trunc((opts[:cpu] || 0) * 1000)
  end

  defp build_ports(opts) do
    case opts[:ports] do
      [] ->
        nil

      ports ->
        {:open_ports, %Modal.Client.PortSpecs{ports: Enum.map(ports, &%Modal.Client.PortSpec{port: &1})}}
    end
  end

  # Both the struct and plain-map forms have already passed
  # `validate_volume_entry/1` by the time we reach `build_volume/1` —
  # other shapes are impossible here.
  defp build_volume(%Modal.Volume{} = v) do
    %Modal.Client.VolumeMount{
      volume_id: v.id,
      mount_path: v.path,
      read_only: v.read_only,
      # Worker commits writes periodically + on exit, so a sandbox's volume
      # writes persist without an in-container `commit()` (which can't auth
      # anyway). Matches the Python SDK's sandbox volume mounts.
      allow_background_commits: true
    }
  end

  defp build_volume(v) when is_map(v) do
    %Modal.Client.VolumeMount{
      volume_id: Map.get(v, :id) || Map.get(v, "id"),
      mount_path: Map.get(v, :path) || Map.get(v, "path"),
      read_only: Map.get(v, :read_only, false),
      allow_background_commits: true
    }
  end

  defp build_scheduler(opts) do
    case opts[:regions] do
      nil -> nil
      regions when is_list(regions) -> %Modal.Client.SchedulerPlacement{regions: regions}
    end
  end

  # ── Cloud bucket mounts ─────────────────────────────────────────

  defp build_bucket_mount(%Modal.CloudBucket{} = b), do: Modal.CloudBucket.to_proto(b)

  defp build_bucket_mount(other) do
    raise ArgumentError,
          "cloud_bucket_mounts entries must be %Modal.CloudBucket{} structs; " <>
            "got #{inspect(other)}"
  end

  # ── Network access ──────────────────────────────────────────────

  defp build_network_access(nil), do: nil

  defp build_network_access(:open),
    do: %Modal.Client.NetworkAccess{network_access_type: :OPEN}

  defp build_network_access(:blocked),
    do: %Modal.Client.NetworkAccess{network_access_type: :BLOCKED}

  defp build_network_access({:allowlist, cidrs}) when is_list(cidrs) do
    %Modal.Client.NetworkAccess{
      network_access_type: :ALLOWLIST,
      allowed_cidrs: cidrs
    }
  end

  @doc false
  def validate_network_access(:open), do: {:ok, :open}
  def validate_network_access(:blocked), do: {:ok, :blocked}

  def validate_network_access({:allowlist, []}),
    do: {:error, "network_access {:allowlist, []}: empty allowlist denies all egress; use :blocked instead"}

  def validate_network_access({:allowlist, [_ | _] = cidrs}) do
    if Enum.all?(cidrs, &is_binary/1) do
      {:ok, {:allowlist, cidrs}}
    else
      {:error, "network_access {:allowlist, cidrs}: each CIDR must be a string"}
    end
  end

  def validate_network_access(other),
    do: {:error, "expected :open | :blocked | {:allowlist, [\"cidr\", ...]}, got #{inspect(other)}"}

  @doc """
  Fetch GitHub's current API IP allowlist as a list of CIDR strings,
  suitable for `network_access: {:allowlist, ...}`.

  GitHub publishes a meta endpoint at `https://api.github.com/meta`
  with their service IP ranges. The `api` block (used by
  `api.github.com` + `*.github.com` REST/GraphQL) is typically
  ~10 CIDRs and stable enough to pin in a deploy.

  Returns IPv4 CIDRs only — Modal's `network_access` allowlist
  rejects IPv6 (`gRPC INVALID_ARGUMENT: "does not support IPv6"`).
  GitHub publishes both families; we drop the `::/...` entries.

  ## Example

      gh = Modal.Sandbox.github_cidrs!()

      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["python", "agent.py"],
        network_access: {:allowlist, gh}
      )

  Falls through Req's default HTTP retry; raises `Modal.Error` if
  GitHub returns non-200 or the JSON doesn't contain the `:block`
  key. Snapshot the result and pass it explicitly if you don't
  want to hit GitHub on every deploy.

  ## Options

    * `:block` — which block from `api.github.com/meta` to return.
      Defaults to `"api"`. Other useful values: `"web"`, `"git"`,
      `"hooks"`, `"actions"`, `"importer"`.
    * `:family` — `:ipv4` (default, only IPv4 CIDRs — Modal's
      allowlist requirement), `:ipv6`, or `:both`.
  """
  @spec github_cidrs!(keyword()) :: [String.t()]
  def github_cidrs!(opts \\ []) do
    block = Keyword.get(opts, :block, "api")
    family = Keyword.get(opts, :family, :ipv4)

    case Req.get("https://api.github.com/meta", receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: %{} = body}} ->
        case Map.fetch(body, block) do
          {:ok, cidrs} when is_list(cidrs) ->
            filter_family(cidrs, family)

          _ ->
            raise Modal.Error.validation_msg(
                    "github_cidrs!: api.github.com/meta has no #{inspect(block)} key " <>
                      "(available: #{inspect(Map.keys(body))})"
                  )
        end

      {:ok, %Req.Response{status: status}} ->
        raise Modal.Error.network({:github_meta, status})

      {:error, reason} ->
        raise Modal.Error.network({:github_meta, reason})
    end
  end

  defp filter_family(cidrs, :both), do: cidrs
  defp filter_family(cidrs, :ipv6), do: Enum.filter(cidrs, &String.contains?(&1, ":"))
  defp filter_family(cidrs, :ipv4), do: Enum.reject(cidrs, &String.contains?(&1, ":"))

  # ── Caller-exit monitor ─────────────────────────────────────────
  #
  # Mirrors the channel-monitor pattern in
  # `Modal.ContainerProcess.start_channel_monitor/2`: a dedicated
  # lightweight process watches the caller via `Process.monitor/1` and
  # fires `Sandbox.terminate/1` if the caller dies before
  # `terminate/1` is called explicitly. The synchronous `:monitor_ready`
  # handshake closes the race where the caller could exit between
  # `spawn/1` returning and `Process.monitor/1` running.

  # Normalise the user's `:terminate_on_caller_exit` choice into either
  # `:disabled` or `{:enabled, log_level_or_nil}`. `nil` log level means
  # the watchdog fires silently.
  defp watchdog_config(false), do: :disabled
  defp watchdog_config(true), do: {:enabled, :warning}
  defp watchdog_config(:silent), do: {:enabled, nil}

  defp watchdog_config(level) when level in [:debug, :info, :warning, :error],
    do: {:enabled, level}

  defp start_terminate_monitor(%__MODULE__{} = sandbox, caller, log_level) do
    parent = self()

    # Run the monitor under the library's Task.Supervisor rather than a
    # bare `spawn/1`: a crash in here (the watchdog that's supposed to
    # stop a leak) is then reported through the logger instead of
    # vanishing silently. The `:monitor_ready` handshake still closes the
    # race where `caller` exits before `Process.monitor/1` runs.
    {:ok, pid} =
      Task.Supervisor.start_child(Modal.WatchdogSupervisor, fn ->
        ref = Process.monitor(caller)
        send(parent, {self(), :monitor_ready})

        receive do
          {:DOWN, ^ref, :process, ^caller, reason} ->
            log_watchdog_fire(log_level, sandbox, caller, reason)

            # Best-effort: log and swallow. The caller is already dead;
            # there's no one to receive an error tuple, and a noisy crash
            # in this monitor process would only spam logs.
            case terminate(sandbox) do
              :ok ->
                :ok

              {:error, err} ->
                log_watchdog_failure(log_level, sandbox, err)
            end

          :cancel ->
            :ok
        end
      end)

    receive do
      {^pid, :monitor_ready} -> pid
    end
  end

  defp log_watchdog_fire(nil, _sandbox, _caller, _reason), do: :ok

  defp log_watchdog_fire(level, sandbox, caller, reason) do
    Logger.log(
      level,
      "[modal] sandbox #{sandbox.id}: caller #{inspect(caller)} exited " <>
        "(#{inspect(reason)}); auto-terminating per :terminate_on_caller_exit"
    )
  end

  defp log_watchdog_failure(nil, _sandbox, _err), do: :ok

  defp log_watchdog_failure(level, sandbox, err) do
    # If the user opted out of fire-time logs, they presumably don't
    # want cleanup-failure logs either — but we err one step above
    # silent because a failing terminate is "the leak you were trying
    # to avoid actually happened" and worth surfacing.
    elevated =
      case level do
        :debug -> :info
        :info -> :warning
        other -> other
      end

    Logger.log(elevated, "[modal] sandbox #{sandbox.id}: auto-terminate failed: #{inspect(err)}")
  end

  # ── Inspect — show only sandbox ID + optional name, redact client ──

  defimpl Inspect do
    def inspect(%Modal.Sandbox{name: nil} = sb, _opts), do: "#Modal.Sandbox<id: #{sb.id}>"

    def inspect(%Modal.Sandbox{} = sb, _opts),
      do: "#Modal.Sandbox<id: #{sb.id}, name: #{inspect(sb.name)}>"
  end
end
