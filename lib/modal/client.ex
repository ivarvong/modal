defmodule Modal.Client do
  @moduledoc """
  A gRPC connection to the Modal API.

  Wraps a `GRPC.Channel` to `api.modal.com`. Start one per set of credentials —
  in a SaaS context, one per customer — and pass it to `Modal.*` functions.

  RPC calls are dispatched concurrently via a per-client `Task.Supervisor`, so a
  single `Modal.Client` can serve many concurrent requests without serialisation.

  ## Usage

      {:ok, client} = Modal.Client.start_link(
        token_id: "ak-...",
        token_secret: "as-..."
      )

      {:ok, sandboxes} = Modal.Sandbox.list(client)

  ## Supervision

      children = [
        {Modal.Client,
         name: MyApp.ModalClient,
         token_id: System.fetch_env!("MODAL_TOKEN_ID"),
         token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")}
      ]

  ## Options

    * `:token_id` — Modal API token ID (required)
    * `:token_secret` — Modal API token secret (required)
    * `:server_url` — API endpoint (default `"https://api.modal.com"`)
    * `:name` — GenServer name for registration
    * `:modal_stub` — gRPC stub module (defaults to the production stub; override with a Mox in tests)
    * `:max_concurrency` — max inflight RPCs (default `:infinity`)
  """

  @behaviour Modal.Client.Behaviour

  use GenServer

  # The Modal API protocol version expected by Modal's servers.
  # This is NOT the library version — update it when Modal bumps the protocol.
  @modal_client_version "1.4.0"

  @type rpc_error :: Modal.Error.t()

  # ── Public API ──────────────────────────────────────────────────

  @doc """
  Start a supervised `Modal.Client` GenServer holding one gRPC
  connection and one set of credentials. Returns `{:ok, pid}` (or
  `{:ok, name}` if `:name` is set).

      {:ok, client} = Modal.Client.start_link(
        token_id: System.fetch_env!("MODAL_TOKEN_ID"),
        token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")
      )

  In production, place under a supervisor — one client per tenant,
  named, with `:max_concurrency` set per your throughput target.

  ## Options

    * `:token_id` (required) — Modal API token ID (`ak-...`).
    * `:token_secret` (required) — Modal API token secret (`as-...`).
    * `:server_url` — API endpoint (default `"https://api.modal.com"`).
      Set to `"https://api.modal-staging.com"` for staging.
    * `:name` — GenServer name for registration; if set, RPC callers
      can use the atom or `{:via, ...}` tuple in place of the pid.
    * `:max_concurrency` — cap on in-flight RPCs. `:infinity` (default)
      or a positive integer. Exceeded RPCs return
      `{:error, %Modal.Error{kind: :overloaded}}`.
    * `:modal_stub` — gRPC stub module. Defaults to the production
      stub; override with a Mox in tests.

  ## Credentials

  Use `Modal.Credentials.load!/1` to splat in env/profile values:

      {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Lower-level escape hatch: dispatch a unary RPC by its **snake_case**
  stub name (e.g. `:sandbox_create`, `:volume_get_or_create`).

  Most callers should use `Modal.RPC.call/4` instead — it accepts the
  proto's PascalCase atoms, gives compile-time typo safety, and emits
  `[:modal, :rpc, :*]` telemetry. This function is the fallback for
  RPCs that aren't yet in `Modal.RPC`'s dispatch table; you lose the
  telemetry and typo check but reach every RPC the generated stub
  exposes.
  """
  @impl Modal.Client.Behaviour
  def rpc(client, method, request, timeout \\ 30_000) do
    GenServer.call(client, {:rpc, method, request, timeout}, timeout + 5_000)
  end

  @doc "Like `rpc/4`, but for server-streaming RPCs; collects all responses into a list."
  @impl Modal.Client.Behaviour
  def stream_rpc(client, method, request, timeout \\ 60_000) do
    GenServer.call(client, {:stream_rpc, method, request, timeout}, timeout + 5_000)
  end

  @doc "Like `stream_rpc/4`, but folds responses through a `{:cont, acc} | {:halt, acc}` reducer."
  @impl Modal.Client.Behaviour
  def stream_rpc_reduce(client, method, request, acc, reducer, timeout \\ :infinity) do
    GenServer.call(client, {:stream_rpc_reduce, method, request, acc, reducer}, timeout)
  end

  @doc """
  Look up a cached `task_id` for a sandbox. Returns `{:ok, task_id}` on hit,
  `:miss` if not yet resolved. Used by `Modal.Sandbox.get_task_id/1` to
  avoid repeat RPCs for the same sandbox.
  """
  @impl Modal.Client.Behaviour
  def lookup_task_id(client, sandbox_id) when is_binary(sandbox_id) do
    GenServer.call(client, {:lookup_task_id, sandbox_id})
  end

  @doc """
  Cache a `task_id` for a sandbox so subsequent `lookup_task_id/2` calls
  short-circuit. Idempotent: storing the same value twice is a no-op,
  and a different value is overwritten without comment (the server
  determines truth, the cache only avoids re-asking).
  """
  @impl Modal.Client.Behaviour
  def cache_task_id(client, sandbox_id, task_id)
      when is_binary(sandbox_id) and is_binary(task_id) do
    GenServer.cast(client, {:cache_task_id, sandbox_id, task_id})
  end

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def init(opts) do
    server_url = Keyword.get(opts, :server_url, "https://api.modal.com")
    stub = Keyword.get(opts, :modal_stub, Modal.ModalStub.Real)
    max_concurrency = Keyword.get(opts, :max_concurrency, :infinity)

    # `:connect_fn` is an undocumented test seam: a 1-arity function that
    # receives the GenServer state and returns `{:ok, state}` (with `:channel`
    # populated) or `{:error, reason, state}`. Production code never sets it
    # — `default_connect/1` opens a real gRPC channel to `:server_url`. Tests
    # set it to skip the network and inject a sentinel channel, which is
    # how the regression suites in test/modal/client_*_test.exs verify
    # dispatch, error mapping, and reconnect logic without a live server.
    connect_fn = Keyword.get(opts, :connect_fn, &default_connect/1)

    credentials = %Modal.Client.Credentials{
      metadata: %{
        "x-modal-token-id" => Keyword.fetch!(opts, :token_id),
        "x-modal-token-secret" => Keyword.fetch!(opts, :token_secret),
        "x-modal-client-version" => @modal_client_version,
        "x-modal-client-type" => "1"
      }
    }

    # Linked to this GenServer — cleaned up automatically on crash.
    {:ok, task_sup} = Task.Supervisor.start_link()

    # `GRPC.Client.Supervisor` is started by `Modal.Application` at boot
    # and lives under `Modal.Supervisor`, outliving every individual
    # client. We never start or stop it from here — doing so would tie
    # the supervisor's lifecycle to whichever client got there first
    # and take down every tenant's channels when that client stopped.

    state = %{
      server_url: server_url,
      credentials: credentials,
      channel: nil,
      task_sup: task_sup,
      stub: stub,
      connect_fn: connect_fn,
      max_concurrency: max_concurrency,
      inflight: 0,
      # Per-sandbox task_id cache. Resolving a sandbox's task_id requires
      # an RPC (`SandboxGetTaskId`) that blocks on boot — caching collapses
      # repeat resolutions for the same sandbox to a single RPC. Lives on
      # the GenServer so it's tied to the client's lifecycle, not threaded
      # through caller code (which a previous 3-tuple return tried, and
      # most call sites discarded the mutated struct).
      task_ids: %{},
      # `:epoch` advances every time `connect/1` returns a fresh channel.
      # `dispatch/3` tags each task with the current epoch, and
      # `handle_cast({:connection_failed, e})` only triggers a reconnect
      # when `e` still matches `state.epoch`. This collapses a stampede
      # of N concurrent in-flight tasks (all of which failed on the same
      # dead channel) into a single reconnect.
      epoch: 0
    }

    case connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, _, state} -> {:ok, state}
    end
  end

  # Each handle_call dispatches work to a Task.Supervisor task and returns
  # {:noreply} immediately, so the GenServer mailbox is never blocked by a
  # slow RPC. The task calls GenServer.reply/2 when done.
  @impl true
  def handle_call({:rpc, method, request, timeout}, from, state) do
    with_channel(state, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_rpc(state.stub, channel, metadata, method, request, timeout)
      end)
    end)
  end

  @impl true
  def handle_call({:stream_rpc, method, request, timeout}, from, state) do
    with_channel(state, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_stream_rpc(state.stub, channel, metadata, method, request, timeout)
      end)
    end)
  end

  @impl true
  def handle_call({:stream_rpc_reduce, method, request, acc, reducer}, from, state) do
    with_channel(state, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_stream_reduce(state.stub, channel, metadata, method, request, acc, reducer)
      end)
    end)
  end

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :pong, state}

  @impl true
  def handle_call({:lookup_task_id, sandbox_id}, _from, state) do
    case Map.fetch(state.task_ids, sandbox_id) do
      {:ok, task_id} -> {:reply, {:ok, task_id}, state}
      :error -> {:reply, :miss, state}
    end
  end

  # Gun notifies us when the HTTP/2 connection drops — mark channel nil so the
  # next RPC reconnects lazily.
  @impl true
  def handle_info({:gun_down, _, _, _, _}, state) do
    {:noreply, %{state | channel: nil}}
  end

  @impl true
  def handle_info({:gun_up, _, _}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Only the first task to observe a broken channel triggers reconnect. Every
  # other in-flight task that captured the same epoch is now stale and is
  # ignored — collapses N concurrent failures into one reconnect.
  @impl true
  def handle_cast({:connection_failed, task_epoch}, %{epoch: current_epoch} = state)
      when task_epoch == current_epoch do
    {:noreply, reconnect(state)}
  end

  def handle_cast({:connection_failed, _stale_epoch}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:task_completed, state) do
    {:noreply, %{state | inflight: max(0, state.inflight - 1)}}
  end

  @impl true
  def handle_cast({:cache_task_id, sandbox_id, task_id}, state) do
    {:noreply, %{state | task_ids: Map.put(state.task_ids, sandbox_id, task_id)}}
  end

  @impl true
  def terminate(_reason, state) do
    safe_disconnect(state.channel)
    :ok
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp with_channel(state, fun) do
    case ensure_channel(state) do
      {:ok, state} -> fun.(state)
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  # ── Task dispatch ────────────────────────────────────────────────

  defp dispatch(from, state, _fun)
       when state.max_concurrency != :infinity and state.inflight >= state.max_concurrency do
    GenServer.reply(from, {:error, Modal.Error.overloaded()})
    {:noreply, state}
  end

  defp dispatch(from, state, fun) do
    channel = state.channel
    metadata = state.credentials.metadata
    server = self()
    # Tag this task with the epoch it observed at dispatch time. Used to
    # deduplicate `:connection_failed` casts from a stampede of in-flight
    # tasks that all failed on the same dead channel.
    epoch = state.epoch

    # try/after guarantees `:task_completed` casts even if `fun.(...)` crashes
    # — otherwise `state.inflight` leaks upward forever and `max_concurrency`
    # eventually wedges. try/catch guarantees the caller's `GenServer.call`
    # receives a reply rather than blocking until its timeout.
    Task.Supervisor.start_child(state.task_sup, fn ->
      try do
        result = fun.(channel, metadata)
        if network_error?(result), do: GenServer.cast(server, {:connection_failed, epoch})
        GenServer.reply(from, result)
      catch
        kind, reason ->
          GenServer.reply(from, {:error, Modal.Error.task_crashed(kind, reason)})
      after
        GenServer.cast(server, :task_completed)
      end
    end)

    {:noreply, %{state | inflight: state.inflight + 1}}
  end

  defp network_error?({:error, %Modal.Error{kind: :network}}), do: true
  defp network_error?(_), do: false

  # ── RPC execution (runs inside Task) ────────────────────────────

  defp exec_rpc(stub, channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case stub.call(channel, method, request, opts) do
      {:ok, response} -> {:ok, response}
      {:error, %GRPC.RPCError{status: s, message: m}} -> {:error, Modal.Error.grpc(s, m)}
      {:error, reason} -> {:error, Modal.Error.network(reason)}
    end
  end

  defp exec_stream_rpc(stub, channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case stub.stream(channel, method, request, opts) do
      {:ok, enum} ->
        result =
          Enum.reduce_while(enum, {:ok, []}, fn
            {:ok, msg}, {:ok, acc} ->
              {:cont, {:ok, [msg | acc]}}

            item, _ ->
              {:halt, {:error, map_stream_error(item)}}
          end)

        case result do
          {:ok, items} -> {:ok, Enum.reverse(items)}
          error -> error
        end

      {:error, %GRPC.RPCError{status: s, message: m}} ->
        {:error, Modal.Error.grpc(s, m)}

      {:error, reason} ->
        {:error, Modal.Error.network(reason)}
    end
  end

  defp exec_stream_reduce(stub, channel, metadata, method, request, acc, reducer) do
    opts = [metadata: metadata]

    case stub.stream(channel, method, request, opts) do
      {:ok, enum} ->
        final =
          Enum.reduce_while(enum, acc, fn
            {:ok, msg}, acc ->
              reducer.(msg, acc)

            item, _acc ->
              {:halt, {:error, map_stream_error(item)}}
          end)

        case final do
          {:error, _} = err -> err
          acc -> {:ok, acc}
        end

      {:error, %GRPC.RPCError{status: s, message: m}} ->
        {:error, Modal.Error.grpc(s, m)}

      {:error, reason} ->
        {:error, Modal.Error.network(reason)}
    end
  end

  # Any item that isn't {:ok, msg} is a terminal error and must halt the
  # stream. The previous catch-all silently dropped {:error, _} items,
  # turning a half-finished build/log stream into a "successful" partial
  # result. Every non-ok item now halts with a structured Modal.Error.
  defp map_stream_error({:error, %GRPC.RPCError{status: s, message: m}}),
    do: Modal.Error.grpc(s, m)

  defp map_stream_error({:error, reason}), do: Modal.Error.network(reason)
  defp map_stream_error(other), do: Modal.Error.unexpected(other)

  # ── Connection management ────────────────────────────────────────

  defp ensure_channel(%{channel: nil} = state), do: connect(state)
  defp ensure_channel(state), do: {:ok, state}

  defp connect(state) do
    # Every successful connect bumps `:epoch`. This is the single source of
    # truth for "the channel currently in state.channel belongs to generation
    # N" — stale `:connection_failed` casts that observed generation N-1 will
    # not match and will not re-trigger reconnect.
    case state.connect_fn.(state) do
      {:ok, new_state} -> {:ok, %{new_state | epoch: state.epoch + 1}}
      other -> other
    end
  end

  defp default_connect(state) do
    cred =
      GRPC.Credential.new(ssl: [cacertfile: CAStore.file_path(), verify: :verify_peer, depth: 4])

    case GRPC.Stub.connect(state.server_url, cred: cred) do
      {:ok, channel} ->
        {:ok, %{state | channel: channel}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp reconnect(state) do
    safe_disconnect(state.channel)

    case connect(%{state | channel: nil}) do
      {:ok, state} -> state
      {:error, _, state} -> state
    end
  end

  # Defensive: disconnect can crash if the underlying orchestrator process
  # is dead (e.g. a gun_down arrived in parallel with our reconnect path).
  # The right behaviour is to swallow the crash and proceed with reconnect —
  # otherwise a network blip during reconnect takes the whole client down.
  defp safe_disconnect(nil), do: :ok

  defp safe_disconnect(channel) do
    GRPC.Stub.disconnect(channel)
  catch
    _, _ -> :ok
  end
end
