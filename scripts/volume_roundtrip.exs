# Modal Volume + Filesystem + caller-exit watchdog + cross-family telemetry.
#
# Dogfoods surface the parallel-π script didn't cover:
#
#   * `Modal.Volume.{get_or_create,delete}` — lifecycle wrappers added
#     after this script first surfaced the gap.
#   * `Modal.Filesystem.write_file` / `read_file` / `ls` against a
#     mounted volume.
#   * `:terminate_on_caller_exit: true` live — a spawned task creates a
#     sandbox then crashes; the watchdog must auto-terminate.
#   * Telemetry across BOTH event families (`[:modal, :rpc, :*]` for
#     control-plane RPCs and `[:modal, :worker_rpc, :*]` for per-exec
#     RPCs that the parallel-π demo couldn't see).
#
# Why no cross-sandbox volume read here: Modal's volume contract
# requires `commit` to fire from *inside* a mounted container, and
# this library runs *outside* containers (it's the orchestrator).
# `Modal.Volume`'s moduledoc explains the workarounds. We test the
# single-sandbox path that's portable from where we live.
#
# Run:
#
#     elixir scripts/volume_roundtrip.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule VolumeRoundtrip do
  @app_name "modal-elixir-volume-demo"
  @volume_name "elixir-volume-demo-#{System.os_time(:second)}"
  @mount_path "/data"
  @payload_name "secret-of-the-universe.txt"
  @payload "42 (written and read back from the same sandbox)\n"

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app:   #{inspect(app)}")

    # ── PHASE 1: volume get-or-create ─────────────────────────────
    log("\n── PHASE 1: volume get-or-create ─────────────")
    t = now()
    volume_id = Modal.Volume.get_or_create!(client, @volume_name)
    log("volume: #{volume_id} (#{elapsed(t)})")

    mount = %Modal.Volume{id: volume_id, path: @mount_path, read_only: false}

    # ── PHASE 2: image (cached after first run) ───────────────────
    log("\n── PHASE 2: image ─────────────")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        ["FROM python:3.14-slim"],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image_id} [#{status}] (#{elapsed(t)})")

    # ── PHASE 3: write + read through the mounted volume ──────────
    log("\n── PHASE 3: write + read on a single sandbox ─────────────")
    t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 120,
        volumes: [mount],
        # Demonstrate the watchdog on a long-lived sandbox — defuses
        # cleanly when we call terminate/1 below.
        terminate_on_caller_exit: true
      )

    log("sandbox: #{sandbox.id} (#{elapsed(t)})")
    log("  monitor_pid: #{inspect(sandbox.monitor_pid)} (watchdog armed)")

    path = Path.join(@mount_path, @payload_name)
    log("  writing #{path} (#{byte_size(@payload)} bytes)")
    :ok = Modal.Filesystem.write_file(sandbox, path, @payload)

    {:ok, entries} = Modal.Filesystem.ls(sandbox, @mount_path)
    log("  ls #{@mount_path}: #{inspect(entries)}")

    {:ok, contents} = Modal.Filesystem.read_file(sandbox, path)

    if contents == @payload do
      log("  ✓ read-back matches: #{inspect(String.trim_trailing(contents))}")
    else
      log("  ✗ MISMATCH: got #{inspect(contents)}, expected #{inspect(@payload)}")
      System.halt(1)
    end

    # Exec a shell command IN THE SAME sandbox so we hit worker-channel
    # RPCs (task_exec_*) — that's the path that surfaces in the
    # [:modal, :worker_rpc, :*] telemetry family. A fresh sandbox
    # mounting the same volume would NOT see the file (cross-sandbox
    # visibility needs commit-from-inside; see Modal.Volume's
    # moduledoc), so we exec inside the writer.
    proc =
      Modal.Sandbox.exec!(sandbox, [
        "bash",
        "-c",
        "ls -la /data && cat /data/#{@payload_name}"
      ])

    result = Modal.ContainerProcess.await!(proc, timeout: 30_000)
    Modal.ContainerProcess.close(proc)

    log("  exec'd ls + cat (same sandbox):")
    result.stdout |> String.split("\n", trim: true) |> Enum.each(&log("    " <> &1))

    if result.stderr != "", do: log("  stderr: #{inspect(result.stderr)}")

    :ok = Modal.Sandbox.terminate(sandbox)
    log("  sandbox terminated (watchdog disarmed)")

    # ── PHASE 4: caller-exit watchdog (live) ──────────────────────
    log("\n── PHASE 4: caller-exit watchdog ─────────────")
    demo_caller_exit_watchdog(client, app, image_id)

    # ── PHASE 5: cleanup ──────────────────────────────────────────
    log("\n── PHASE 5: cleanup ─────────────")
    :ok = Modal.Volume.delete(client, volume_id)
    log("  volume #{volume_id} deleted")

    # ── PHASE 6: telemetry ────────────────────────────────────────
    log("\n── PHASE 6: telemetry counters ─────────────")
    print_telemetry()
  end

  # ── Caller-exit watchdog demo ────────────────────────────────────

  defp demo_caller_exit_watchdog(client, app, image_id) do
    parent = self()

    # Spawn a sub-process that creates a sandbox with the watchdog
    # armed, then deliberately crashes. The watchdog must fire a
    # SandboxTerminate RPC; we observe it via telemetry.
    caller =
      spawn(fn ->
        sandbox =
          Modal.Sandbox.create!(client,
            app: app,
            image_id: image_id,
            cmd: ["sleep", "infinity"],
            timeout_secs: 60,
            terminate_on_caller_exit: true
          )

        send(parent, {:sandbox_id, sandbox.id, sandbox.monitor_pid})

        receive do
          :crash_now -> :ok
        end

        raise "deliberate caller crash to test watchdog"
      end)

    receive do
      {:sandbox_id, id, watchdog} ->
        log("  caller #{inspect(caller)} created sandbox #{id}")
        log("  watchdog pid: #{inspect(watchdog)}")
        log("  → crashing caller...")

        # Set up both monitors before sending :crash_now so we never
        # miss the :DOWN message that races with the crash.
        caller_ref = Process.monitor(caller)
        watchdog_ref = Process.monitor(watchdog)

        send(caller, :crash_now)

        receive do
          {:DOWN, ^caller_ref, :process, ^caller, _reason} -> :ok
        after
          2000 -> raise "caller did not exit within 2s"
        end

        log("  ✓ caller down")

        # The watchdog fires SandboxTerminate and exits. Give the
        # Modal-side RPC up to 10s.
        receive do
          {:DOWN, ^watchdog_ref, :process, _, _reason} -> :ok
        after
          10_000 -> raise "watchdog did not exit within 10s"
        end

        log("  ✓ watchdog completed (sandbox terminated by it)")
    after
      5000 -> raise "caller never reported its sandbox id"
    end
  end

  # ── Telemetry ────────────────────────────────────────────────────
  #
  # Subscribes to BOTH families. Before worker-channel telemetry was
  # wired, `[:modal, :worker_rpc, :*]` events would be silent and
  # this counter would only show control-plane RPCs.

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "volume-demo-telemetry",
      [
        [:modal, :rpc, :stop],
        [:modal, :worker_rpc, :stop]
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  @doc false
  def handle_telemetry(event, _measurements, meta, _config) do
    [_, family, _] = event
    key = {family, meta.method, Map.get(meta, :status), Map.get(meta, :error_kind)}
    Agent.update(__MODULE__.Metrics, fn m -> Map.update(m, key, 1, &(&1 + 1)) end)
  end

  defp print_telemetry do
    metrics = Agent.get(__MODULE__.Metrics, & &1)

    {control, worker} = Enum.split_with(metrics, fn {{family, _, _, _}, _} -> family == :rpc end)

    log("  control-plane RPCs:")
    print_section(control)

    if worker != [] do
      log("\n  worker-channel RPCs (per-exec, via Modal.TaskCommandRouter):")
      print_section(worker)
    end
  end

  defp print_section(events) do
    events
    |> Enum.sort()
    |> Enum.each(fn {{_family, method, status, error_kind}, count} ->
      tag = if error_kind, do: " (#{error_kind})", else: ""
      log("    #{count |> to_string() |> String.pad_leading(3)} × #{method} #{status}#{tag}")
    end)
  end

  # ── Tiny utilities ───────────────────────────────────────────────

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
  defp log(msg), do: IO.puts(:stderr, msg)
end

VolumeRoundtrip.run()
