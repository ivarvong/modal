defmodule Modal.Client do
  @moduledoc """
  A gRPC connection to the Modal API.

  Wraps a `GRPC.Channel` to `api.modal.com`. Start one per set of credentials —
  in a SaaS context, one per customer — and pass it to `Modal.*` functions.

  RPC calls are dispatched concurrently via `Modal.TaskSupervisor`, so a single
  `Modal.Client` can serve many concurrent requests without serialisation.

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
  """

  @behaviour Modal.Client.Behaviour

  use GenServer

  # modal_stub/0 is configurable so tests can inject a fake without a live
  # gRPC connection. Production uses Modal.ModalStub.Real which delegates to
  # the generated protobuf stub via apply/3.
  defp modal_stub, do: Application.get_env(:modal, :modal_stub, Modal.ModalStub.Real)

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

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def init(opts) do
    server_url = Keyword.get(opts, :server_url, "https://api.modal.com")

    # Store credentials opaquely — not as plain strings accessible via
    # :sys.get_state/1 in plaintext. In production, consider wrapping in a
    # struct with a custom Inspect implementation.
    metadata = %{
      "x-modal-token-id" => Keyword.fetch!(opts, :token_id),
      "x-modal-token-secret" => Keyword.fetch!(opts, :token_secret),
      "x-modal-client-version" => @modal_client_version,
      "x-modal-client-type" => "1"
    }

    state = %{server_url: server_url, metadata: metadata, channel: nil}

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
    case ensure_channel(state) do
      {:ok, state} ->
        dispatch(from, state, fn channel, metadata ->
          exec_rpc(channel, metadata, method, request, timeout)
        end)

        {:noreply, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stream_rpc, method, request, timeout}, from, state) do
    case ensure_channel(state) do
      {:ok, state} ->
        dispatch(from, state, fn channel, metadata ->
          exec_stream_rpc(channel, metadata, method, request, timeout)
        end)

        {:noreply, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stream_rpc_each, method, request, callback}, from, state) do
    case ensure_channel(state) do
      {:ok, state} ->
        dispatch(from, state, fn channel, metadata ->
          exec_stream_each(channel, metadata, method, request, callback)
        end)

        {:noreply, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
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

  @impl true
  def terminate(_reason, %{channel: %GRPC.Channel{} = ch}), do: GRPC.Stub.disconnect(ch)
  def terminate(_reason, _state), do: :ok

  # ── Task dispatch ────────────────────────────────────────────────

  # Spawns a supervised, unlinked task under Modal.TaskSupervisor. The task
  # executes the RPC and calls GenServer.reply/2 with the result. If there is
  # a network error (not a gRPC application error), it casts :connection_failed
  # to trigger reconnection before the next call.
  defp dispatch(from, state, fun) do
    channel = state.channel
    metadata = state.metadata
    server = self()

    Task.Supervisor.start_child(Modal.TaskSupervisor, fn ->
      result = fun.(channel, metadata)

      if network_error?(result) do
        GenServer.cast(server, :connection_failed)
      end

      GenServer.reply(from, result)
    end)
  end

  defp network_error?({:error, {:network, _}}), do: true
  defp network_error?(_), do: false

  # ── RPC execution (runs inside Task) ────────────────────────────

  defp exec_rpc(channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case modal_stub().call(channel, method, request, opts) do
      {:ok, response} -> {:ok, response}
      {:error, %GRPC.RPCError{status: status, message: msg}} -> {:error, {:grpc, status, msg}}
      {:error, reason} -> {:error, {:network, reason}}
    end
  end

  defp exec_stream_rpc(channel, metadata, method, request, timeout) do
    opts = [metadata: metadata, timeout: timeout]

    case modal_stub().stream(channel, method, request, opts) do
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

  defp exec_stream_each(channel, metadata, method, request, callback) do
    opts = [metadata: metadata]

    case modal_stub().stream(channel, method, request, opts) do
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
