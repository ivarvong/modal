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
    * `:modal_stub` — gRPC stub module (default `Modal.ModalStub.Real`, override for testing)
    * `:max_concurrency` — max inflight RPCs (default `:infinity`)
  """

  @behaviour Modal.Client.Behaviour

  use GenServer

  # The Modal API protocol version expected by Modal's servers.
  # This is NOT the library version — update it when Modal bumps the protocol.
  @modal_client_version "1.4.0"

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @impl Modal.Client.Behaviour
  def rpc(client, method, request, timeout \\ 30_000) do
    GenServer.call(client, {:rpc, method, request, timeout}, timeout + 5_000)
  end

  @impl Modal.Client.Behaviour
  def stream_rpc(client, method, request, timeout \\ 60_000) do
    GenServer.call(client, {:stream_rpc, method, request, timeout}, timeout + 5_000)
  end

  @impl Modal.Client.Behaviour
  def stream_rpc_each(client, method, request, callback, timeout \\ :infinity) do
    GenServer.call(client, {:stream_rpc_each, method, request, callback}, timeout)
  end

  @impl Modal.Client.Behaviour
  def stream_rpc_reduce(client, method, request, acc, reducer, timeout \\ :infinity) do
    GenServer.call(client, {:stream_rpc_reduce, method, request, acc, reducer}, timeout)
  end

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def init(opts) do
    server_url = Keyword.get(opts, :server_url, "https://api.modal.com")
    stub = Keyword.get(opts, :modal_stub, Modal.ModalStub.Real)
    max_concurrency = Keyword.get(opts, :max_concurrency, :infinity)

    credentials = %Modal.Client.Credentials{
      metadata: %{
        "x-modal-token-id" => Keyword.fetch!(opts, :token_id),
        "x-modal-token-secret" => Keyword.fetch!(opts, :token_secret),
        "x-modal-client-version" => @modal_client_version,
        "x-modal-client-type" => "1"
      }
    }

    # Per-client Task.Supervisor — no global names, no shared state.
    {:ok, task_sup} = Task.Supervisor.start_link()

    # The grpc library requires GRPC.Client.Supervisor to be running.
    # Start it if not already started (idempotent across multiple clients).
    ensure_grpc_supervisor()

    state = %{
      server_url: server_url,
      credentials: credentials,
      channel: nil,
      task_sup: task_sup,
      stub: stub,
      max_concurrency: max_concurrency,
      inflight: 0
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
    with_channel(state, from, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_rpc(state.stub, channel, metadata, method, request, timeout)
      end)
    end)
  end

  @impl true
  def handle_call({:stream_rpc, method, request, timeout}, from, state) do
    with_channel(state, from, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_stream_rpc(state.stub, channel, metadata, method, request, timeout)
      end)
    end)
  end

  @impl true
  def handle_call({:stream_rpc_each, method, request, callback}, from, state) do
    with_channel(state, from, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_stream_each(state.stub, channel, metadata, method, request, callback)
      end)
    end)
  end

  @impl true
  def handle_call({:stream_rpc_reduce, method, request, acc, reducer}, from, state) do
    with_channel(state, from, fn state ->
      dispatch(from, state, fn channel, metadata ->
        exec_stream_reduce(state.stub, channel, metadata, method, request, acc, reducer)
      end)
    end)
  end

  # Test-only ping to verify the GenServer mailbox is responsive.
  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :pong, state}

  # Gun notifies us when the connection drops — mark channel nil so the next
  # ensure_channel call reconnects.
  @impl true
  def handle_info({:gun_down, _, _, _, _}, state) do
    {:noreply, %{state | channel: nil}}
  end

  def handle_info({:gun_up, _, _}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  # A task signals a network-level failure so the GenServer can reconnect
  # before the next request.
  @impl true
  def handle_cast(:connection_failed, state) do
    {:noreply, reconnect(state)}
  end

  def handle_cast(:task_completed, state) do
    {:noreply, %{state | inflight: max(0, state.inflight - 1)}}
  end

  @impl true
  def terminate(_reason, state) do
    if match?(%GRPC.Channel{}, state[:channel]), do: GRPC.Stub.disconnect(state.channel)
    if state[:task_sup], do: Supervisor.stop(state.task_sup, :normal)
    :ok
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp with_channel(state, _from, fun) do
    case ensure_channel(state) do
      {:ok, state} -> fun.(state)
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  # ── Task dispatch ────────────────────────────────────────────────

  defp dispatch(from, state, _fun)
       when state.max_concurrency != :infinity and state.inflight >= state.max_concurrency do
    GenServer.reply(from, {:error, :overloaded})
    {:noreply, state}
  end

  defp dispatch(from, state, fun) do
    channel = state.channel
    metadata = state.credentials.metadata
    server = self()

    Task.Supervisor.start_child(state.task_sup, fn ->
      result = fun.(channel, metadata)
      if network_error?(result), do: GenServer.cast(server, :connection_failed)
      GenServer.cast(server, :task_completed)
      GenServer.reply(from, result)
    end)

    {:noreply, %{state | inflight: state.inflight + 1}}
  end

  defp network_error?({:error, {:network, _}}), do: true
  defp network_error?(_), do: false

  # ── RPC execution (runs inside Task) ────────────────────────────

  defp exec_rpc(stub, channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case stub.call(channel, method, request, opts) do
      {:ok, response} -> {:ok, response}
      {:error, %GRPC.RPCError{status: status, message: msg}} -> {:error, {:grpc, status, msg}}
      {:error, reason} -> {:error, {:network, reason}}
    end
  end

  defp exec_stream_rpc(stub, channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case stub.stream(channel, method, request, opts) do
      {:ok, enum} ->
        # Surface stream-level errors rather than silently dropping them.
        result =
          Enum.reduce_while(enum, {:ok, []}, fn
            {:ok, msg}, {:ok, acc} ->
              {:cont, {:ok, [msg | acc]}}

            {:error, %GRPC.RPCError{status: status, message: msg}}, _ ->
              {:halt, {:error, {:grpc, status, msg}}}

            _, acc ->
              {:cont, acc}
          end)

        case result do
          {:ok, items} -> {:ok, Enum.reverse(items)}
          error -> error
        end

      {:error, %GRPC.RPCError{status: status, message: msg}} ->
        {:error, {:grpc, status, msg}}

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end

  defp exec_stream_each(stub, channel, metadata, method, request, callback) do
    opts = [metadata: metadata]

    case stub.stream(channel, method, request, opts) do
      {:ok, enum} ->
        enum
        |> Stream.flat_map(fn
          {:ok, msg} -> [msg]
          _ -> []
        end)
        |> dispatch_stream_messages(callback)

        callback.(:done)
        :ok

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end

  defp dispatch_stream_messages(messages, callback) do
    Enum.reduce_while(messages, :ok, fn msg, _ ->
      if callback.({:data, msg}) == :halt, do: {:halt, :halted}, else: {:cont, :ok}
    end)
  end

  defp exec_stream_reduce(stub, channel, metadata, method, request, acc, reducer) do
    opts = [metadata: metadata]

    case stub.stream(channel, method, request, opts) do
      {:ok, enum} ->
        final =
          Enum.reduce_while(enum, acc, fn
            {:ok, msg}, acc ->
              reducer.(msg, acc)

            {:error, %GRPC.RPCError{status: s, message: m}}, _acc ->
              {:halt, {:error, {:grpc, s, m}}}

            _, acc ->
              {:cont, acc}
          end)

        case final do
          {:error, _} = err -> err
          acc -> {:ok, acc}
        end

      {:error, %GRPC.RPCError{status: status, message: msg}} ->
        {:error, {:grpc, status, msg}}

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end

  # ── GRPC infrastructure ──────────────────────────────────────────

  defp ensure_grpc_supervisor do
    case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  # ── Connection management ────────────────────────────────────────

  defp ensure_channel(%{channel: nil} = state), do: connect(state)
  defp ensure_channel(state), do: {:ok, state}

  defp connect(state) do
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
    if state.channel, do: GRPC.Stub.disconnect(state.channel)

    case connect(%{state | channel: nil}) do
      {:ok, state} -> state
      {:error, _, state} -> state
    end
  end
end
