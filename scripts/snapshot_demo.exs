# Ramp-style coding-agent workflow: clone an Elixir repo, install
# deps, compile, *snapshot the filesystem*, then restore from snapshot
# and run tests on a fresh sandbox.
#
# The snapshot is the load-bearing primitive — phase 1 takes minutes
# to install + compile; phase 2 boots from the snapshot in seconds
# and is ready to run tests immediately. Realistic shape for any
# per-PR / per-branch test runner that benefits from a warm baseline.
#
#     elixir scripts/snapshot_demo.exs                                 # defaults to elixir-lang/gen_stage
#     elixir scripts/snapshot_demo.exs https://github.com/owner/repo   # any public Elixir repo

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule SnapshotDemo do
  @default_repo_url "https://github.com/elixir-lang/gen_stage.git"

  def run(args) do
    :logger.set_application_level(:grpc, :warning)

    repo_url =
      case args do
        [] -> @default_repo_url
        [url | _] -> url
      end

    repo_name = repo_url |> Path.basename() |> String.replace_suffix(".git", "")
    workdir = "/work/#{repo_name}"

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, "modal-elixir-snapshot-demo")

    step("Building image")
    t0 = now()

    {:ok, image_id, image_status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM hexpm/elixir:1.19.5-erlang-28.5-debian-bookworm-20260421-slim",
          "RUN apt-get update && apt-get install -y git build-essential python3 && rm -rf /var/lib/apt/lists/*",
          "RUN mix local.hex --force && mix local.rebar --force"
        ],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    info("image: #{image_id} [#{image_status}] (#{elapsed(t0)})")

    header("PHASE 1: Build from scratch")

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 600,
        idle_timeout_secs: 120,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("Cloning #{repo_name}")
    run!(sandbox, "git clone --depth=1 #{repo_url} #{workdir}")

    step("Installing deps")
    run!(sandbox, "cd #{workdir} && mix deps.get 2>&1 | tail -5")

    step("Compiling (cold) — STREAMING output")
    stream!(sandbox, "cd #{workdir} && mix compile 2>&1")

    step("Snapshotting filesystem")
    t0 = now()
    {:ok, snap_id} = Modal.Sandbox.snapshot_filesystem(sandbox)
    info("snapshot: #{snap_id} (#{elapsed(t0)})")

    Modal.Sandbox.terminate(sandbox)

    header("PHASE 2: Restore from snapshot")

    t0 = now()

    sandbox2 =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: snap_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 600,
        idle_timeout_secs: 120,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id2} = Modal.Sandbox.get_task_id(sandbox2)
    info("sandbox: #{sandbox2.id} (boot from snapshot: #{elapsed(t0)})")

    step("Verifying snapshot")
    run!(sandbox2, "ls #{workdir}/mix.exs #{workdir}/deps/ && echo 'All present'")

    step("Running tests — STREAMING output")
    stream!(sandbox2, "cd #{workdir} && mix test 2>&1")

    step("Reading a file via Modal.Filesystem")
    {:ok, mix_exs} = Modal.Filesystem.read_file(sandbox2, "#{workdir}/mix.exs")
    mix_exs |> String.split("\n") |> Enum.take(8) |> Enum.each(&info("  #{&1}"))

    step("Writing + reading via Modal.Filesystem")
    :ok = Modal.Filesystem.write_file(sandbox2, "/tmp/test.txt", "hello from elixir\n")
    {:ok, contents} = Modal.Filesystem.read_file(sandbox2, "/tmp/test.txt")
    info("  read back: #{inspect(contents)}")

    Modal.Sandbox.terminate(sandbox2)
    IO.puts(:stderr, "\n\e[32m=== Done. ===\e[0m")
  end

  defp run!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")
    result = Modal.Sandbox.exec_streaming!(sandbox, ["bash", "-c", cmd])

    if String.trim(result.stdout) != "" do
      result.stdout |> String.trim() |> String.split("\n") |> Enum.each(&info("  #{&1}"))
    end

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp stream!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    on_line = Modal.ContainerProcess.line_buffered(fn line -> IO.puts("  " <> line) end)

    # Non-bang exec_streaming/3: a non-zero exit (e.g. some upstream
    # tests fail) is a valid result we want to surface, not an
    # exception that aborts the snapshot pipeline.
    {:ok, result} =
      Modal.Sandbox.exec_streaming(sandbox, ["bash", "-c", cmd],
        on_stdout: on_line,
        timeout: :infinity
      )

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp header(msg), do: IO.puts(:stderr, "\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: IO.puts(:stderr, "\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: IO.puts(:stderr, "  #{msg}")

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

SnapshotDemo.run(System.argv())
