defmodule Modal.DataPlane do
  @moduledoc """
  Direct gRPC connection to a sandbox worker.

  Low-latency exec with offset-based stdout resumption and infinite
  retry on `exec_wait`.

      {:ok, dp} = Modal.DataPlane.start_link(client, sandbox_id)
      {:ok, result} = Modal.DataPlane.exec_run(dp, ["echo", "hello"])
      result.stdout  #=> "hello\\n"
  """

  use GenServer, restart: :transient
  require Logger

  alias Modal.TaskCommandRouter, as: TCR
  alias Modal.TaskCommandRouter.TaskCommandRouter.Stub, as: TCRStub

  @jwt_refresh_buffer_secs 30
  @wait_attempt_timeout 60_000
  @wait_retry_delay 1_000
  @stdio_max_retries 10
  @stdio_base_delay 10

  # ── Public API ──────────────────────────────────────────────────

  def start_link(client, sandbox_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {client, sandbox_id, opts})
  end

  def exec_start(dp, command, opts \\ []),
    do: GenServer.call(dp, {:exec_start, command, opts}, 30_000)

  def exec_wait(dp, exec_id, timeout \\ :infinity),
    do: GenServer.call(dp, {:exec_wait, exec_id}, timeout)

  def exec_run(dp, command, opts \\ []),
    do: GenServer.call(dp, {:exec_run, command, opts}, Keyword.get(opts, :timeout, 600_000))

  def exec_stdin_write(dp, exec_id, data, opts \\ []),
    do: GenServer.call(dp, {:exec_stdin_write, exec_id, data, opts}, 30_000)

  def exec_stdio_read(dp, exec_id, opts \\ []),
    do: GenServer.call(dp, {:exec_stdio_read, exec_id, opts}, 120_000)

  @doc "Start a stdio stream process for Enumerable consumption."
  def exec_stdio_stream(dp, exec_id) do
    GenServer.call(dp, {:exec_stdio_stream, exec_id}, 10_000)
  end

  # ── GenServer ───────────────────────────────────────────────────

  defmodule State do
    @moduledoc false
    defstruct [:client, :sandbox_id, :task_id, :channel, :jwt, :jwt_exp, :url, exec_counter: 0]
  end

  @impl true
  def init({client, sandbox_id, _opts}) do
    state = %State{client: client, sandbox_id: sandbox_id, jwt_exp: 0}

    case connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, {:connect_failed, reason}}
    end
  end

  @impl true
  def handle_call({:exec_start, command, opts}, _from, state) do
    state = refresh_jwt_if_needed(state)
    {exec_id, state} = next_exec_id(state)

    request = %TCR.TaskExecStartRequest{
      task_id: state.task_id,
      exec_id: exec_id,
      command_args: command,
      stdout_config: :TASK_EXEC_STDOUT_CONFIG_PIPE,
      stderr_config: :TASK_EXEC_STDERR_CONFIG_PIPE,
      timeout_secs: Keyword.get(opts, :timeout_secs, 300),
      workdir: Keyword.get(opts, :workdir, "")
    }

    case rpc(state, :task_exec_start, request) do
      {:ok, _, state} -> {:reply, {:ok, exec_id}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:exec_wait, exec_id}, _from, state) do
    {result, state} = wait_loop(state, exec_id, 0)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:exec_run, command, opts}, _from, state) do
    state = refresh_jwt_if_needed(state)
    {exec_id, state} = next_exec_id(state)

    start_req = %TCR.TaskExecStartRequest{
      task_id: state.task_id,
      exec_id: exec_id,
      command_args: command,
      stdout_config: :TASK_EXEC_STDOUT_CONFIG_PIPE,
      stderr_config: :TASK_EXEC_STDERR_CONFIG_PIPE,
      timeout_secs: Keyword.get(opts, :timeout_secs, 300),
      workdir: Keyword.get(opts, :workdir, "")
    }

    case rpc(state, :task_exec_start, start_req) do
      {:ok, _, state} ->
        {wait_result, state} = wait_loop(state, exec_id, 0)

        case wait_result do
          {:ok, %{code: code}} ->
            {stdout, state} = read_stdio(state, exec_id, 0, 0)
            {:reply, {:ok, %{code: code, stdout: stdout, exec_id: exec_id}}, state}

          error ->
            {:reply, error, state}
        end

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:exec_stdin_write, exec_id, data, opts}, _from, state) do
    request = %TCR.TaskExecStdinWriteRequest{
      task_id: state.task_id,
      exec_id: exec_id,
      offset: Keyword.get(opts, :offset, 0),
      data: data,
      eof: Keyword.get(opts, :eof, false)
    }

    case rpc(state, :task_exec_stdin_write, request) do
      {:ok, _, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:exec_stdio_read, exec_id, _opts}, _from, state) do
    {data, state} = read_stdio(state, exec_id, 0, 0)
    {:reply, {:ok, data}, state}
  end

  @impl true
  def handle_call({:exec_stdio_stream, exec_id}, _from, state) do
    state = ensure_channel(state)

    if state.channel do
      {:ok, pid} =
        Modal.DataPlane.StdioStream.start_link(
          state.channel,
          state.task_id,
          exec_id,
          auth_meta(state)
        )

      {:reply, {:ok, pid}, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[modal.dp] ignoring: #{inspect(msg, limit: 3)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{channel: ch}) when not is_nil(ch), do: GRPC.Stub.disconnect(ch)
  def terminate(_reason, _state), do: :ok

  # ── Wait loop: infinite retry, 60s per attempt ─────────────────

  defp wait_loop(state, exec_id, attempts) do
    state = ensure_channel(state)

    if is_nil(state.channel) do
      if attempts > 100 do
        {{:error, :not_connected}, state}
      else
        Process.sleep(@wait_retry_delay)
        wait_loop(state, exec_id, attempts + 1)
      end
    else
      request = %TCR.TaskExecWaitRequest{task_id: state.task_id, exec_id: exec_id}
      opts = [metadata: auth_meta(state), timeout: @wait_attempt_timeout]

      case TCRStub.task_exec_wait(state.channel, request, opts) do
        {:ok, resp} ->
          {{:ok, %{code: exit_code(resp.exit_status)}}, state}

        {:error, _} ->
          state = reconnect(state)
          Process.sleep(@wait_retry_delay)
          wait_loop(state, exec_id, attempts + 1)
      end
    end
  end

  # ── Stdio read: offset-based resumption ─────────────────────────

  defp read_stdio(state, exec_id, offset, retries) do
    state = ensure_channel(state)

    if is_nil(state.channel) or retries > @stdio_max_retries do
      {"", state}
    else
      request = %TCR.TaskExecStdioReadRequest{
        task_id: state.task_id,
        exec_id: exec_id,
        offset: offset
      }

      opts = [metadata: auth_meta(state)]

      case TCRStub.task_exec_stdio_read(state.channel, request, opts) do
        {:ok, enum} ->
          collect_stdio(state, enum, exec_id, offset, [], retries)

        {:error, _} ->
          state = reconnect(state)
          delay = @stdio_base_delay * Integer.pow(2, retries)
          Process.sleep(min(delay, 5_000))
          read_stdio(state, exec_id, offset, retries + 1)
      end
    end
  end

  defp collect_stdio(state, enum, exec_id, offset, acc, retries) do
    try do
      {final_offset, chunks} =
        Enum.reduce(enum, {offset, acc}, fn
          {:ok, resp}, {off, chunks} -> {off + byte_size(resp.data), [resp.data | chunks]}
          _, {off, chunks} -> throw({:stream_error, off, chunks})
        end)

      _ = final_offset
      {chunks |> Enum.reverse() |> IO.iodata_to_binary(), state}
    catch
      {:stream_error, new_offset, chunks} ->
        if retries < @stdio_max_retries do
          state = reconnect(state)
          {more, state} = read_stdio(state, exec_id, new_offset, retries + 1)
          {[Enum.reverse(chunks), more] |> IO.iodata_to_binary(), state}
        else
          {chunks |> Enum.reverse() |> IO.iodata_to_binary(), state}
        end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp rpc(state, method, request) do
    state = ensure_channel(state)

    if is_nil(state.channel) do
      {:error, :not_connected, state}
    else
      case apply(TCRStub, method, [state.channel, request, [metadata: auth_meta(state)]]) do
        {:ok, resp} -> {:ok, resp, state}
        {:error, %GRPC.RPCError{status: s, message: m}} -> {:error, {:grpc, s, m}, state}
        {:error, reason} -> {:error, reason, reconnect(state)}
      end
    end
  end

  defp next_exec_id(state) do
    n = state.exec_counter + 1
    {"ex-#{n}-#{System.unique_integer([:positive])}", %{state | exec_counter: n}}
  end

  defp auth_meta(state), do: %{"authorization" => "Bearer #{state.jwt}"}

  defp exit_code({:code, c}), do: c
  defp exit_code({:signal, s}), do: 128 + s
  defp exit_code(_), do: nil

  # ── Connection ──────────────────────────────────────────────────

  defp ensure_channel(%{channel: nil} = state) do
    case connect(state) do
      {:ok, s} -> s
      {:error, _} -> state
    end
  end

  defp ensure_channel(state), do: state

  defp reconnect(state) do
    if state.channel, do: GRPC.Stub.disconnect(state.channel)

    case connect(%{state | channel: nil}) do
      {:ok, s} -> s
      {:error, _} -> %{state | channel: nil}
    end
  end

  defp connect(state) do
    sb = %Modal.Sandbox{id: state.sandbox_id, client: state.client}

    with {:ok, task_id} <- Modal.Sandbox.get_task_id(sb),
         {:ok, resp} <-
           Modal.Client.rpc(
             state.client,
             :task_get_command_router_access,
             %Modal.Client.TaskGetCommandRouterAccessRequest{task_id: task_id}
           ),
         {:ok, channel} <-
           GRPC.Stub.connect(resp.url,
             cred:
               GRPC.Credential.new(
                 ssl: [cacerts: :public_key.cacerts_get(), verify: :verify_peer, depth: 4]
               ),
             headers: [{"authorization", "Bearer #{resp.jwt}"}]
           ) do
      {:ok,
       %{
         state
         | task_id: task_id,
           channel: channel,
           jwt: resp.jwt,
           jwt_exp: Modal.JWT.parse_exp(resp.jwt),
           url: resp.url
       }}
    end
  end

  defp refresh_jwt_if_needed(%{jwt_exp: exp} = state) do
    if System.system_time(:second) > exp - @jwt_refresh_buffer_secs do
      if state.channel, do: GRPC.Stub.disconnect(state.channel)

      case connect(%{state | channel: nil}) do
        {:ok, state} -> state
        {:error, _} -> state
      end
    else
      state
    end
  end
end
