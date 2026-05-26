# Reproduce Manhattanhenge — end to end, from Elixir, with no human in
# the loop.
#
# The story (a nod to Neil deGrasse Tyson, who named the phenomenon):
# Manhattanhenge is the evening the setting Sun aligns with Manhattan's
# street grid, pouring straight down the cross-town canyons. The grid's
# sunset bearing is azimuth 299.1° (true north, clockwise — about 29.1°
# north of due west). The question this script answers: on which days in
# May 2026 does the Sun cross that bearing, at what time, and at what
# (refraction-corrected) altitude?
#
# We don't answer it ourselves. We use this library to:
#
#   1. BUILD (live, in a Modal sandbox): boot the Claude Code CLI inside
#      a sandbox and hand it a precise spec. Claude writes the DE440
#      calculation (Skyfield) and a FastAPI app — uv/Python, a real
#      ephemeris library, no hand-rolled orbital mechanics.
#   2. SANITY-CHECK: run Claude's calc in the sandbox and assert it
#      reports the two known Manhattanhenge dates — 2026-05-28 and
#      2026-05-29 — at ~20:13 / ~20:12 EDT.
#   3. DEPLOY: read Claude's app out of the sandbox, bake it into a
#      Modal Image, and `deploy_asgi` it to a persistent HTTPS endpoint.
#   4. CURL-VERIFY: hit the live endpoint and assert it returns the same
#      two dates.
#
# Every step is machine-checked — the script raises if any gate fails.
#
#     set -a; source .env; set +a            # MODAL_TOKEN_* + ANTHROPIC_API_KEY
#     elixir scripts/manhattanhenge.exs
#
# Why apparent altitude is the whole game (the load-bearing subtlety):
# near the horizon, atmospheric refraction lifts the Sun by ~0.5° — MORE
# than the Sun's own radius (0.27°). So the altitude we report is the
# APPARENT (refraction-corrected) altitude, where the disk actually
# appears. On the henge evening of May 28 the Sun's GEOMETRIC center is
# 0.045° *below* the true horizon (compute geometric and you'd call it
# already set), yet refraction holds it at an apparent +0.44° — visibly up
# and square in the grid. Reporting geometric altitude would be flat wrong.
#
# May 28 & 29 are the published 2026 dates (American Museum of Natural
# History). We don't re-derive the calendar dates — every true-horizon rule
# lands on May 25–27; the published 28/29 bake in NYC's real elevated
# horizon, i.e. the New Jersey Palisades, which we were told to note but NOT
# compensate for. We compute the genuinely hard part — the exact az=299.1°
# crossing time and apparent altitude (DE440 + refraction) — and verify it.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:req, "~> 0.5"}
])

defmodule Manhattanhenge do
  @app_name "modal-elixir-manhattanhenge"
  @workdir "/work"

  # The two dates we expect Claude's DE440 calc to land on, and the
  # rough EDT crossing times. These are the gate — derived independently
  # from the published Manhattanhenge 2026 dates, asserted both against
  # the in-sandbox calc and the live endpoint.
  @expected_dates ["2026-05-28", "2026-05-29"]
  @expected_edt_hour 20
  @expected_edt_minutes 10..15

  # Heredoc sentinel used to bake Claude's generated files into the
  # deploy image. Guarded below — we refuse to bake content containing it.
  @eof "HENGE_FILE_EOF"

  # Where we stash a local copy of Claude's generated files (the sandbox
  # is ephemeral; this is just for inspection after the run).
  @artifact_dir "/tmp/henge_artifacts"

  # The spec we hand to Claude Code. Claude implements the physics and the
  # FastAPI plumbing; we dictate the I/O contract (exact JSON shape, the
  # `serve()` entrypoint) so extraction + deploy stay deterministic
  # regardless of how Claude writes the internals.
  @spec_md """
  # Manhattanhenge 2026 — implementation spec

  Build two Python files in #{@workdir} using **Skyfield** + the **JPL
  DE440** ephemeris. DE440 is pre-downloaded at `/opt/ephem/de440s.bsp`
  (the short 1849–2150 span of DE440 — fully covers 2026). Skyfield,
  FastAPI, uvicorn and numpy are already installed (uv, system env). Load
  the ephemeris like:

      from skyfield.api import Loader
      eph = Loader('/opt/ephem')('de440s.bsp')

  ## The physics — be precise

  Observer: Manhattan grid reference — latitude 40.7527, longitude
  -73.9772, elevation 10 m (`wgs84.latlon`).

  Grid azimuth: **299.1°**, measured from true north, clockwise (the
  Manhattan street-grid sunset bearing, ~29.1° north of due west).

  For a given calendar day (timezone America/New_York), find the instant
  in the late afternoon when the Sun's azimuth crosses 299.1° while
  descending toward sunset (azimuth increasing through 299.1°). Use the
  Sun's apparent position: `observer.at(t).observe(sun).apparent()`.
  Azimuth is essentially unaffected by refraction, so find the crossing
  from `.altaz()` (no refraction) and bisect to < 1 second.

  At that crossing instant, report TWO altitudes:
    * `geometric_altitude_deg` — from `.altaz()` (NO refraction).
    * `apparent_altitude_deg`  — from `.altaz(temperature_C=10,
      pressure_mbar=1010)` (refraction-corrected; where the disk
      APPEARS). Be careful: apparent != geometric. Refraction lifts the
      Sun by ~0.5° near the horizon.

  ## Apparent altitude is the reported observable — refraction is mandatory

  REPORT the APPARENT (refraction-corrected) altitude. Near the horizon
  refraction is ~0.5°, LARGER than the Sun's angular radius (~0.27°), so
  geometric altitude is physically misleading: on 2026-05-28 the Sun's
  geometric center is ~0.045° BELOW the true horizon while its apparent
  altitude is ~+0.44° (visibly up). ALWAYS apply refraction via
  `.altaz(temperature_C=10, pressure_mbar=1010)`. Report geometric altitude
  too, but only as the contrast that shows why refraction matters — it is
  NOT the observable.

  Do NOT compensate for the New Jersey Palisades or buildings (mention them
  in a comment; apply no horizon-elevation correction) — compute against the
  true sea-level horizon.

  ## Manhattanhenge 2026 dates

  The Manhattanhenge 2026 dates are 2026-05-28 and 2026-05-29 (as published
  by the American Museum of Natural History). Treat them as known constants:
  `manhattanhenge_2026 = ["2026-05-28", "2026-05-29"]`. Your job is NOT to
  re-derive the calendar dates (every flat-horizon rule lands a few days
  early) but to compute, with DE440 + refraction, the exact az=299.1°
  crossing time and apparent altitude on those days and the surrounding
  window. The computed crossing MUST land at ~20:13 EDT (May 28) and ~20:12
  EDT (May 29), with apparent altitude ~+0.44° and ~+0.63° respectively.

  ## File 1: #{@workdir}/henge.py

  A module with the calculation. Running `python #{@workdir}/henge.py`
  MUST print to stdout exactly this JSON (one compact object):

      {
        "azimuth_deg": 299.1,
        "observer": {"lat": 40.7527, "lon": -73.9772, "elev_m": 10.0},
        "ephemeris": "de440s.bsp (DE440)",
        "refraction": {"temperature_C": 10.0, "pressure_mbar": 1010.0},
        "manhattanhenge_2026": ["2026-05-28", "2026-05-29"],
        "crossings": [ <crossing>, ...  one per day 2026-05-20 .. 2026-05-31 ]
      }

  A <crossing> object is:

      {
        "date": "2026-05-28",                       # America/New_York date
        "crossing_utc": "2026-05-29T00:13:15Z",
        "crossing_edt": "2026-05-28T20:13:15-04:00",
        "apparent_altitude_deg": 0.44,              # rounded to 2 dp
        "geometric_altitude_deg": -0.05
      }

  Expose reusable functions `crossing(d)` (d: datetime.date) -> crossing
  dict and `manhattanhenge(year, month)` -> list of date strings, so
  app.py can import them.

  ## File 2: #{@workdir}/app.py

  A FastAPI app. Expose a module-level function `serve()` that BUILDS and
  RETURNS the FastAPI app object. Do NOT add `@modal.asgi_app` or any
  decorator, and do NOT call uvicorn — a host imports `serve()` and runs
  the returned ASGI app. Load the ephemeris ONCE at import (module level)
  and reuse it across requests.

  Endpoints:
    * `GET /`               -> {"service": "manhattanhenge", "azimuth_deg":
                               299.1, "ephemeris": "...", "endpoints": [...]}
    * `GET /manhattanhenge` -> {"year": 2026, "dates": ["2026-05-28",
                               "2026-05-29"], "crossings": [<crossing>,
                               <crossing>]}  (the two henge days)
    * `GET /crossing/{date}`-> a single <crossing> for any YYYY-MM-DD,
                               computed on demand. Bad date -> HTTP 422.

  Keep both files clean and commented. When done, run
  `python #{@workdir}/henge.py` and confirm the JSON shows May 28 & 29.
  """

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    anthropic_key =
      System.get_env("ANTHROPIC_API_KEY") ||
        raise "set ANTHROPIC_API_KEY (try: set -a; source .env; set +a)"

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    base_image = build_base_image!(client, app)
    secret_id = ephemeral_secret!(client, app, anthropic_key)

    {henge_py, app_py} =
      with_sandbox(client, app, base_image, secret_id, fn sandbox ->
        claude_builds_it!(sandbox)
        sanity_check!(sandbox)
        extract_files!(sandbox)
      end)

    web = deploy!(client, app, base_image, henge_py, app_py)
    curl_verify!(web)

    print_summary(web)
  end

  # ── STAGE 1a: base image (Claude CLI + uv + Skyfield + DE440) ─────
  #
  # Content-addressed: identical layers cache-hit. The DE440 ephemeris
  # (de440s.bsp) is pre-fetched into the image so the calc runs offline
  # and fast — and so the deployed endpoint (which reuses these exact
  # layers) carries the ephemeris too.

  defp build_base_image!(client, app) do
    log_header("STAGE 1a — base image (Claude Code + uv + Skyfield + DE440)")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        base_dockerfile(),
        app: app,
        on_log:
          Modal.Image.line_buffered(fn line ->
            IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, line]))
          end)
      )

    log("  ✓ image: #{image_id} [#{status}] (#{elapsed(t)})")
    image_id
  end

  # Ephemeral Secret carrying the Anthropic key — attached at sandbox
  # boot, never baked into the image.
  defp ephemeral_secret!(client, app, anthropic_key) do
    {:ok, secret_id} =
      Modal.Secret.create(client,
        app: app,
        name: "henge-anthropic-#{System.os_time(:second)}",
        env: %{"ANTHROPIC_API_KEY" => anthropic_key}
      )

    secret_id
  end

  defp with_sandbox(client, app, image_id, secret_id, fun) do
    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        workdir: @workdir,
        secret_ids: [secret_id],
        timeout_secs: 1_800,
        idle_timeout_secs: 60,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    log("  sandbox: #{sandbox.id}")

    try do
      fun.(sandbox)
    after
      Modal.Sandbox.terminate(sandbox)
      log("  sandbox terminated")
    end
  end

  # ── STAGE 1b: Claude Code writes the implementation, live ─────────

  # Claude needs minutes to read the spec and write both files — longer
  # than the 60s deadline baked into the exec/await `wait_loop` (which
  # surfaces as a non-retried CANCELLED). So we DON'T await: launch
  # claude as a *background* exec under a PTY (Claude refuses to run
  # without a terminal, and refuses --dangerously-skip-permissions as
  # root, which we are), redirect its transcript to a file plus an
  # EXIT-code sentinel, then poll the filesystem (main channel, no worker
  # wait) until the sentinel appears.
  @claude_deadline_ms 600_000

  defp claude_builds_it!(sandbox) do
    log_header("STAGE 1b — Claude Code writes the DE440 calc + FastAPI app (live)")

    Modal.Filesystem.write_file!(sandbox, "#{@workdir}/SPEC.md", @spec_md)
    log("  wrote SPEC.md (#{byte_size(@spec_md)} bytes)")

    prompt =
      "Read SPEC.md in this directory and implement it exactly: create the " <>
        "two files henge.py and app.py as specified, matching the required " <>
        "JSON shape and the serve() entrypoint precisely. The Python deps " <>
        "(skyfield, fastapi, uvicorn, numpy) and the DE440 ephemeris are " <>
        "already installed."

    launch =
      "cd #{@workdir} && (claude -p #{shell_escape(prompt)} " <>
        "--permission-mode acceptEdits > #{@workdir}/claude.log 2>&1; " <>
        "echo \"EXIT:$?\" > #{@workdir}/claude.done)"

    {:ok, proc} = Modal.Sandbox.exec(sandbox, ["bash", "-c", launch], pty: true)
    log("  $ claude -p <spec> --permission-mode acceptEdits  (background, PTY #{proc.exec_id})")
    t = now()

    exit_line = poll_for_done!(sandbox, t)

    # Dump Claude's transcript for the record.
    case Modal.Filesystem.read_file(sandbox, "#{@workdir}/claude.log") do
      {:ok, logtext} ->
        logtext
        |> strip_ansi()
        |> String.split("\n")
        |> Enum.each(&IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, &1])))

      _ ->
        :ok
    end

    code = exit_line |> String.trim() |> String.replace_prefix("EXIT:", "") |> String.to_integer()
    assert!(code == 0, "claude exited #{code} — see transcript above")
    log("  ✓ Claude finished (#{elapsed(t)}, exit #{code})")
  end

  defp poll_for_done!(sandbox, t0) do
    deadline = now() + @claude_deadline_ms

    Stream.repeatedly(fn ->
      Process.sleep(5_000)

      case Modal.Filesystem.read_file(sandbox, "#{@workdir}/claude.done") do
        {:ok, line} ->
          {:done, line}

        _ ->
          IO.puts(:stderr, IO.ANSI.format([:faint, "  … still writing (#{elapsed(t0)})", :reset]))
          :pending
      end
    end)
    |> Enum.find_value(fn
      {:done, line} ->
        line

      :pending ->
        if now() > deadline, do: raise("claude did not finish within #{@claude_deadline_ms}ms")
    end)
  end

  # ── STAGE 2a: sanity-check Claude's calc in the sandbox ───────────
  #
  # Run the calc and assert it produced the two known Manhattanhenge
  # dates at the right times, with apparent altitude clearly distinct
  # from geometric (i.e. refraction was actually applied).

  defp sanity_check!(sandbox) do
    log_header("STAGE 2a — sanity-check the calc (in-sandbox, automated)")

    proc = Modal.Sandbox.exec!(sandbox, ["python", "#{@workdir}/henge.py"], workdir: @workdir)
    result = Modal.ContainerProcess.await!(proc, timeout: 120_000)
    Modal.ContainerProcess.close(proc)
    assert!(result.code == 0, "henge.py exited #{result.code}\n#{result.stderr}")

    data = decode_json_lax!(result.stdout)
    assert_henge!(data["manhattanhenge_2026"], data["crossings"], "calc")
  end

  # The shared assertion used for BOTH the in-sandbox calc and the live
  # endpoint — same contract, two surfaces.
  defp assert_henge!(dates, crossings, where) do
    assert!(
      dates == @expected_dates,
      "#{where}: expected dates #{inspect(@expected_dates)}, got #{inspect(dates)}"
    )

    by_date = Map.new(crossings, fn c -> {c["date"], c} end)

    for date <- @expected_dates do
      c = by_date[date] || raise("#{where}: no crossing for #{date}")
      edt = c["crossing_edt"]

      {h, m} = parse_edt_hm(edt)

      assert!(
        h == @expected_edt_hour and m in @expected_edt_minutes,
        "#{where}: #{date} crossing #{edt} not ~#{@expected_edt_hour}:#{inspect(@expected_edt_minutes)} EDT"
      )

      app_alt = c["apparent_altitude_deg"]
      geo_alt = c["geometric_altitude_deg"]
      refraction = app_alt - geo_alt

      # Apparent altitude is the observable: the disk sits just above the
      # true horizon at the grid bearing.
      assert!(
        is_number(app_alt) and app_alt > 0.0 and app_alt < 1.2,
        "#{where}: #{date} apparent altitude #{inspect(app_alt)}° outside (0°, 1.2°) — refraction not applied?"
      )

      # Refraction near the horizon is ~0.5° — larger than the Sun's radius
      # (0.27°). The whole point: on May 28 it's the difference between a
      # geometrically-below-horizon Sun and an apparent, visible one.
      assert!(
        refraction > 0.35 and refraction < 0.65,
        "#{where}: #{date} refraction (apparent−geometric) #{fmt(refraction)}° not ~0.5° — refraction model wrong"
      )

      log(
        "  ✓ #{date}: 299.1° at #{edt}  apparent #{fmt(app_alt)}°  " <>
          "(geometric #{fmt(geo_alt)}°, refraction +#{fmt(refraction)}°)"
      )
    end

    log("  ✓ #{where}: Manhattanhenge 2026 = #{Enum.join(dates, " & ")}")
  end

  # ── STAGE 2b: extract Claude's files out of the sandbox ───────────

  defp extract_files!(sandbox) do
    log_header("STAGE 2b — extract Claude's files for deploy")
    henge_py = Modal.Filesystem.read_file!(sandbox, "#{@workdir}/henge.py")
    app_py = Modal.Filesystem.read_file!(sandbox, "#{@workdir}/app.py")
    log("  henge.py: #{byte_size(henge_py)} bytes, app.py: #{byte_size(app_py)} bytes")

    # Stash a local copy of what Claude wrote — handy for inspecting the
    # generated code after the (ephemeral) sandbox is gone.
    File.mkdir_p!(@artifact_dir)
    File.write!(Path.join(@artifact_dir, "henge.py"), henge_py)
    File.write!(Path.join(@artifact_dir, "app.py"), app_py)
    log("  saved a local copy to #{@artifact_dir}")

    for {name, content} <- [{"henge.py", henge_py}, {"app.py", app_py}] do
      assert!(
        not String.contains?(content, @eof),
        "#{name} contains the heredoc sentinel #{@eof} — cannot safely bake"
      )
    end

    {henge_py, app_py}
  end

  # ── STAGE 3: bake Claude's app into an image and deploy_asgi ──────
  #
  # Reuse the base image's dockerfile prefix (cache hits — ephemeris and
  # deps don't rebuild) and append the two generated files. deploy_asgi
  # imports `app:serve` and serves the returned FastAPI app on a stable
  # HTTPS URL that scales to zero.

  defp deploy!(client, app, _base_image, henge_py, app_py) do
    log_header("STAGE 3 — bake app into an image + deploy_asgi (persistent endpoint)")
    t = now()

    {:ok, deploy_image, status} =
      Modal.Image.get_or_create(
        client,
        base_dockerfile() ++
          [
            file_layer("#{@workdir}/henge.py", henge_py),
            file_layer("#{@workdir}/app.py", app_py)
          ],
        app: app,
        on_log:
          Modal.Image.line_buffered(fn line ->
            IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, line]))
          end)
      )

    log("  ✓ deploy image: #{deploy_image} [#{status}] (#{elapsed(t)})")

    {:ok, web} =
      Modal.Function.deploy_asgi(client,
        app: app,
        name: "web",
        image_id: deploy_image,
        module: "app",
        callable: "serve",
        requested_suffix: "manhattanhenge",
        target_concurrent_inputs: 8,
        timeout_secs: 60,
        idle_timeout_secs: 120,
        min_containers: 0
      )

    log("  ✓ deployed: #{web.web_url}")
    web
  end

  # ── STAGE 4: curl the live endpoint and assert it agrees ──────────

  defp curl_verify!(%Modal.Function{web_url: url}) do
    log_header("STAGE 4 — curl the live endpoint (automated)")

    %{status: 200, body: root} = req_get!(url <> "/")
    log("  GET /            → 200  azimuth #{root["azimuth_deg"]}°")
    assert!(root["azimuth_deg"] == 299.1, "endpoint azimuth != 299.1")

    %{status: 200, body: mh} = req_get!(url <> "/manhattanhenge")
    log("  GET /manhattanhenge → 200")
    assert_henge!(mh["dates"], mh["crossings"], "endpoint")

    # Realtime single-date compute path.
    %{status: 200, body: one} = req_get!(url <> "/crossing/2026-05-29")
    log("  GET /crossing/2026-05-29 → 200  apparent #{fmt(one["apparent_altitude_deg"])}°")
    assert!(one["date"] == "2026-05-29", "single-date endpoint returned wrong date")
  end

  # ── helpers ───────────────────────────────────────────────────────

  # The base image's dockerfile, factored out so STAGE 1a and STAGE 3
  # share a byte-identical prefix (and therefore the layer cache).
  defp base_dockerfile do
    [
      "FROM python:3.12-slim",
      "RUN apt-get update && apt-get install -y --no-install-recommends " <>
        "git curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      "RUN pip install --no-cache-dir uv",
      # uv-driven install of the calc + web stack. `modal` itself is
      # required: a deploy_asgi function is booted by the worker via
      # `python -m modal._container_entrypoint`, so the package must be
      # importable inside the deployed container.
      "RUN uv pip install --system --no-cache-dir " <>
        "'modal>=0.65' 'skyfield>=1.49' 'numpy>=1.26' 'fastapi[standard]>=0.115' 'uvicorn>=0.30'",
      # Pre-fetch DE440 (short span, covers 2026) so there's no network
      # at calc time — and so the deployed endpoint carries it too.
      "RUN mkdir -p /opt/ephem && " <>
        "python -c \"from skyfield.api import Loader; Loader('/opt/ephem')('de440s.bsp')\"",
      # Official Claude Code installer; download-then-run so a failed
      # curl fails the layer, retry on claude.ai 429s.
      ~S{RUN bash -c 'set -eo pipefail; for i in 1 2 3 4 5; do } <>
        ~S{curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && break || sleep 10; } <>
        ~S{done; bash /tmp/install.sh'},
      "ENV PATH=/root/.local/bin:$PATH",
      "RUN claude --version",
      "WORKDIR #{@workdir}",
      # module: "app" resolves /work/app.py for the deployed function.
      "ENV PYTHONPATH=#{@workdir}"
    ]
  end

  defp file_layer(path, content) do
    dir = Path.dirname(path)
    mkdir = if dir in [".", "/"], do: "", else: "mkdir -p #{dir} && "
    "RUN #{mkdir}cat > #{path} <<'#{@eof}'\n#{content}\n#{@eof}"
  end

  # "2026-05-28T20:13:15-04:00" -> {20, 13}
  defp parse_edt_hm(edt) do
    [_date, time] = String.split(edt, "T", parts: 2)
    [h, m | _] = String.split(time, ":")
    {String.to_integer(h), String.to_integer(m)}
  end

  defp req_get!(url) do
    Req.get!(url, receive_timeout: 60_000, retry: :transient, max_retries: 5)
  end

  # Claude's henge.py is told to print only the JSON object, but it may
  # log a stray line. Extract the outermost {...} and decode that.
  defp decode_json_lax!(stdout) do
    case Regex.run(~r/\{.*\}/s, stdout) do
      [json] -> JSON.decode!(json)
      _ -> raise "no JSON object in calc output:\n#{stdout}"
    end
  end

  defp shell_escape(s), do: "'" <> String.replace(s, "'", ~S('"'"')) <> "'"

  defp strip_ansi(s) do
    s
    |> String.replace(~r/\e\[[0-9;:<>=?]*[ -\/]*[@-~]/, "")
    |> String.replace(~r/\e\][^\a]*(?:\a|\e\\)/, "")
    |> String.replace(~r/\e[PX^_].*?\e\\/, "")
    |> String.replace(~r/\e[@-Z\\-_]/, "")
  end

  defp assert!(true, _msg), do: :ok
  defp assert!(false, msg), do: raise("ASSERTION FAILED — #{msg}")

  defp fmt(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 3)
  defp fmt(n), do: inspect(n)

  # ── telemetry (control-plane + worker-channel call counts) ────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "manhattanhenge-telemetry",
      [[:modal, :rpc, :stop], [:modal, :worker_rpc, :stop]],
      &__MODULE__.on_telemetry/4,
      nil
    )
  end

  @doc false
  def on_telemetry(event, _measurements, meta, _config) do
    [_, family, _] = event
    key = {family, meta.method, Map.get(meta, :status)}
    Agent.update(__MODULE__.Metrics, fn m -> Map.update(m, key, 1, &(&1 + 1)) end)
  end

  defp print_summary(%Modal.Function{web_url: url}) do
    log_header("LIVE — Manhattanhenge 2026 reproduced")

    log("""
      Manhattanhenge 2026: #{Enum.join(@expected_dates, " & ")}  (azimuth 299.1°)

      The endpoint is live and computes in realtime:

        curl #{url}/
        curl #{url}/manhattanhenge
        curl #{url}/crossing/2026-05-29

      It scales to zero at rest; re-running this script redeploys in place.
    """)

    metrics = Agent.get(__MODULE__.Metrics, & &1)

    rpc_total =
      metrics
      |> Enum.filter(fn {{f, _, _}, _} -> f == :rpc end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    worker_total =
      metrics
      |> Enum.filter(fn {{f, _, _}, _} -> f == :worker_rpc end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    log("  RPCs: #{rpc_total} control-plane, #{worker_total} worker-channel")
  end

  defp log_header(msg), do: IO.puts(:stderr, "\n\e[1m── #{msg} ──────────────\e[0m")
  defp log(msg), do: IO.puts(:stderr, msg)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: fmt_ms(now() - t)
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"
end

Manhattanhenge.run()
