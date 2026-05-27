# Manhattanhenge 2026 — Claude Code builds it on Modal, Modal serves it.
#
# Modal runs both phases, and a Volume is the handoff — the generated code
# never touches the orchestrator's disk:
#
#   1. BUILD  — a sandbox runs the Claude Code CLI, which writes (and
#               smoke-tests) app.py — DE440/Skyfield calc + FastAPI — onto a
#               mounted Volume. On sandbox exit the worker commits the Volume.
#   2. DEPLOY — deploy_asgi mounts the same Volume read-only and serves
#               app.py directly: same base image, no copy-out, no rebake.
#   3. VERIFY — curl the live endpoint: smoke-test + correctness in one.
#
#     set -a; source .env; set +a     # MODAL_TOKEN_* + ANTHROPIC_API_KEY
#     elixir scripts/manhattanhenge.exs
#
# Azimuth 299.1° is the Manhattan grid's sunset bearing; the reported
# altitude is apparent (refraction-corrected) — near the horizon refraction
# (~0.5°) exceeds the Sun's radius (0.27°), so geometric is misleading.
# May 28 & 29 are the published 2026 dates. See the PR for the full story.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:req, "~> 0.5"}
])

defmodule Manhattanhenge do
  @app_name "modal-elixir-manhattanhenge"
  @workdir "/work"

  # The Volume that carries Claude's app from the build sandbox to the
  # deployed function. Mounted read-write on the sandbox, read-only on the
  # function — the handoff happens entirely on Modal.
  @volume_name "manhattanhenge-app"

  # Model the Claude Code CLI runs the build with.
  @claude_model "claude-sonnet-4-6"

  # Local copy of Claude's app.py (read back from the Volume) + the full
  # session transcript, for inspection after the run.
  @artifact_dir "/tmp/henge_artifacts"
  @transcript_file Path.join(@artifact_dir, "claude_transcript.jsonl")

  # The gate: the published 2026 dates and the EDT crossing-time window,
  # asserted against the live endpoint.
  @expected_dates ["2026-05-28", "2026-05-29"]
  @expected_edt_hour 20
  @expected_edt_minutes 10..15

  # Claude's brief. We pin only the I/O contract (the `serve()` entrypoint,
  # the routes, and the JSON shape) so deploy + verify are deterministic;
  # the astronomy and the file's internal structure are Claude's, and
  # STAGE 3 verifies the result.
  @spec_md """
  # Manhattanhenge 2026 — write a single file: #{@workdir}/app.py

  Manhattanhenge is the evening the setting Sun aligns with Manhattan's
  street grid: azimuth 299.1° (true north, clockwise). Compute it with
  Skyfield + JPL DE440 (pre-installed at `/opt/ephem/de440s.bsp` — load via
  `Loader('/opt/ephem')`), for an observer at 42nd St & 5th Ave — use these
  exact coordinates: `wgs84.latlon(40.75348868877207, -73.98088776620406)`.

  For a date, find the afternoon instant the Sun's azimuth crosses 299.1°,
  and report two altitudes there:
    * `apparent_altitude_deg` — refraction-corrected, the observable
      (`.altaz(temperature_C=10, pressure_mbar=1010)`)
    * `geometric_altitude_deg` — no refraction (plain `.altaz()`), for contrast

  The 2026 Manhattanhenge dates are May 28 & 29 (treat as known).

  `app.py` exposes a module-level `serve()` returning a FastAPI app (no
  `@modal` decorator, no uvicorn; load the ephemeris once at import). A
  "crossing" is a dict with keys `date`, `crossing_utc` (ISO `…Z`),
  `crossing_edt` (ISO with offset), `apparent_altitude_deg`,
  `geometric_altitude_deg` (altitudes rounded to 2 dp). Routes:
    * `GET /`               -> `{"service","azimuth_deg":299.1,"ephemeris","endpoints"}`
    * `GET /manhattanhenge`  -> `{"year":2026,"dates":["2026-05-28","2026-05-29"],"crossings":[<crossing>,<crossing>]}`
    * `GET /crossing/{date}` -> one crossing dict; 422 on a bad date
    * `GET /source`          -> this app's own source code as `text/plain`
                                (read `__file__`) — a peek at exactly what's
                                running in prod, served off the Volume
    * `GET /transcript`      -> the Claude Code session that built this app,
                                from `transcript.jsonl` next to this file
                                (`text/plain`; a short note if it's absent)

  Write it production-grade: use `zoneinfo("America/New_York")` for local
  time (not a fixed UTC offset, so DST stays correct); validate
  `/crossing/{date}` — return 4xx for an unparseable date, a date outside
  DE440's range, or one with no 299.1° crossing (never a bogus result);
  `@lru_cache` the deterministic per-date computation; and add short
  docstrings for the non-obvious astronomy (apparent vs geometric, the
  299.1° grid bearing). `/source` is meant to be read.
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
    {:ok, vol_id} = Modal.Volume.get_or_create(client, @volume_name, app: app)
    secret_id = ephemeral_secret!(client, app, anthropic_key)

    build_on_volume!(client, app, base_image, vol_id, secret_id)
    web = deploy!(client, app, base_image, vol_id)
    verify!(web)

    print_summary(web)
  end

  # ── SETUP: base image (Claude CLI + uv + Skyfield + DE440) ────────
  #
  # Content-addressed, so identical layers cache-hit. The DE440 ephemeris
  # is baked in (offline + fast), and the deployed function reuses this
  # exact image — only app.py comes from the Volume.

  defp build_base_image!(client, app) do
    log_header("SETUP — base image (Claude Code CLI + uv + Skyfield + DE440)")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(client, base_dockerfile(),
        app: app,
        on_log:
          Modal.Image.line_buffered(fn line ->
            IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, line]))
          end)
      )

    log("  ✓ image: #{image_id} [#{status}] (#{elapsed(t)})")
    image_id
  end

  # Ephemeral Secret carrying the Anthropic key — attached at sandbox boot,
  # never baked into the image.
  defp ephemeral_secret!(client, app, anthropic_key) do
    {:ok, secret_id} =
      Modal.Secret.create(client,
        app: app,
        name: "henge-anthropic-#{System.os_time(:second)}",
        env: %{"ANTHROPIC_API_KEY" => anthropic_key}
      )

    secret_id
  end

  # ── STAGE 1 — BUILD: Claude writes app.py onto the Volume, live ───
  #
  # The sandbox mounts the Volume read-write at /work; Claude writes app.py
  # there. On sandbox exit the worker commits the Volume (sandbox mounts set
  # allow_background_commits) — no copy-out, and no in-container commit
  # (a sandbox can't authenticate one). STAGE 2 mounts the same Volume.

  defp build_on_volume!(client, app, base_image, vol_id, secret_id) do
    log_header("STAGE 1 — BUILD: Claude writes app.py onto the Volume (live)")

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: base_image,
        cmd: ["sleep", "infinity"],
        workdir: @workdir,
        secret_ids: [secret_id],
        volumes: [%Modal.Volume{id: vol_id, path: @workdir}],
        # Claude Code (Node) is memory-hungry — especially streaming a
        # verbose session — and OOM-kills (exit 137) with less. Give it room.
        memory_mb: 8192,
        timeout_secs: 1_800,
        idle_timeout_secs: 60,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    log("  sandbox #{sandbox.id}, Volume mounted read-write at #{@workdir}")

    # Clean room: the Volume persists across runs, so wipe any prior build
    # before Claude starts — otherwise it finds the last run's app.py and
    # patches it instead of writing fresh.
    Modal.Sandbox.exec_streaming!(sandbox, [
      "bash",
      "-c",
      "find #{@workdir} -mindepth 1 -delete 2>/dev/null; true"
    ])

    # SPEC.md goes in /work — Claude (acceptEdits) is sandboxed to its
    # working dir, so a spec under /tmp would be unreadable. It lands on the
    # Volume too, but that's harmless: the function imports only `app`.
    Modal.Filesystem.write_file!(sandbox, "#{@workdir}/SPEC.md", @spec_md)

    prompt =
      "Read SPEC.md in this directory and implement it exactly: write app.py " <>
        "here (#{@workdir}), matching the serve() entrypoint, routes, and JSON " <>
        "shape precisely. The Python deps (skyfield, fastapi, uvicorn, numpy) " <>
        "and the DE440 ephemeris are already installed. Smoke-test before " <>
        "finishing: `python3 -c 'from app import serve; serve()'` must run clean."

    # PTY: claude needs a terminal (and refuses --dangerously-skip-permissions
    # as root). `--allowedTools Bash` lets it run python to smoke-test its own
    # app (acceptEdits alone blocks Bash). `--output-format stream-json
    # --verbose` emits one JSON event per turn — a transcript we render + save
    # — plus a final event with total_cost_usd. Raises on a non-zero exit.
    cmd =
      "cd #{@workdir} && claude -p #{shell_escape(prompt)} " <>
        "--permission-mode acceptEdits --allowedTools Bash --model #{@claude_model} " <>
        "--output-format stream-json --verbose 2>&1"

    log("  $ claude -p <spec> --model #{@claude_model}  (writing app.py, a few min)…")
    t = now()

    result =
      Modal.Sandbox.exec_streaming!(sandbox, ["bash", "-c", cmd],
        exec_opts: [pty: true],
        timeout: :infinity
      )

    transcript = strip_ansi(result.stdout)
    log("  ✓ Claude finished (#{elapsed(t)})#{render_transcript_and_cost!(transcript)}")

    # Put the session transcript on the Volume too, so the deployed app can
    # serve it (GET /transcript) right next to its own source.
    Modal.Filesystem.write_file!(sandbox, "#{@workdir}/transcript.jsonl", transcript)

    # Sandbox exit commits the Volume; confirm from the orchestrator (a
    # committed Volume is readable here) and stash a local copy.
    Modal.Sandbox.terminate(sandbox)
    stash_from_volume!(client, vol_id)
  end

  defp stash_from_volume!(client, vol_id) do
    app_py = wait_for_volume_file!(client, vol_id, "/app.py")
    File.mkdir_p!(@artifact_dir)
    File.write!(Path.join(@artifact_dir, "app.py"), app_py)
    log("  ✓ Volume committed (app.py #{byte_size(app_py)}B); local copy in #{@artifact_dir}")
  end

  # Poll the committed Volume from the orchestrator until app.py lands (the
  # worker's on-exit commit is usually done by the first read).
  defp wait_for_volume_file!(client, vol_id, path) do
    deadline = now() + 30_000

    Stream.repeatedly(fn ->
      case Modal.Volume.get_file(client, vol_id, path) do
        {:ok, bytes} ->
          {:ok, bytes}

        _ ->
          Process.sleep(1_000)
          :pending
      end
    end)
    |> Enum.find_value(fn
      {:ok, bytes} -> bytes
      :pending -> if now() > deadline, do: raise("#{path} not committed to the Volume within 30s")
    end)
  end

  # ── STAGE 2 — DEPLOY: serve straight off the Volume ───────────────
  #
  # No copy-out, no second image: deploy_asgi mounts the same Volume
  # read-only and reuses the base image. `module: "app"` resolves
  # /work/app.py off the Volume (PYTHONPATH=/work). Autoscaling, stable
  # HTTPS URL, scales to zero.

  defp deploy!(client, app, base_image, vol_id) do
    log_header("STAGE 2 — DEPLOY: deploy_asgi serving app.py from the Volume")
    t = now()

    {:ok, web} =
      Modal.Function.deploy_asgi(client,
        app: app,
        name: "web",
        image_id: base_image,
        volumes: [%Modal.Volume{id: vol_id, path: @workdir, read_only: true}],
        module: "app",
        callable: "serve",
        requested_suffix: "manhattanhenge",
        target_concurrent_inputs: 8,
        timeout_secs: 60,
        idle_timeout_secs: 120,
        min_containers: 0
      )

    log("  ✓ deployed: #{web.web_url} (#{elapsed(t)})")
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

    # Realtime single-date compute path — the serve function does real work.
    %{status: 200, body: one} = req_get!(url <> "/crossing/2026-05-29")
    log("  GET /crossing/2026-05-29 → 200  apparent #{fmt(one["apparent_altitude_deg"])}°")
    assert!(one["date"] == "2026-05-29", "single-date endpoint returned wrong date")

    # The app serves its own source off the Volume — a peek at what's in prod.
    %{status: 200, body: src} = req_get!(url <> "/source")
    src = to_string(src)
    log("  GET /source → 200  (#{byte_size(src)}B of the app's own source)")
    assert!(String.contains?(src, "serve"), "/source didn't return the app's own source")

    # …and the Claude session that built it, also off the Volume.
    %{status: 200, body: tx} = req_get!(url <> "/transcript")
    tx = to_string(tx)
    log("  GET /transcript → 200  (#{byte_size(tx)}B of the build session)")
    assert!(String.contains?(tx, "assistant"), "/transcript didn't return the build session")
  end

  # The correctness gate: the two published dates, each crossing at ~20:1x
  # EDT with an apparent (refraction-corrected) altitude clearly above the
  # geometric one.
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

      # Refraction near the horizon is ~0.5° — confirms it was applied.
      assert!(
        refraction > 0.35 and refraction < 0.65,
        "#{where}: #{date} refraction (apparent−geometric) #{fmt(refraction)}° not ~0.5°"
      )

      log(
        "  ✓ #{date}: 299.1° at #{edt}  apparent #{fmt(app_alt)}°  " <>
          "(geometric #{fmt(geo_alt)}°, refraction +#{fmt(refraction)}°)"
      )
    end

    log("  ✓ #{where}: Manhattanhenge 2026 = #{Enum.join(dates, " & ")}")
  end

  # ── helpers ───────────────────────────────────────────────────────

  # Render claude's stream-json session as a readable transcript, save the
  # raw events, and return a " — $cost, N turns" suffix from the result event.
  defp render_transcript_and_cost!(raw) do
    File.mkdir_p!(@artifact_dir)
    File.write!(@transcript_file, raw)

    events =
      raw
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case JSON.decode(String.trim(line)) do
          {:ok, ev} when is_map(ev) -> [ev]
          _ -> []
        end
      end)

    log("  ── Claude session transcript ──────────────")
    Enum.each(events, &render_event/1)
    log("  ── (full session-json: #{@transcript_file}) ──")

    case Enum.find(events, &(&1["type"] == "result")) do
      %{"total_cost_usd" => c} = r ->
        "  —  $#{:erlang.float_to_binary(c / 1, decimals: 4)}, #{r["num_turns"] || "?"} turns"

      _ ->
        "  (cost: unavailable)"
    end
  end

  defp render_event(%{"type" => "system", "subtype" => "init"} = ev),
    do: log(IO.ANSI.format([:faint, "    · session start — model #{ev["model"]}", :reset]))

  defp render_event(%{"type" => "assistant", "message" => %{"content" => content}})
       when is_list(content) do
    Enum.each(content, fn
      %{"type" => "text", "text" => txt} ->
        if String.trim(txt) != "",
          do: log(IO.ANSI.format([:faint, "    🤖 ", String.trim(txt), :reset]))

      %{"type" => "tool_use", "name" => name} = tu ->
        log(IO.ANSI.format([:faint, "    🔧 #{name} #{tool_brief(tu["input"])}", :reset]))

      _ ->
        :ok
    end)
  end

  defp render_event(_), do: :ok

  defp tool_brief(%{"file_path" => p}), do: p
  defp tool_brief(%{"command" => c}), do: c |> to_string() |> String.slice(0, 70)
  defp tool_brief(%{"path" => p}), do: p
  defp tool_brief(_), do: ""

  # Python + uv + the calc/web deps + the DE440 ephemeris + the Claude CLI.
  # The deployed function reuses this exact image; app.py comes from the
  # Volume, not the image.
  defp base_dockerfile do
    [
      "FROM python:3.12-slim",
      "RUN apt-get update && apt-get install -y --no-install-recommends " <>
        "git curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      "RUN pip install --no-cache-dir uv",
      # `modal` is required: a deploy_asgi function is booted by the worker
      # via `python -m modal._container_entrypoint`, so it must be importable.
      "RUN uv pip install --system --no-cache-dir " <>
        "'modal>=0.65' 'skyfield>=1.49' 'numpy>=1.26' 'fastapi[standard]>=0.115' 'uvicorn>=0.30'",
      # Pre-fetch DE440 (short span, covers 2026) — no network at calc time.
      "RUN mkdir -p /opt/ephem && " <>
        "python -c \"from skyfield.api import Loader; Loader('/opt/ephem')('de440s.bsp')\"",
      # Official Claude Code installer; download-then-run so a failed curl
      # fails the layer, retry on claude.ai 429s.
      ~S{RUN bash -c 'set -eo pipefail; for i in 1 2 3 4 5; do } <>
        ~S{curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && break || sleep 10; } <>
        ~S{done; bash /tmp/install.sh'},
      "ENV PATH=/root/.local/bin:$PATH",
      "RUN claude --version",
      "WORKDIR #{@workdir}",
      # module: "app" resolves /work/app.py (from the Volume) for the function.
      "ENV PYTHONPATH=#{@workdir}"
    ]
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

      Claude Code built app.py in a Modal sandbox; it lives on a Modal
      Volume; a Modal Function serves it. Hit it:

        curl #{url}/
        curl #{url}/manhattanhenge
        curl #{url}/crossing/2026-05-29
        curl #{url}/source            # the app's own source, off the Volume
        curl #{url}/transcript        # the Claude session that built it

      Scales to zero at rest; re-running redeploys in place.
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
