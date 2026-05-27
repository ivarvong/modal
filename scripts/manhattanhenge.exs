# Manhattanhenge 2026 — Claude Code builds it on Modal, Modal serves it.
#
# A sandbox runs Claude headless: it DERIVES the dates (not told them) and
# writes a FastAPI app onto a Volume; deploy_asgi serves that Volume; we curl
# it to verify. Claude lands on May 28 & 29 from azimuth 299.1° + the ~0.5°
# apparent-altitude target. See the PR for the story.
#
#   set -a; source .env; set +a   # MODAL_TOKEN_* + ANTHROPIC_API_KEY
#   elixir scripts/manhattanhenge.exs

Mix.install([{:modal, path: Path.expand("..", __DIR__)}, {:req, "~> 0.5"}])

defmodule Manhattanhenge do
  @app_name "modal-elixir-manhattanhenge"
  @workdir "/work"
  @volume_prefix "manhattanhenge-app"
  @claude_model "claude-sonnet-4-6"
  @transcript_file "/tmp/henge_transcript.jsonl"
  @expected_dates ["2026-05-28", "2026-05-29"]

  # Claude's brief. We pin only the I/O contract (serve(), routes, headers,
  # JSON shape) so deploy + verify are deterministic; the astronomy is Claude's.
  @spec_md """
  # Manhattanhenge 2026 — write a single file: #{@workdir}/app.py

  Manhattanhenge is the evening the setting Sun aligns with Manhattan's street
  grid: azimuth 299.1° (true north, clockwise). Compute it with Skyfield + JPL
  DE440 (at `/opt/ephem/de440s.bsp`, load via `Loader('/opt/ephem')`), observer
  at 42nd St & 5th Ave: `wgs84.latlon(40.75348868877207, -73.98088776620406)`.

  For a date, find the afternoon instant the Sun's azimuth crosses 299.1° and
  report two altitudes there: `apparent_altitude_deg` (refraction-corrected,
  `.altaz(temperature_C=10, pressure_mbar=1010)`) and `geometric_altitude_deg`
  (plain `.altaz()`, for contrast).

  DERIVE the dates — do NOT hard-code them. Manhattanhenge is when the Sun,
  crossing the grid bearing, sits at an apparent altitude of ~0.5° (not 0°: the
  NJ Palisades + skyline put NYC's western horizon ~0.5° up — use that target,
  don't model the horizon). Scan May 2026; the two consecutive evenings that
  bracket ~0.5° (last below, first above) are Manhattanhenge.

  `app.py` exposes module-level `serve()` returning a FastAPI app (no `@modal`,
  no uvicorn; load the ephemeris once at import). A "crossing" is a dict: `date`,
  `crossing_utc` (ISO `…Z`), `crossing_edt` (ISO+offset), `apparent_altitude_deg`,
  `geometric_altitude_deg` (altitudes 2 dp). Routes:
    * `GET /`                -> {"service","azimuth_deg":299.1,"ephemeris","endpoints"}
    * `GET /manhattanhenge`  -> {"year":2026,"dates":[…derived…],"crossings":[…]}
    * `GET /crossing/{date}` -> one crossing dict; 422 on bad/out-of-range/no-crossing
    * `GET /source`          -> this file's own source, text/plain (read `__file__`)

  Add an `X-Compute-Ms` response header — the milliseconds spent computing the
  body — so the per-request compute cost is visible to any caller.

  Production-grade: `zoneinfo("America/New_York")` for DST-correct local time;
  validate `/crossing/{date}` (4xx on unparseable / out-of-DE440-range / no
  crossing); `@lru_cache` the per-date compute; short docstrings.
  """

  def run do
    :logger.set_application_level(:grpc, :warning)
    key = System.get_env("ANTHROPIC_API_KEY") || raise("set ANTHROPIC_API_KEY (source .env)")
    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    run_id = run_id()

    image = base_image!(client, app)
    # A fresh, uniquely-named volume per run is empty by construction, so Claude
    # builds from scratch (no stale app.py to patch).
    vol = Modal.Volume.get_or_create!(client, "#{@volume_prefix}-#{run_id}", app: app)

    # Ephemeral means Modal ties the secret to this client session instead of
    # leaving named per-run secrets behind. Agent demos should not accumulate
    # credentials as historical artifacts.
    secret =
      Modal.Secret.create!(client,
        app: app,
        name: "henge-key-#{run_id}",
        env: %{"ANTHROPIC_API_KEY" => key},
        if_exists: :ephemeral
      )

    try do
      build!(client, app, image, vol, secret)
      web = deploy!(client, app, image, vol)
      verify!(web)
      # The deploy is live on `vol`; retire prior runs' volumes (theirs are replaced).
      prune_stale_volumes!(client, vol)
      summary(web)
    after
      Modal.Secret.delete(client, secret)
    end
  end

  # Base image: Claude CLI + uv + Skyfield + DE440. Content-addressed (cache-hits);
  # the deployed function reuses it — only app.py comes from the Volume.
  defp base_image!(client, app) do
    log_header("SETUP — base image (Claude CLI + uv + Skyfield + DE440)")
    {:ok, id, status} = Modal.Image.get_or_create(client, base_dockerfile(), app: app)
    log("  ✓ image #{id} [#{status}]")
    id
  end

  # STAGE 1 — BUILD: a sandbox mounts the Volume read-write; Claude writes (and
  # smoke-tests) app.py onto it. On sandbox exit the worker commits the Volume.
  defp build!(client, app, image, vol, secret) do
    log_header("STAGE 1 — BUILD: Claude derives + writes app.py (live)")

    sb =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image,
        cmd: ["sleep", "infinity"],
        workdir: @workdir,
        secret_ids: [secret],
        volumes: [%Modal.Volume{id: vol, path: @workdir}],
        cpu: 4.0,
        memory_mb: 4_096,
        timeout_secs: 1_800,
        idle_timeout_secs: 900,
        terminate_on_caller_exit: :silent
      )

    try do
      {:ok, _} = Modal.Sandbox.get_task_id(sb)
      Modal.Filesystem.write_file!(sb, "#{@workdir}/SPEC.md", @spec_md)

      prompt =
        "Read SPEC.md here and implement it exactly: write app.py in #{@workdir} " <>
          "matching serve(), the routes, headers, and JSON shape. skyfield / fastapi / " <>
          "uvicorn / numpy and the DE440 ephemeris are installed. Smoke-test before " <>
          "finishing: `python3 -c 'from app import serve; serve()'` must run clean."

      # stream-json --verbose records every turn (we save locally). headless
      # `-p` needs no PTY; `< /dev/null` skips the stdin-wait warning.
      cmd =
        "cd #{@workdir} && claude -p #{esc(prompt)} --permission-mode acceptEdits " <>
          "--allowedTools Bash --model #{@claude_model} --output-format stream-json " <>
          "--verbose < /dev/null 2>&1"

      log("  $ claude -p <spec> --model #{@claude_model}  (deriving + writing, ~5 min)…")
      t = now()

      # timeout: :infinity — wait out the whole build (~400-510s). No per-exec
      # timeout_secs: the exec is bounded only by the sandbox's own timeout_secs
      # (1800s above). (Modal.Sandbox.exec/3 no longer caps execs at 300s.)
      result = Modal.Sandbox.exec_streaming!(sb, ["bash", "-c", cmd], timeout: :infinity)

      File.write!(@transcript_file, result.stdout)
      log("  ✓ Claude finished (#{elapsed(t)})#{cost_summary(result.stdout)}")

      # The orchestrator, not the agent, owns the acceptance gate. This catches
      # "Claude said it tested" failures before deploy and makes the demo's trust
      # boundary explicit.
      smoke = Modal.Sandbox.exec_streaming!(sb, ["python3", "-c", "from app import serve; serve()"], timeout: 120_000)
      assert!(smoke.code == 0, "orchestrator smoke test failed")
      log("  ✓ orchestrator smoke-test passed")

      # Keep the agent transcript local for cost/debugging; do not publish it with
      # the generated app. Transcripts are useful audit artifacts, but they are
      # also an easy place to leak env dumps, paths, or future tool output.
    after
      Modal.Sandbox.terminate(sb)
    end

    app_py = volume_file!(client, vol, "/app.py")
    log("  ✓ Volume committed (app.py #{byte_size(app_py)}B)")
  end

  # STAGE 2 — DEPLOY: same image, mount the Volume read-only, serve /work/app.py.
  defp deploy!(client, app, image, vol) do
    log_header("STAGE 2 — DEPLOY: deploy_asgi off the Volume")

    {:ok, web} =
      Modal.Function.deploy_asgi(client,
        app: app,
        name: "web",
        image_id: image,
        volumes: [%Modal.Volume{id: vol, path: @workdir, read_only: true}],
        module: "app",
        callable: "serve",
        requested_suffix: "manhattanhenge",
        target_concurrent_inputs: 8,
        timeout_secs: 60,
        idle_timeout_secs: 120,
        min_containers: 0
      )

    log("  ✓ deployed #{web.web_url}")
    web
  end

  # STAGE 3 — VERIFY: curl the live endpoint and check the math.
  defp verify!(%Modal.Function{web_url: url}) do
    log_header("STAGE 3 — VERIFY: live endpoint")

    root = req!(url <> "/")
    assert!(root.body["azimuth_deg"] == 299.1, "azimuth_deg != 299.1")

    # The math: the two derived days, each crossing the grid bearing at ~8:1x
    # PM EDT, at the refraction-corrected apparent altitude.
    mh = req!(url <> "/manhattanhenge")
    assert_henge!(mh.body["dates"], mh.body["crossings"])

    # The single-date route recomputes a crossing on demand.
    one = req!(url <> "/crossing/2026-05-29")
    assert!(one.body["date"] == "2026-05-29", "/crossing returned the wrong date")

    src = to_string(req!(url <> "/source").body)
    assert!(String.contains?(src, "serve"), "/source isn't the app's own source")
    log("  ✓ /source #{byte_size(src)}B  (off the Volume; transcript kept local)")
  end

  # The math gate. For each published day: the Sun crosses the 299.1° grid
  # bearing at ~8:1x PM EDT, sitting at an apparent (refraction-corrected)
  # altitude just above the horizon — a ~0.5° lift over the geometric altitude,
  # which confirms the refraction model ran (the published ~0.5° "above the
  # horizon" is the Palisades-lifted apparent value, not geometric).
  defp assert_henge!(dates, crossings, label \\ "endpoint") do
    assert!(dates == @expected_dates, "#{label}: dates #{inspect(dates)} != #{inspect(@expected_dates)}")
    by_date = Map.new(crossings, &{&1["date"], &1})

    for d <- @expected_dates do
      c = by_date[d] || raise("#{label}: no crossing for #{d}")
      {hour, minute} = edt_hm(c["crossing_edt"])
      app_alt = c["apparent_altitude_deg"]
      refraction = app_alt - c["geometric_altitude_deg"]

      assert!(hour == 20 and minute in 10..15, "#{label}: #{d} crossing #{c["crossing_edt"]} not ~8:1x PM EDT")
      assert!(app_alt > 0.0 and app_alt < 0.8, "#{label}: #{d} apparent #{inspect(app_alt)}° outside (0°, 0.8°)")
      assert!(refraction > 0.35 and refraction < 0.65, "#{label}: #{d} refraction #{fmt(refraction)}° not ~0.5°")

      log("  ✓ #{d}: 299.1° at #{c["crossing_edt"]}  apparent #{fmt(app_alt)}° (refraction +#{fmt(refraction)}°)")
    end
  end

  # "2026-05-28T20:13:16-04:00" -> {20, 13}
  defp edt_hm(edt) do
    [_, time] = String.split(edt, "T", parts: 2)
    [h, m | _] = String.split(time, ":")
    {String.to_integer(h), String.to_integer(m)}
  end

  # Each run mints a fresh volume; retire EARLIER ones (their deploys have been
  # replaced), keeping the volume the just-verified deploy serves from. Only
  # touch volumes older than 10 min, so a concurrent run's fresh volume is
  # safe. Best-effort and last — housekeeping must never fail a green deploy.
  defp prune_stale_volumes!(client, keep_id) do
    cutoff = System.os_time(:second) - 600

    with {:ok, vols} <- Modal.Volume.list(client) do
      stale =
        Enum.filter(vols, fn v ->
          String.starts_with?(v.name, @volume_prefix) and v.volume_id != keep_id and v.created_at < cutoff
        end)

      Enum.each(stale, &Modal.Volume.delete(client, &1.volume_id))
      if stale != [], do: log("  ✓ pruned #{length(stale)} stale volume(s)")
    end
  rescue
    e -> log("  · volume prune skipped: #{Exception.message(e)}")
  end

  defp base_dockerfile do
    [
      "FROM python:3.12-slim",
      "RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      "RUN pip install --no-cache-dir uv",
      # modal must be importable: a deploy_asgi function boots via `python -m modal._container_entrypoint`.
      "RUN uv pip install --system --no-cache-dir 'modal>=0.65' 'skyfield>=1.49' 'numpy>=1.26' 'fastapi[standard]>=0.115' 'uvicorn>=0.30'",
      "RUN mkdir -p /opt/ephem && python -c \"from skyfield.api import Loader; Loader('/opt/ephem')('de440s.bsp')\"",
      ~S{RUN bash -c 'set -eo pipefail; for i in 1 2 3 4 5; do curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && break || sleep 10; done; bash /tmp/install.sh'},
      "ENV PATH=/root/.local/bin:$PATH",
      "RUN claude --version",
      "WORKDIR #{@workdir}",
      "ENV PYTHONPATH=#{@workdir}"
    ]
  end

  # Poll the committed Volume until app.py lands (the worker commits on exit).
  defp volume_file!(client, vol, path) do
    deadline = now() + 30_000

    Stream.repeatedly(fn ->
      case Modal.Volume.get_file(client, vol, path) do
        {:ok, b} -> b
        _ -> Process.sleep(1_000) && :pending
      end
    end)
    |> Enum.find_value(fn
      :pending -> if now() > deadline, do: raise("#{path} not committed to the Volume within 30s")
      b -> b
    end)
  end

  # The stream's final `result` event carries the run cost + turn count.
  defp cost_summary(transcript) do
    transcript
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case JSON.decode(line) do
        {:ok, %{"type" => "result", "total_cost_usd" => c} = r} ->
          "  —  $#{:erlang.float_to_binary(c / 1, decimals: 4)}, #{r["num_turns"] || "?"} turns"

        _ ->
          nil
      end
    end) || ""
  end

  defp summary(%Modal.Function{web_url: url}) do
    log_header("LIVE — Manhattanhenge 2026")

    log("""
      #{Enum.join(@expected_dates, " & ")} — azimuth 299.1°, derived by Claude.
        curl #{url}/manhattanhenge
        curl #{url}/crossing/2026-05-29
        curl #{url}/source       # the app's own source, off the Volume
    """)
  end

  # 90s receive timeout: a cold start (min_containers: 0) has to boot Python,
  # import Skyfield, load the ephemeris, and serve — Modal holds the request
  # open meanwhile, so the client must out-wait the boot.
  defp req!(u), do: Req.get!(u, receive_timeout: 90_000, retry: :transient, max_retries: 5)

  defp run_id do
    ts = System.os_time(:millisecond) |> Integer.to_string(36)
    rand = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    "#{ts}-#{rand}"
  end

  defp esc(s), do: "'" <> String.replace(s, "'", ~S('"'"')) <> "'"
  defp assert!(true, _), do: :ok
  defp assert!(false, m), do: raise("ASSERT FAILED — #{m}")
  defp fmt(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 3)
  defp fmt(n), do: inspect(n)
  defp log_header(m), do: IO.puts(:stderr, "\n\e[1m── #{m} ──\e[0m")
  defp log(m), do: IO.puts(:stderr, m)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{Float.round((now() - t) / 1000, 1)}s"
end

Manhattanhenge.run()
