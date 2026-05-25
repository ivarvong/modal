# Seed a Modal volume from the orchestrator, fan out N parallel
# sandboxes that each mount it read-only and process their chunk,
# aggregate the results.
#
# This is the canonical pattern that `Modal.Volume.put_file/5`
# unlocks — previously you had to install Modal's Python SDK in
# your container and call `volume.commit()` from inside a worker
# sandbox just to get input data into a place every consumer could
# see. Now the orchestrator writes directly into the volume's
# content-addressed block store and every sandbox sees it on first
# read, no commit/reload dance required.
#
# Workload: split 1000 random ints into N chunks, sum each chunk in
# its own sandbox, verify the partial sums add up to the local sum.
# Toy compute on purpose — the orchestration shape is the point.
#
# Run:
#
#     elixir scripts/seed_and_fan_out.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule SeedAndFanOut do
  @app_name "modal-elixir-seed-fan-out"
  @num_workers 5
  @chunk_size 200

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    # ── PHASE 0: generate data, compute the local truth ─────────
    chunks =
      for i <- 0..(@num_workers - 1) do
        # Deterministic so re-runs produce the same expected sum and
        # we can verify against a known answer.
        :rand.seed(:exsss, {i, i + 1, i + 2})
        Enum.map(1..@chunk_size, fn _ -> :rand.uniform(1000) end)
      end

    expected_total = chunks |> List.flatten() |> Enum.sum()
    log("\nlocal: #{@num_workers} chunks × #{@chunk_size} ints = #{@num_workers * @chunk_size} numbers")
    log("local sum: #{expected_total}")

    # ── PHASE 1: v2 volume + push every chunk via put_file ──────
    log("\n── PHASE 1: seed volume from orchestrator ─────────────")
    t = now()

    volume_name = "elixir-seed-fan-out-#{System.os_time(:second)}"
    {:ok, volume_id} = Modal.Volume.get_or_create(client, volume_name, version: :v2)
    log("volume:   #{volume_id} (v2, #{elapsed(t)})")

    # `put_file/5` writes each chunk straight into the volume's
    # block store. No sandbox needed for the write side. The bang
    # variant raises on failure so partial seeding surfaces loudly.
    t = now()

    for {chunk, i} <- Enum.with_index(chunks) do
      payload = chunk |> Enum.map_join("\n", &to_string/1)
      :ok = Modal.Volume.put_file!(client, volume_id, "chunk_#{i}.txt", payload)
    end

    log("seeded:   #{@num_workers} chunks pushed in #{elapsed(t)}")

    # ── PHASE 2: image (cached on subsequent runs) ──────────────
    log("\n── PHASE 2: image ─────────────")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(client, ["FROM python:3.14-slim"],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image:    #{image_id} [#{status}] (#{elapsed(t)})")

    # ── PHASE 3: fan out N read-only mounts ─────────────────────
    log("\n── PHASE 3: fan out #{@num_workers} workers in parallel ─────────────")
    t = now()

    mount = %Modal.Volume{id: volume_id, path: "/data", read_only: true}

    partial_sums =
      0..(@num_workers - 1)
      |> Task.async_stream(
        fn worker_id -> sum_chunk_in_sandbox(client, app, image_id, mount, worker_id) end,
        ordered: true,
        max_concurrency: @num_workers,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, v} -> v end)

    log("\nall #{@num_workers} workers settled in #{elapsed(t)}")

    # ── PHASE 4: verify ─────────────────────────────────────────
    log("\n── PHASE 4: verify ─────────────")

    remote_total = Enum.sum(partial_sums)
    log("remote partials:  #{Enum.join(partial_sums, " + ")} = #{remote_total}")
    log("local truth:      #{expected_total}")

    if remote_total == expected_total do
      log("\n  ✓ remote == local — orchestrator→volume→N sandboxes survived end-to-end")
    else
      log("\n  ✗ MISMATCH: remote #{remote_total} vs local #{expected_total}")
      System.halt(1)
    end

    # ── PHASE 5: cleanup ────────────────────────────────────────
    log("\n── PHASE 5: cleanup ─────────────")
    :ok = Modal.Volume.delete(client, volume_id)
    log("volume #{volume_id} deleted")

    # ── PHASE 6: telemetry ──────────────────────────────────────
    log("\n── PHASE 6: telemetry ─────────────")
    print_telemetry()
  end

  # ── Per-worker sandbox ───────────────────────────────────────────
  #
  # Each worker boots its own sandbox with the seeded volume mounted
  # read-only, reads its chunk, sums it, prints the sum to stdout.
  # `Modal.Sandbox.run!/2` wraps create + exec + await + terminate
  # so the worker's whole lifecycle is one call.

  defp sum_chunk_in_sandbox(client, app, image_id, mount, worker_id) do
    script = """
    total = 0
    with open("/data/chunk_#{worker_id}.txt") as f:
        for line in f:
            line = line.strip()
            if line:
                total += int(line)
    print(total)
    """

    started = now()

    %{stdout: stdout, code: 0} =
      Modal.Sandbox.run!(client,
        app: app,
        image_id: image_id,
        cmd: ["python3", "-c", script],
        timeout_secs: 60,
        await_timeout: 60_000,
        volumes: [mount]
      )

    partial = stdout |> String.trim() |> String.to_integer()
    ms = now() - started
    log("  worker #{worker_id}: partial sum = #{partial} (#{ms}ms)")
    partial
  end

  # ── Telemetry ────────────────────────────────────────────────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "seed-fan-out-telemetry",
      [[:modal, :rpc, :stop], [:modal, :worker_rpc, :stop]],
      &__MODULE__.on_telemetry/4,
      nil
    )
  end

  @doc false
  def on_telemetry(event, _measurements, meta, _config) do
    [_, family, _] = event
    key = {family, meta.method, Map.get(meta, :status), Map.get(meta, :error_kind)}
    Agent.update(__MODULE__.Metrics, fn m -> Map.update(m, key, 1, &(&1 + 1)) end)
  end

  defp print_telemetry do
    metrics = Agent.get(__MODULE__.Metrics, & &1)
    {control, worker} = Enum.split_with(metrics, fn {{family, _, _, _}, _} -> family == :rpc end)

    log("  control-plane:")
    print_section(control)

    if worker != [] do
      log("\n  worker-channel:")
      print_section(worker)
    end

    # `put_file/5` is content-addressed: a cold seed costs 2 RPCs
    # per file (probe + HTTPS PUT + confirm), while a warm seed
    # (same bytes already in Modal's block store from a previous
    # run) is 1 RPC per file — the probe returns no missing blocks
    # and we short-circuit. We seed deterministic content, so the
    # SECOND run of this script and beyond lands in the warm
    # regime and skips the HTTPS PUT entirely.
    cold = 2 * @num_workers
    warm = @num_workers
    actual = Map.get(metrics, {:rpc, :VolumePutFiles2, :ok, nil}, 0)

    log("")

    cond do
      actual == cold ->
        log("  ✓ put_file (cold): #{actual} VolumePutFiles2 RPCs — 2 per file (probe + confirm)")

      actual == warm ->
        log(
          "  ✓ put_file (warm): #{actual} VolumePutFiles2 RPCs — 1 per file (dedup hit, no HTTPS PUT)"
        )

      true ->
        log(
          "  ! put_file: expected #{warm} (warm) or #{cold} (cold) VolumePutFiles2 RPCs, got #{actual}"
        )
    end
  end

  defp print_section(events) do
    events
    |> Enum.sort()
    |> Enum.each(fn {{_, method, status, error_kind}, count} ->
      tag = if error_kind, do: " (#{error_kind})", else: ""
      log("    #{count |> to_string() |> String.pad_leading(3)} × #{method} #{status}#{tag}")
    end)
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
  defp log(msg), do: IO.puts(:stderr, msg)
end

SeedAndFanOut.run()
