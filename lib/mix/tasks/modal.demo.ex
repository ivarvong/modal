defmodule Mix.Tasks.Modal.Demo do
  @moduledoc "Demonstrates a Ramp-style coding agent workflow using Modal Sandboxes."
  @shortdoc "Clone a repo, install deps, snapshot, restore, run tests"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    {token_id, token_secret} = credentials!()

    connect = fn ->
      {:ok, c} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
      c
    end

    client = connect.()
    {:ok, app_id} = Modal.App.lookup(client, "elixir-demo")

    step("Building image")
    t0 = now()

    {:ok, image_id} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM hexpm/elixir:1.19.4-erlang-26.2.5.3-debian-bullseye-20260316-slim",
          "RUN apt-get update && apt-get install -y git build-essential python3 && rm -rf /var/lib/apt/lists/*",
          "RUN mix local.hex --force && mix local.rebar --force"
        ],
        app_id: app_id
      )

    info("image: #{image_id} (#{elapsed(t0)})")

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

    {:ok, _} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("Cloning ivarvong/pyex")
    dp_run!(sandbox, "git clone --depth=1 https://github.com/ivarvong/pyex.git /work/pyex")

    step("Installing deps")
    dp_run!(sandbox, "cd /work/pyex && mix deps.get 2>&1 | tail -5")

    step("Compiling (cold)")
    dp_run!(sandbox, "cd /work/pyex && mix compile 2>&1 | tail -5", timeout: 600_000)

    step("Running tests")

    dp_run!(
      sandbox,
      "cd /work/pyex && mix test --exclude postgres --exclude external_http --exclude r2 2>&1 | tail -15",
      timeout: 600_000
    )

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

    {:ok, _} = Modal.Sandbox.get_task_id(sandbox2)
    info("sandbox: #{sandbox2.id} (boot: #{elapsed(t0)})")

    step("Verifying snapshot")
    dp_run!(sandbox2, "ls /work/pyex/mix.exs /work/pyex/deps/ && echo 'All present'")

    step("Running tests (from snapshot)")

    dp_run!(
      sandbox2,
      "cd /work/pyex && mix test --exclude postgres --exclude external_http --exclude r2 2>&1 | tail -15",
      timeout: 600_000
    )

    step("Reading a file")
    dp_run!(sandbox2, "head -8 /work/pyex/mix.exs")

    step("Writing + reading a file")
    dp_run!(sandbox2, "echo 'hello from elixir' > /tmp/test.txt && cat /tmp/test.txt")

    client = connect.()
    Modal.Sandbox.terminate(%{sandbox2 | client: client})
    Mix.shell().info("\n\e[32m=== Done. ===\e[0m")
  end

  defp dp_run!(%Modal.Sandbox{} = sandbox, cmd, opts \\ []) do
    t0 = now()
    info("$ #{cmd}")

    proc = Modal.Sandbox.exec(sandbox, ["bash", "-c", cmd], opts)
    {:ok, result} = Modal.ContainerProcess.await(proc)
    Modal.ContainerProcess.close(proc)

    if String.trim(result.stdout) != "" do
      result.stdout |> String.trim() |> String.split("\n") |> Enum.each(&info("  #{&1}"))
    end

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp credentials! do
    id = System.get_env("MODAL_TOKEN_ID")
    secret = System.get_env("MODAL_TOKEN_SECRET")
    unless id && secret, do: Mix.raise("Set MODAL_TOKEN_ID and MODAL_TOKEN_SECRET")
    {id, secret}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp elapsed(t0) do
    ms = System.monotonic_time(:millisecond) - t0
    if ms < 1000, do: "#{ms}ms", else: "#{Float.round(ms / 1000, 1)}s"
  end

  defp header(msg), do: Mix.shell().info("\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: Mix.shell().info("\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: Mix.shell().info("  #{msg}")
end
