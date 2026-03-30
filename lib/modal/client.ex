defmodule Modal.Client do
  @moduledoc """
  A gRPC connection to the Modal API.

  Wraps a `GRPC.Channel` to `api.modal.com`. Start one per set of
  credentials, pass it to `Modal.*` functions.

  ## Usage

      {:ok, client} = Modal.Client.start_link(
        token_id: "ak-...",
        token_secret: "as-..."
      )

      {:ok, sandboxes} = Modal.Sandbox.list(client)

  ## Supervision

      children = [
        {Modal.Client,
         name: MyApp.Modal,
         token_id: "...",
         token_secret: "..."}
      ]
  """

  use GenServer
  require Logger

  alias Modal.Client.ModalClient.Stub, as: ModalStub

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc false
  def rpc(client, method, request, timeout \\ 30_000) do
    GenServer.call(client, {:rpc, method, request, timeout}, timeout + 5_000)
  end

  @doc false
  def stream_rpc(client, method, request, timeout \\ 60_000) do
    GenServer.call(client, {:stream_rpc, method, request, timeout}, timeout + 5_000)
  end

  @doc false
  def stream_rpc_each(client, method, request, callback, timeout \\ :infinity) do
    GenServer.call(client, {:stream_rpc_each, method, request, callback}, timeout)
  end

  # ── GenServer ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    ensure_grpc_supervisor!()

    server_url = Keyword.get(opts, :server_url, "https://api.modal.com")

    metadata = %{
      "x-modal-token-id" => Keyword.fetch!(opts, :token_id),
      "x-modal-token-secret" => Keyword.fetch!(opts, :token_secret),
      "x-modal-client-version" => "1.4.0",
      "x-modal-client-type" => "1"
    }

    state = %{server_url: server_url, metadata: metadata, channel: nil}

    case connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, _, state} -> {:ok, state}
    end
  end

  @impl true
  def handle_call({:rpc, method, request, timeout}, _from, state) do
    with {:ok, state} <- ensure_channel(state) do
      {result, state} = do_rpc(state, method, request, timeout)
      {:reply, result, state}
    else
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stream_rpc, method, request, timeout}, _from, state) do
    with {:ok, state} <- ensure_channel(state) do
      {result, state} = do_stream_rpc(state, method, request, timeout)
      {:reply, result, state}
    else
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stream_rpc_each, method, request, callback}, _from, state) do
    with {:ok, state} <- ensure_channel(state) do
      {result, state} = do_stream_each(state, method, request, callback)
      {:reply, result, state}
    else
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:gun_down, _, _, _, _}, state), do: {:noreply, state}
  def handle_info({:gun_up, _, _}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{channel: ch}) when not is_nil(ch), do: GRPC.Stub.disconnect(ch)
  def terminate(_reason, _state), do: :ok

  # ── RPC execution ───────────────────────────────────────────────

  defp do_rpc(state, method, request, timeout) do
    opts = [metadata: state.metadata, timeout: timeout]

    case apply(ModalStub, method, [state.channel, request, opts]) do
      {:ok, response} ->
        {{:ok, response}, state}

      {:error, %GRPC.RPCError{status: status, message: msg}} ->
        {{:error, {:grpc, status, msg}}, state}

      {:error, reason} ->
        {{:error, reason}, reconnect(state)}
    end
  end

  defp do_stream_rpc(state, method, request, timeout) do
    opts = [metadata: state.metadata, timeout: timeout]

    case apply(ModalStub, method, [state.channel, request, opts]) do
      {:ok, enum} ->
        items =
          enum
          |> Enum.flat_map(fn
            {:ok, msg} -> [msg]
            _ -> []
          end)

        {{:ok, items}, state}

      {:error, %GRPC.RPCError{status: status, message: msg}} ->
        {{:error, {:grpc, status, msg}}, state}

      {:error, reason} ->
        {{:error, reason}, reconnect(state)}
    end
  end

  defp do_stream_each(state, method, request, callback) do
    opts = [metadata: state.metadata]

    case apply(ModalStub, method, [state.channel, request, opts]) do
      {:ok, enum} ->
        enum
        |> Stream.flat_map(fn
          {:ok, msg} -> [msg]
          _ -> []
        end)
        |> Enum.each(fn msg ->
          callback.({:data, msg})
        end)

        callback.(:done)
        {:ok, state}

      {:error, reason} ->
        {{:error, reason}, reconnect(state)}
    end
  end

  # ── Connection management ───────────────────────────────────────

  defp ensure_channel(%{channel: nil} = state), do: connect(state)
  defp ensure_channel(state), do: {:ok, state}

  defp connect(state) do
    cred =
      GRPC.Credential.new(
        ssl: [cacerts: :public_key.cacerts_get(), verify: :verify_peer, depth: 4]
      )

    case GRPC.Stub.connect(state.server_url, cred: cred) do
      {:ok, channel} ->
        Logger.debug("[modal] connected to #{state.server_url}")
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

  defp ensure_grpc_supervisor! do
    unless Process.whereis(GRPC.Client.Supervisor) do
      DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor)
    end
  end
end
