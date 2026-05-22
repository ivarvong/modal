defmodule Modal.Sandbox do
  @moduledoc """
  Modal Sandbox lifecycle.

      sandbox = Modal.Sandbox.create!(client, app_id: app_id, cmd: ["sleep", "infinity"])

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Modal.ContainerProcess.stream() |> Enum.each(&IO.write/1)
      Modal.ContainerProcess.exit_code(proc)  #=> {:ok, 0}

      Modal.Sandbox.terminate(sandbox)
  """

  alias Modal.RPC

  defstruct [:id, :client, :task_id]

  @type t :: %__MODULE__{
          id: String.t(),
          client: GenServer.server(),
          # Populated after the first get_task_id/1 call. Pass the returned
          # sandbox value to subsequent operations to avoid repeat RPCs.
          task_id: String.t() | nil
        }

  # GRPC status code 4 = DEADLINE_EXCEEDED — how SandboxWait(timeout: 0)
  # signals "still running" rather than an actual error.
  @grpc_deadline_exceeded 4

  @create_opts [
    app_id: [type: :string, required: true],
    cmd: [type: {:list, :string}, default: []],
    image_id: [type: :string, default: ""],
    timeout: [type: :pos_integer, default: 300],
    idle_timeout: [type: :non_neg_integer, default: 0],
    name: [type: :string, default: ""],
    workdir: [type: :string, default: "/root"],
    memory_mb: [type: :non_neg_integer, default: 0],
    # Fractional CPU cores, matching Python SDK convention (e.g. 0.5, 1.0, 2.0).
    # Accepts integer or float; converted to millicores internally.
    cpu: [type: {:or, [:float, :integer]}, default: 0],
    gpu: [type: :string],
    gpu_count: [type: :pos_integer, default: 1],
    disk_mb: [type: :non_neg_integer, default: 0],
    ports: [type: {:list, :pos_integer}, default: []],
    volumes: [type: {:list, :any}, default: []],
    # Accepts a single region string or a list of strings.
    regions: [type: {:or, [:string, {:list, :string}]}],
    secret_ids: [type: {:list, :string}, default: []],
    snapshot: [type: :boolean, default: false],
    block_network: [type: :boolean, default: false],
    verbose: [type: :boolean, default: false]
  ]

  # ── Lifecycle ───────────────────────────────────────────────────

  @doc """
  Create a sandbox. Returns `{:ok, %Modal.Sandbox{}}`.

  ## Options

  #{NimbleOptions.docs(@create_opts)}
  """
  @spec create(GenServer.server(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(client, opts) do
    opts = coerce_opts(opts)

    with {:ok, validated} <- NimbleOptions.validate(opts, @create_opts),
         request = %Modal.Client.SandboxCreateRequest{
           app_id: validated[:app_id],
           definition: build_definition(validated)
         },
         {:ok, resp} <- RPC.call(client, :SandboxCreate, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
    end
  end

  @doc "Like `create/2` but raises on error."
  @spec create!(GenServer.server(), keyword()) :: t()
  def create!(client, opts) do
    case create(client, opts) do
      {:ok, sandbox} -> sandbox
      {:error, reason} -> raise "Modal.Sandbox.create! failed: #{inspect(reason)}"
    end
  end

  @doc "Terminate a sandbox."
  @spec terminate(t()) :: :ok | {:error, term()}
  def terminate(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxTerminateRequest{sandbox_id: sb.id}
    with {:ok, _} <- RPC.call(sb.client, :SandboxTerminate, request), do: :ok
  end

  @doc "Wait for sandbox to finish."
  @spec wait(t(), keyword()) :: {:ok, term()} | {:error, term()}
  def wait(%__MODULE__{} = sb, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30.0)
    request = %Modal.Client.SandboxWaitRequest{sandbox_id: sb.id, timeout: timeout}
    RPC.call(sb.client, :SandboxWait, request)
  end

  @doc """
  Non-blocking status check. Returns `{:ok, nil}` if still running,
  `{:ok, result}` if finished.
  """
  @spec poll(t()) :: {:ok, term() | nil} | {:error, term()}
  def poll(%__MODULE__{} = sb) do
    case wait(sb, timeout: 0.0) do
      {:ok, %{result: nil}} -> {:ok, nil}
      {:ok, resp} -> {:ok, resp}
      {:error, {:grpc, @grpc_deadline_exceeded, _}} -> {:ok, nil}
      other -> other
    end
  end

  @doc "Wait until ready (passes readiness probe)."
  @spec wait_until_ready(t(), keyword()) :: :ok | {:error, term()}
  def wait_until_ready(%__MODULE__{} = sb, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120.0)

    request = %Modal.Client.SandboxWaitUntilReadyRequest{
      sandbox_id: sb.id,
      timeout: timeout
    }

    with {:ok, _} <- RPC.call(sb.client, :SandboxWaitUntilReady, request), do: :ok
  end

  @doc """
  Get task ID (waits for boot).

  Returns `{:ok, task_id, sandbox}` where `sandbox` has the `task_id` field
  populated. Pass the returned sandbox to subsequent operations — filesystem
  functions will use the cached value directly, avoiding repeat RPCs.

      {:ok, task_id, sandbox} = Modal.Sandbox.get_task_id(sandbox)
      :ok = Modal.Sandbox.write_file(sandbox, "/tmp/a.txt", "hello")
      :ok = Modal.Sandbox.write_file(sandbox, "/tmp/b.txt", "world")
  """
  @spec get_task_id(t()) :: {:ok, String.t(), t()} | {:error, term()}
  def get_task_id(%__MODULE__{task_id: task_id} = sb) when not is_nil(task_id) do
    {:ok, task_id, sb}
  end

  def get_task_id(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxGetTaskIdRequest{
      sandbox_id: sb.id,
      timeout: 30.0,
      wait_until_ready: true
    }

    with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTaskId, request) do
      {:ok, resp.task_id, %{sb | task_id: resp.task_id}}
    end
  end

  @doc "Look up by name."
  @spec from_name(GenServer.server(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_name(client, name, opts \\ []) do
    request = %Modal.Client.SandboxGetFromNameRequest{
      sandbox_name: name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      app_name: Keyword.get(opts, :app_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :SandboxGetFromName, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
    end
  end

  @doc "List sandboxes."
  @spec list(GenServer.server(), keyword()) :: {:ok, list()} | {:error, term()}
  def list(client, opts \\ []) do
    request = %Modal.Client.SandboxListRequest{
      app_id: Keyword.get(opts, :app_id, ""),
      include_finished: Keyword.get(opts, :include_finished, false),
      environment_name: Keyword.get(opts, :environment_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :SandboxList, request) do
      {:ok, resp.sandboxes}
    end
  end

  # ── Exec ────────────────────────────────────────────────────────

  @doc """
  Execute a command. Returns `{:ok, %Modal.ContainerProcess{}}` or
  `{:error, reason}`.

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)
  """
  @spec exec(t(), [String.t()], keyword()) ::
          {:ok, Modal.ContainerProcess.t()} | {:error, term()}
  def exec(%__MODULE__{} = sb, command, opts \\ []) do
    Modal.ContainerProcess.start(sb, command, opts)
  end

  @doc "Like `exec/3` but raises on error."
  @spec exec!(t(), [String.t()], keyword()) :: Modal.ContainerProcess.t()
  def exec!(%__MODULE__{} = sb, command, opts \\ []) do
    case exec(sb, command, opts) do
      {:ok, proc} -> proc
      {:error, reason} -> raise "Modal.Sandbox.exec! failed: #{inspect(reason)}"
    end
  end

  # ── Stdin ───────────────────────────────────────────────────────

  @doc "Write to sandbox entrypoint stdin."
  @spec stdin_write(t(), binary(), keyword()) :: :ok | {:error, term()}
  def stdin_write(%__MODULE__{} = sb, data, opts \\ []) do
    request = %Modal.Client.SandboxStdinWriteRequest{
      sandbox_id: sb.id,
      input: data,
      index: Keyword.get(opts, :index, 0),
      eof: Keyword.get(opts, :eof, false)
    }

    with {:ok, _} <- RPC.call(sb.client, :SandboxStdinWrite, request), do: :ok
  end

  # ── Logs ────────────────────────────────────────────────────────

  @doc "Fetch sandbox logs."
  @spec get_logs(t(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_logs(%__MODULE__{} = sb, opts \\ []) do
    request = %Modal.Client.SandboxGetLogsRequest{
      sandbox_id: sb.id,
      file_descriptor: Keyword.get(opts, :file_descriptor, :FILE_DESCRIPTOR_STDOUT),
      timeout: Keyword.get(opts, :timeout, 55.0),
      last_entry_id: Keyword.get(opts, :last_entry_id, "")
    }

    RPC.stream(sb.client, :SandboxGetLogs, request)
  end

  # ── Tunnels ─────────────────────────────────────────────────────

  @doc "Get tunnel URLs."
  @spec tunnels(t()) :: {:ok, list()} | {:error, term()}
  def tunnels(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxGetTunnelsRequest{sandbox_id: sb.id, timeout: 30.0}

    with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTunnels, request) do
      {:ok, resp.tunnels}
    end
  end

  @doc "Get an HTTP connect token."
  @spec connect_token(t(), keyword()) ::
          {:ok, %{url: String.t(), token: String.t()}} | {:error, term()}
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

  @doc "Read a file from the sandbox."
  defdelegate read_file(sandbox, path), to: Modal.Filesystem

  @doc "Read a file from the sandbox, raising on error."
  defdelegate read_file!(sandbox, path), to: Modal.Filesystem

  @doc "Write a file to the sandbox."
  defdelegate write_file(sandbox, path, content), to: Modal.Filesystem

  @doc "Write a file to the sandbox, raising on error."
  defdelegate write_file!(sandbox, path, content), to: Modal.Filesystem

  @doc "List a directory."
  defdelegate ls(sandbox, path \\ "/"), to: Modal.Filesystem

  @doc "Create a directory."
  defdelegate mkdir(sandbox, path, opts \\ []), to: Modal.Filesystem

  @doc "Remove a file or directory."
  defdelegate rm(sandbox, path, opts \\ []), to: Modal.Filesystem

  # ── Snapshots ───────────────────────────────────────────────────

  @doc "Snapshot a running sandbox (full VM). Returns `{:ok, snapshot_id}`."
  @spec snapshot(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def snapshot(%__MODULE__{} = sb, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 55.0)

    with {:ok, resp} <-
           RPC.call(sb.client, :SandboxSnapshot, %Modal.Client.SandboxSnapshotRequest{
             sandbox_id: sb.id
           }),
         {:ok, wait_resp} <-
           RPC.call(sb.client, :SandboxSnapshotWait, %Modal.Client.SandboxSnapshotWaitRequest{
             snapshot_id: resp.snapshot_id,
             timeout: timeout
           }) do
      if wait_resp.result && wait_resp.result.status == :GENERIC_STATUS_SUCCESS do
        {:ok, resp.snapshot_id}
      else
        {:error, {:snapshot_failed, wait_resp.result && wait_resp.result.status}}
      end
    end
  end

  @doc "Restore from snapshot."
  @spec restore(GenServer.server(), String.t()) :: {:ok, t()} | {:error, term()}
  def restore(client, snapshot_id) do
    request = %Modal.Client.SandboxRestoreRequest{snapshot_id: snapshot_id}

    with {:ok, resp} <- RPC.call(client, :SandboxRestore, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
    end
  end

  @doc "Snapshot filesystem as a reusable image. Returns `{:ok, image_id}`."
  @spec snapshot_filesystem(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def snapshot_filesystem(%__MODULE__{} = sb, opts \\ []) do
    request = %Modal.Client.SandboxSnapshotFsRequest{
      sandbox_id: sb.id,
      timeout: Keyword.get(opts, :timeout, 55.0)
    }

    with {:ok, resp} <- RPC.call(sb.client, :SandboxSnapshotFs, request) do
      if resp.result && resp.result.status == :GENERIC_STATUS_SUCCESS do
        {:ok, resp.image_id}
      else
        {:error, {:snapshot_fs_failed, resp.result && resp.result.status}}
      end
    end
  end

  # ── Option coercions (pre-NimbleOptions) ────────────────────────

  # Coerce regions: accept a single string and normalise to a list,
  # matching Python SDK behaviour (region="us-east" or region=["us-east"]).
  defp coerce_opts(opts) do
    case Keyword.get(opts, :regions) do
      r when is_binary(r) -> Keyword.put(opts, :regions, [r])
      _ -> opts
    end
  end

  # ── Definition builder ──────────────────────────────────────────

  defp build_definition(opts) do
    %Modal.Client.Sandbox{
      entrypoint_args: opts[:cmd],
      image_id: opts[:image_id],
      timeout_secs: opts[:timeout],
      idle_timeout_secs: opts[:idle_timeout],
      name: opts[:name],
      workdir: opts[:workdir],
      block_network: opts[:block_network],
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

    if opts[:memory_mb] > 0 or opts[:cpu] != 0 or opts[:disk_mb] > 0 or gpu do
      %Modal.Client.Resources{
        memory_mb: opts[:memory_mb],
        milli_cpu: trunc(opts[:cpu] * 1000),
        gpu_config: gpu,
        ephemeral_disk_mb: opts[:disk_mb]
      }
    end
  end

  defp build_ports(opts) do
    case opts[:ports] do
      [] ->
        nil

      ports ->
        {:open_ports,
         %Modal.Client.PortSpecs{ports: Enum.map(ports, &%Modal.Client.PortSpec{port: &1})}}
    end
  end

  defp build_volume(v) when is_map(v) do
    %Modal.Client.VolumeMount{
      volume_id: Map.get(v, :id) || Map.get(v, "id"),
      mount_path: Map.get(v, :path) || Map.get(v, "path"),
      read_only: Map.get(v, :read_only, false)
    }
  end

  defp build_scheduler(opts) do
    case opts[:regions] do
      nil -> nil
      regions when is_list(regions) -> %Modal.Client.SchedulerPlacement{regions: regions}
    end
  end

  # ── Inspect — show only sandbox ID, redact client ───────────────

  defimpl Inspect do
    def inspect(%Modal.Sandbox{} = sb, _opts) do
      "#Modal.Sandbox<id: #{sb.id}>"
    end
  end
end
