defmodule Modal.Sandbox do
  @moduledoc """
  Modal Sandbox lifecycle.

      sandbox = Modal.Sandbox.create!(client, app_id: app_id, cmd: ["sleep", "infinity"])

      proc = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      Modal.Process.exit_code(proc)  #=> {:ok, 0}

      Modal.Sandbox.terminate(sandbox)
  """

  alias Modal.RPC

  defstruct [:id, :client]

  @type t :: %__MODULE__{id: String.t(), client: GenServer.server()}

  @create_opts [
    app_id: [type: :string, required: true],
    cmd: [type: {:list, :string}, default: []],
    image_id: [type: :string, default: ""],
    timeout: [type: :pos_integer, default: 300],
    idle_timeout: [type: :non_neg_integer, default: 0],
    name: [type: :string, default: ""],
    workdir: [type: :string, default: "/root"],
    memory_mb: [type: :non_neg_integer, default: 0],
    cpu: [type: :non_neg_integer, default: 0],
    gpu: [type: :string],
    gpu_count: [type: :pos_integer, default: 1],
    disk_mb: [type: :non_neg_integer, default: 0],
    ports: [type: {:list, :pos_integer}, default: []],
    volumes: [type: {:list, :any}, default: []],
    regions: [type: {:list, :string}],
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
  def create(client, opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @create_opts) do
      request = %Modal.Client.SandboxCreateRequest{
        app_id: validated[:app_id],
        definition: build_definition(validated)
      }

      with {:ok, resp} <- RPC.call(client, :SandboxCreate, request) do
        {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
      end
    end
  end

  @doc "Like `create/2` but raises on error."
  def create!(client, opts) do
    case create(client, opts) do
      {:ok, sandbox} -> sandbox
      {:error, reason} -> raise "Modal.Sandbox.create failed: #{inspect(reason)}"
    end
  end

  @doc "Terminate a sandbox."
  def terminate(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxTerminateRequest{sandbox_id: sb.id}
    with {:ok, _} <- RPC.call(sb.client, :SandboxTerminate, request), do: :ok
  end

  @doc "Wait for sandbox to finish."
  def wait(%__MODULE__{} = sb, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30.0)
    request = %Modal.Client.SandboxWaitRequest{sandbox_id: sb.id, timeout: timeout}
    RPC.call(sb.client, :SandboxWait, request)
  end

  @doc "Non-blocking status check."
  def poll(%__MODULE__{} = sb) do
    case wait(sb, timeout: 0.0) do
      {:ok, %{result: nil}} -> {:ok, nil}
      {:ok, resp} -> {:ok, resp}
      {:error, {:grpc, 4, _}} -> {:ok, nil}
      other -> other
    end
  end

  @doc "Wait until ready (passes readiness probe)."
  def wait_until_ready(%__MODULE__{} = sb, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120.0)

    request = %Modal.Client.SandboxWaitUntilReadyRequest{
      sandbox_id: sb.id,
      timeout: timeout
    }

    with {:ok, _} <- RPC.call(sb.client, :SandboxWaitUntilReady, request), do: :ok
  end

  @doc "Get task ID (waits for boot)."
  def get_task_id(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxGetTaskIdRequest{
      sandbox_id: sb.id,
      timeout: 30.0,
      wait_until_ready: true
    }

    with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTaskId, request) do
      {:ok, resp.task_id}
    end
  end

  @doc "Look up by name."
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
  Execute a command. Returns a `Modal.ContainerProcess`.

      proc = Modal.Sandbox.exec(sandbox, ["pytest", "-v"])
      proc |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)
  """
  def exec(%__MODULE__{} = sb, command, opts \\ []) do
    Modal.ContainerProcess.start(sb, command, opts)
  end

  # ── Stdin ───────────────────────────────────────────────────────

  @doc "Write to sandbox entrypoint stdin."
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
  def tunnels(%__MODULE__{} = sb) do
    request = %Modal.Client.SandboxGetTunnelsRequest{sandbox_id: sb.id, timeout: 30.0}

    with {:ok, resp} <- RPC.call(sb.client, :SandboxGetTunnels, request) do
      {:ok, resp.tunnels}
    end
  end

  @doc "Get an HTTP connect token."
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

  @doc "Write a file to the sandbox."
  defdelegate write_file(sandbox, path, content), to: Modal.Filesystem

  @doc "List a directory."
  defdelegate ls(sandbox, path \\ "/"), to: Modal.Filesystem

  @doc "Create a directory."
  defdelegate mkdir(sandbox, path, opts \\ []), to: Modal.Filesystem

  @doc "Remove a file or directory."
  defdelegate rm(sandbox, path, opts \\ []), to: Modal.Filesystem

  # ── Snapshots ───────────────────────────────────────────────────

  @doc "Snapshot a running sandbox (full VM). Returns `{:ok, snapshot_id}`."
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
  def restore(client, snapshot_id) do
    request = %Modal.Client.SandboxRestoreRequest{snapshot_id: snapshot_id}

    with {:ok, resp} <- RPC.call(client, :SandboxRestore, request) do
      {:ok, %__MODULE__{id: resp.sandbox_id, client: client}}
    end
  end

  @doc "Snapshot filesystem as a reusable image. Returns `{:ok, image_id}`."
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

    if opts[:memory_mb] > 0 or opts[:cpu] > 0 or opts[:disk_mb] > 0 or gpu do
      %Modal.Client.Resources{
        memory_mb: opts[:memory_mb],
        milli_cpu: opts[:cpu],
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
      regions -> %Modal.Client.SchedulerPlacement{regions: regions}
    end
  end
end
