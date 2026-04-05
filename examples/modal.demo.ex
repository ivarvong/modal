defmodule Mix.Tasks.Modal.Demo do
  @moduledoc "Demonstrates a Ramp-style coding agent workflow using Modal Sandboxes."
  @shortdoc "Clone a repo, install deps, snapshot, restore, run tests"
  use Mix.Task

  import Modal.MixHelpers

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {token_id, token_secret} = credentials!()

    connect = fn ->
      {:ok, c} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
      c
    end

    client = connect.()
    {:ok, app_id} = Modal.App.lookup(client, "elixir-demo")

    step("Building image")
    t0 = now()

    {:ok, image_id, image_status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM hexpm/elixir:1.19.4-erlang-26.2.5.3-debian-bullseye-20260316-slim",
          "RUN apt-get update && apt-get install -y git build-essential python3 && rm -rf /var/lib/apt/lists/*",
          "RUN mix local.hex --force && mix local.rebar --force"
        ],
        app_id: app_id
      )

    info("image: #{image_id} [#{image_status}] (#{elapsed(t0)})")

    header("PHASE 1: Build from scratch")

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout: 600,
        idle_timeout: 120
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("Cloning ivarvong/pyex")
    run!(sandbox, "git clone --depth=1 https://github.com/ivarvong/pyex.git /work/pyex")

    step("Installing deps")
    run!(sandbox, "cd /work/pyex && mix deps.get 2>&1 | tail -5")

    step("Compiling (cold) -- STREAMING output")
    stream!(sandbox, "cd /work/pyex && mix compile 2>&1")

    step("Snapshotting filesystem")
    client = connect.()
    sandbox = %{sandbox | client: client}
    t0 = now()
    {:ok, snap_id} = Modal.Sandbox.snapshot_filesystem(sandbox)
    info("snapshot: #{snap_id} (#{elapsed(t0)})")

    Modal.Sandbox.terminate(sandbox)

    header("PHASE 2: Restore from snapshot")

    client = connect.()
    t0 = now()

    sandbox2 =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: snap_id,
        cmd: ["sleep", "infinity"],
        timeout: 600,
        idle_timeout: 120
      )

    {:ok, _, sandbox2} = Modal.Sandbox.get_task_id(sandbox2)
    info("sandbox: #{sandbox2.id} (boot: #{elapsed(t0)})")

    step("Verifying snapshot")
    run!(sandbox2, "ls /work/pyex/mix.exs /work/pyex/deps/ && echo 'All present'")

    step("Running tests -- STREAMING output")

    stream!(
      sandbox2,
      "cd /work/pyex && mix test --exclude postgres --exclude external_http --exclude r2 2>&1"
    )

    step("Reading a file")
    run!(sandbox2, "head -8 /work/pyex/mix.exs")

    step("Writing + reading a file")
    run!(sandbox2, "echo 'hello from elixir' > /tmp/test.txt && cat /tmp/test.txt")

    client = connect.()
    Modal.Sandbox.terminate(%{sandbox2 | client: client})
    Mix.shell().info("\n\e[32m=== Done. ===\e[0m")
  end

  defp run!(%Modal.Sandbox{} = sandbox, cmd, opts \\ []) do
    t0 = now()
    info("$ #{cmd}")

    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", cmd], opts)
    {:ok, result} = Modal.ContainerProcess.await(proc)
    Modal.ContainerProcess.close(proc)

    if String.trim(result.stdout) != "" do
      result.stdout |> String.trim() |> String.split("\n") |> Enum.each(&info("  #{&1}"))
    end

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp stream!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", cmd])

    exit_task =
      Task.async(fn ->
        {:ok, code} = Modal.ContainerProcess.exit_code(proc)
        code
      end)

    proc |> Modal.ContainerProcess.stream() |> Enum.each(fn chunk -> IO.write("  " <> chunk) end)

    code = Task.await(exit_task, :infinity)
    Modal.ContainerProcess.close(proc)

    color = if (code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp header(msg), do: Mix.shell().info("\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: Mix.shell().info("\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: Mix.shell().info("  #{msg}")
end
