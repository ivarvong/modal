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
    * `GET /transcript`      -> `transcript.jsonl` next to this file, text/plain
                                (a short note if absent)

  Instrument every response with `X-Ephemeris: DE440s` and `X-Compute-Ms` (ms
  spent computing the body); add `X-Cache: HIT|MISS` to `/crossing/{date}` —
  MISS when computed, HIT when `@lru_cache` serves it.

  Production-grade: `zoneinfo("America/New_York")` for DST-correct local time;
  validate `/crossing/{date}` (4xx on unparseable / out-of-DE440-range / no
  crossing); `@lru_cache` the per-date compute; short docstrings.
  """

  def run do
    :logger.set_application_level(:grpc, :warning)
    key = System.get_env("ANTHROPIC_API_KEY") || raise("set ANTHROPIC_API_KEY (source .env)")
    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    image = base_image!(client, app)
    # A fresh, uniquely-named volume per run is empty by construction, so Claude
    # builds from scratch (no stale app.py to patch).
    vol =
      Modal.Volume.get_or_create!(client, "#{@volume_prefix}-#{System.os_time(:second)}",
        app: app
      )

    secret =
      Modal.Secret.create!(client,
        app: app,
        name: "henge-key-#{System.os_time(:second)}",
        env: %{"ANTHROPIC_API_KEY" => key}
      )

    build!(client, app, image, vol, secret)
    web = deploy!(client, app, image, vol)
    verify!(web)
    # The deploy is live on `vol`; retire prior runs' volumes (theirs are replaced).
    prune_stale_volumes!(client, vol)
    summary(web)
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
        memory_mb: 4_096,
        timeout_secs: 1_800,
        idle_timeout_secs: 900,
        terminate_on_caller_exit: :silent
      )

    {:ok, _} = Modal.Sandbox.get_task_id(sb)
    Modal.Filesystem.write_file!(sb, "#{@workdir}/SPEC.md", @spec_md)

    prompt =
      "Read SPEC.md here and implement it exactly: write app.py in #{@workdir} " <>
        "matching serve(), the routes, headers, and JSON shape. skyfield / fastapi / " <>
        "uvicorn / numpy and the DE440 ephemeris are installed. Smoke-test before " <>
        "finishing: `python3 -c 'from app import serve; serve()'` must run clean."

    # stream-json --verbose records every turn (we save + serve it). headless
    # `-p` needs no PTY; `< /dev/null` skips the stdin-wait warning.
    cmd =
      "cd #{@workdir} && claude -p #{esc(prompt)} --permission-mode acceptEdits " <>
        "--allowedTools Bash --model #{@claude_model} --output-format stream-json " <>
        "--verbose < /dev/null 2>&1"

    log("  $ claude -p <spec> --model #{@claude_model}  (deriving + writing, ~5 min)…")
    t = now()

    # exec_opts timeout_secs is load-bearing: the per-exec default is 300s and
    # SIGKILLs a longer build (exit 137, sandbox untouched). Match the sandbox cap.
    result =
      Modal.Sandbox.exec_streaming!(sb, ["bash", "-c", cmd],
        timeout: :infinity,
        exec_opts: [timeout_secs: 1_800]
      )

    File.write!(@transcript_file, result.stdout)
    log("  ✓ Claude finished (#{elapsed(t)})#{cost_summary(result.stdout)}")

    # Serve the session next to the app: write it onto the Volume too.
    Modal.Filesystem.write_file!(sb, "#{@workdir}/transcript.jsonl", result.stdout)
    Modal.Sandbox.terminate(sb)

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

  # STAGE 3 — VERIFY: curl the live endpoint — correctness + the X- perf headers.
  defp verify!(%Modal.Function{web_url: url}) do
    log_header("STAGE 3 — VERIFY: live endpoint")

    root = req!(url <> "/")
    assert!(root.body["azimuth_deg"] == 299.1, "azimuth != 299.1")
    assert!(hdr(root, "x-ephemeris") == "DE440s", "X-Ephemeris header missing")

    mh = req!(url <> "/manhattanhenge")
    assert_henge!(mh.body["dates"], mh.body["crossings"])

    # Perf instrumentation. A date outside the precomputed May set forces a
    # real ephemeris compute in the handler (MISS, non-zero X-Compute-Ms);
    # the @lru_cache serves the repeat instantly (HIT, ~0ms).
    cold = "2026-06-21"
    c1 = req!(url <> "/crossing/" <> cold)
    c2 = req!(url <> "/crossing/" <> cold)
    assert!(c1.body["date"] == cold, "/crossing returned wrong date")
    assert!(hdr(c1, "x-cache") == "MISS", "first /crossing should MISS the cache")
    assert!(hdr(c2, "x-cache") == "HIT", "repeat /crossing should HIT the cache")

    log(
      "  /crossing #{cold}  MISS #{hdr(c1, "x-compute-ms")}ms (real compute) → " <>
        "HIT #{hdr(c2, "x-compute-ms")}ms  (ephemeris #{hdr(c1, "x-ephemeris")})"
    )

    src = to_string(req!(url <> "/source").body)
    tx = to_string(req!(url <> "/transcript").body)
    assert!(String.contains?(src, "serve"), "/source not the app's own source")
    assert!(String.contains?(tx, "assistant"), "/transcript not the build session")
    log("  ✓ /source #{byte_size(src)}B   /transcript #{byte_size(tx)}B  (both off the Volume)")
  end

  # Gate: the two published dates, each with an apparent altitude just above the
  # horizon and a ~0.5° refraction lift over geometric (confirms the model ran).
  defp assert_henge!(dates, crossings, label \\ "endpoint") do
    assert!(
      dates == @expected_dates,
      "#{label}: dates #{inspect(dates)} != #{inspect(@expected_dates)}"
    )

    by_date = Map.new(crossings, &{&1["date"], &1})

    for d <- @expected_dates do
      c = by_date[d] || raise("#{label}: no crossing for #{d}")
      app_alt = c["apparent_altitude_deg"]
      refraction = app_alt - c["geometric_altitude_deg"]

      assert!(
        app_alt > 0.0 and app_alt < 1.2,
        "#{label}: #{d} apparent #{inspect(app_alt)}° out of range"
      )

      assert!(
        refraction > 0.35 and refraction < 0.65,
        "#{label}: #{d} refraction #{fmt(refraction)}° not ~0.5°"
      )

      log(
        "  ✓ #{d}: 299.1° at #{c["crossing_edt"]}  apparent #{fmt(app_alt)}° (refraction +#{fmt(refraction)}°)"
      )
    end
  end

  # Each run mints a fresh volume; delete earlier prefix-matched ones, keeping
  # the volume the just-verified deploy serves from.
  defp prune_stale_volumes!(client, keep_id) do
    {:ok, vols} = Modal.Volume.list(client)

    stale =
      Enum.filter(
        vols,
        &(String.starts_with?(&1.name, @volume_prefix) and &1.volume_id != keep_id)
      )

    Enum.each(stale, &Modal.Volume.delete(client, &1.volume_id))
    if stale != [], do: log("  ✓ pruned #{length(stale)} stale volume(s)")
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
        curl #{url}/transcript   # the Claude session that built it
    """)
  end

  defp req!(u), do: Req.get!(u, receive_timeout: 60_000, retry: :transient, max_retries: 5)
  defp hdr(resp, name), do: resp.headers |> Map.get(name, [""]) |> List.first()
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
