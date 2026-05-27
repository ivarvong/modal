# Reproduce Manhattanhenge 2026, end to end, from Elixir.
#
# Three machine-checked steps:
#   1. BUILD   — run the Claude Code CLI in a Modal sandbox; it writes a
#                DE440/Skyfield calc + a FastAPI app from a short brief.
#   2. DEPLOY  — read the app out, bake it into an Image, deploy_asgi it.
#   3. VERIFY  — curl the live endpoint: smoke-test + correctness in one.
#
#     set -a; source .env; set +a     # MODAL_TOKEN_* + ANTHROPIC_API_KEY
#     elixir scripts/manhattanhenge.exs
#
# Azimuth 299.1° is the Manhattan grid's sunset bearing. The reported
# altitude is the apparent (refraction-corrected) one — near the horizon
# refraction (~0.5°) exceeds the Sun's radius, so geometric altitude is
# misleading. May 28 & 29 are the published 2026 dates, taken as given;
# the calc reproduces the crossing time and apparent altitude. See the PR
# for the full story.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:req, "~> 0.5"}
])

defmodule Manhattanhenge do
  @app_name "modal-elixir-manhattanhenge"
  @workdir "/work"

  # The gate: the published 2026 dates and the EDT crossing-time window,
  # asserted against the live endpoint.
  @expected_dates ["2026-05-28", "2026-05-29"]
  @expected_edt_hour 20
  @expected_edt_minutes 10..15

  # Heredoc sentinel used to bake Claude's generated files into the
  # deploy image. Guarded below — we refuse to bake content containing it.
  @eof "HENGE_FILE_EOF"

  # Where we stash a local copy of Claude's generated files (the sandbox
  # is ephemeral; this is just for inspection after the run).
  @artifact_dir "/tmp/henge_artifacts"

  # The brief for Claude. We pin only the I/O contract (JSON shape +
  # serve() entrypoint) so extraction and deploy stay deterministic; the
  # astronomy is Claude's, and STAGE 3 verifies it.
  @spec_md """
  # Manhattanhenge 2026 — build two files in #{@workdir}

  Manhattanhenge is the evening the setting Sun aligns with the Manhattan
  street grid: **azimuth 299.1°** (true north, clockwise). Compute it with
  **Skyfield + JPL DE440**, pre-installed at `/opt/ephem/de440s.bsp`:

      from skyfield.api import Loader
      eph = Loader('/opt/ephem')('de440s.bsp')

  Observer: Manhattan grid — lat 40.7527, lon -73.9772, elev 10 m.

  For an America/New_York date, find the instant the Sun's azimuth crosses
  299.1° on its afternoon descent toward sunset. Report the **apparent
  (refraction-corrected) altitude** there — near the horizon refraction
  (~0.5°) exceeds the Sun's radius (0.27°), so apparent, not geometric, is
  the observable; use `.altaz(temperature_C=10, pressure_mbar=1010)`. Also
  report the geometric altitude (plain `.altaz()`) for contrast. Use the
  true sea-level horizon — do NOT correct for the New Jersey Palisades. The
  2026 dates are the published **May 28 & 29** (treat as a known constant).

  ## #{@workdir}/henge.py

  A module exposing two functions for app.py to import:
    * `crossing(d: datetime.date) -> dict` with keys `date`,
      `crossing_utc` (ISO, `…Z`), `crossing_edt` (ISO, with offset),
      `apparent_altitude_deg`, `geometric_altitude_deg` — altitudes
      rounded to 2 dp. (For 2026-05-28: crossing_edt
      `2026-05-28T20:13:15-04:00`, apparent 0.44, geometric -0.05.)
    * `manhattanhenge(year, month) -> [date strings]`; May 2026 returns
      `["2026-05-28", "2026-05-29"]`.

  ## #{@workdir}/app.py

  A FastAPI app with a module-level `serve()` that builds and returns it
  (no `@modal.asgi_app`, no uvicorn — a host imports `serve()`). Load the
  ephemeris once at import. Routes:
    * `GET /` -> `{"service","azimuth_deg":299.1,"ephemeris","endpoints"}`
    * `GET /manhattanhenge` -> `{"year":2026,"dates":[…],"crossings":[…]}`
      for the two dates
    * `GET /crossing/{date}` -> one `<crossing>`; HTTP 422 on a bad date
  """

  def run do
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
        extract_files!(sandbox)
      end)

    web = deploy!(client, app, base_image, henge_py, app_py)
    verify!(web)

    print_summary(web)
  end

  # ── SETUP: base image (Claude CLI + uv + Skyfield + DE440) ────────
  #
  # Content-addressed: identical layers cache-hit. The DE440 ephemeris
  # (de440s.bsp) is pre-fetched into the image so the calc runs offline
  # and fast — and so the deployed endpoint (which reuses these exact
  # layers) carries the ephemeris too.

  defp build_base_image!(client, app) do
    log_header("SETUP — base image (Claude Code CLI + uv + Skyfield + DE440)")
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

  # ── STAGE 1 — BUILD: Claude Code writes the implementation, live ──

  defp claude_builds_it!(sandbox) do
    log_header("STAGE 1 — BUILD: Claude writes the DE440 calc + FastAPI app (live)")

    Modal.Filesystem.write_file!(sandbox, "#{@workdir}/SPEC.md", @spec_md)
    log("  wrote SPEC.md (#{byte_size(@spec_md)} bytes)")

    prompt =
      "Read SPEC.md in this directory and implement it exactly: create the " <>
        "two files henge.py and app.py as specified, matching the required " <>
        "JSON shape and the serve() entrypoint precisely. The Python deps " <>
        "(skyfield, fastapi, uvicorn, numpy) and the DE440 ephemeris are " <>
        "already installed."

    # PTY: claude needs a terminal (and refuses --dangerously-skip-permissions
    # as root). The run takes minutes — exec_streaming/3 handles long execs and
    # streams the transcript as it goes; it raises on a non-zero exit.
    cmd = "cd #{@workdir} && claude -p #{shell_escape(prompt)} --permission-mode acceptEdits 2>&1"
    log("  $ claude -p <spec> --permission-mode acceptEdits")
    t = now()

    result =
      Modal.Sandbox.exec_streaming!(sandbox, ["bash", "-c", cmd],
        on_stdout: fn chunk -> IO.write(IO.ANSI.format([:faint, strip_ansi(chunk), :reset])) end,
        exec_opts: [pty: true],
        timeout: :infinity
      )

    log("\n  ✓ Claude finished (#{elapsed(t)}, exit #{result.code})")
  end

  # The correctness gate, run against the live endpoint: the two
  # published dates, each crossing at ~20:1x EDT with an apparent
  # (refraction-corrected) altitude clearly above the geometric one.
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

      # Apparent altitude: the disk sits just above the true horizon.
      assert!(
        is_number(app_alt) and app_alt > 0.0 and app_alt < 1.2,
        "#{where}: #{date} apparent altitude #{inspect(app_alt)}° outside (0°, 1.2°) — refraction not applied?"
      )

      # Refraction near the horizon is ~0.5°; confirms it was applied
      # (apparent altitude well above geometric).
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

  # ── STAGE 2 — DEPLOY: read Claude's app out, bake an Image, deploy ─

  defp extract_files!(sandbox) do
    log_header("STAGE 2 — DEPLOY: read Claude's app out, bake an Image, deploy_asgi")
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

  # Reuse the base image's dockerfile prefix (cache hits — ephemeris and
  # deps don't rebuild) and append the two generated files. deploy_asgi
  # imports `app:serve` and serves the returned FastAPI app on a stable
  # HTTPS URL that scales to zero.

  defp deploy!(client, app, _base_image, henge_py, app_py) do
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

  # ── STAGE 3 — VERIFY: smoke-test + correctness on the live endpoint ─

  defp verify!(%Modal.Function{web_url: url}) do
    log_header("STAGE 3 — VERIFY: smoke-test + correctness on the live endpoint")

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

  # The base image's dockerfile, factored out so SETUP and STAGE 2
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
  end

  defp log_header(msg), do: IO.puts(:stderr, "\n\e[1m── #{msg} ──────────────\e[0m")
  defp log(msg), do: IO.puts(:stderr, msg)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: fmt_ms(now() - t)
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"
end

Manhattanhenge.run()
