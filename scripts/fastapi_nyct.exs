# NYC Transit GTFS-Realtime on Modal — the staff+ pattern:
# scheduled poller + autoscaling web tier sharing a Modal.Dict cache.
#
# Architecture:
#
#   ┌──────────────────┐     Modal.Dict.put    ┌──────────────────┐
#   │ poller           │ ─────────────────────▶│ web (N×)         │
#   │ (Modal.Function  │                       │ (deploy_asgi,    │
#   │  schedule: 15s   │                       │  target_concurr  │
#   │  retries: 3)     │                       │  ent_inputs: 64) │
#   │ fetch MTA → ...  │                       │ Modal.Dict.get   │
#   └──────────────────┘                       └──────────────────┘
#                       ┌─────────────────────────┐
#                       │ Modal.Dict "nyct-feeds" │
#                       │  "{route}:bytes" → raw  │
#                       │  "{route}:etag"  → str  │
#                       │  "{route}:ts"    → unix │
#                       │  "{route}:err"   → ...  │
#                       └─────────────────────────┘
#
# Why this beats v1 (single Function with per-container FeedCache):
#
#   * **One MTA fetch per 15s, period.** v1 had each web container
#     running its own TTL refresher — 5 containers = 5× the MTA
#     load. Here the poller is the single source of truth.
#   * **Web tier is fully stateless** — every container reads from
#     Modal.Dict. Cold starts get warm data immediately. Scale 0→N
#     with zero per-container warm-up.
#   * **target_concurrent_inputs: 64** collapses container count
#     for the I/O-bound serving path. One container handles a burst
#     of 64 concurrent requests instead of Modal spinning up 64.
#   * **Conditional GET** — poller stores MTA's ETag in Dict and
#     sends `If-None-Match` on the next fetch. 304s save bandwidth
#     and signal-to-noise to MTA.
#   * **Modal handles retries** via `retries: 3` on the poller —
#     no hand-rolled retry loop, exponential backoff for free.
#
# Phases the script runs through:
#
#   1. Build the Modal Image (FastAPI + GTFS protobufs + the
#      poller and web modules baked in).
#   2. `pytest` the parser logic in a transient sandbox — broken
#      commits can't progress past this gate.
#   3. Create or reuse Modal.Dict "nyct-feeds".
#   4. Deploy the poller via `Modal.Function.deploy_function/2`
#      with `schedule: {:period, seconds: 15}`.
#   5. Deploy the web tier via `Modal.Function.deploy_asgi/2`
#      with `target_concurrent_inputs: 64`.
#   6. Wait for the poller's first fire to populate the Dict,
#      then hit /trains/{route} and /health to verify.
#
# Both Functions stay deployed across runs; rerunning the script
# updates them in place. The Modal.Dict persists across runs and
# across redeploys.
#
#     elixir scripts/fastapi_nyct.exs
#
# Needs (in .env):
#   MODAL_TOKEN_ID, MODAL_TOKEN_SECRET   — modal.com

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:req, "~> 0.5"}
])

defmodule FastapiNyct do
  @app_name "modal-elixir-fastapi-nyct"
  @poller_name "poll"
  @web_name "web"
  @dict_name "nyct-feeds"

  # ── The Python project, baked into the image ─────────────────────

  @initial_files [
    {"pyproject.toml",
     """
     [project]
     name = "nyct-gtfs"
     version = "0.2.0"
     description = "NYC Transit GTFS-Realtime — poller + web split."
     requires-python = ">=3.11"
     dependencies = [
         "modal>=0.65",
         "fastapi>=0.115",
         "httpx>=0.27",
         "gtfs-realtime-bindings>=1.0",
     ]

     [project.optional-dependencies]
     dev = ["pytest>=8.0", "pytest-asyncio>=0.24"]

     [build-system]
     requires = ["setuptools>=68"]
     build-backend = "setuptools.build_meta"

     [tool.setuptools.packages.find]
     include = ["app*"]

     [tool.pytest.ini_options]
     asyncio_mode = "auto"
     asyncio_default_fixture_loop_scope = "function"
     filterwarnings = [
         "ignore::DeprecationWarning",
     ]
     """},
    {"app/__init__.py", "__version__ = \"0.2.0\"\n"},
    {"app/feeds.py",
     """
     \"\"\"
     Static facts about NYC Transit GTFS-Realtime feeds. Used by both
     the poller and the web tier; kept in one module so they can't
     drift out of sync.
     \"\"\"
     FEED_URLS = {
         "1234567": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
         "ace":     "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
         "bdfm":    "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
         "g":       "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g",
         "jz":      "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
         "l":       "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l",
         "nqrw":    "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
         "sir":     "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si",
     }

     # Map a single-letter route to the feed group containing it.
     # E.g. trips on the F train live in the "bdfm" feed.
     ROUTE_TO_GROUP = {}
     for group in FEED_URLS:
         for ch in group:
             if ch.isalpha() or ch.isdigit():
                 ROUTE_TO_GROUP[ch.upper()] = group
     """},
    {"app/poller.py",
     """
     \"\"\"
     The scheduled poller. Modal invokes `poll()` every 15 seconds
     (configured by `Modal.Function.deploy_function/2` on the Elixir
     side). On each fire, fetches every MTA feed (conditional GET via
     ETag) and writes the raw protobuf bytes to a shared Modal.Dict.

     This is the ONLY process talking to MTA. The web tier reads from
     the Dict and never touches MTA directly.
     \"\"\"
     import asyncio
     import os
     import time

     import httpx
     import modal

     from app.feeds import FEED_URLS

     DICT_NAME = os.environ.get("FEEDS_DICT_NAME", "nyct-feeds")


     async def _fetch_one(client: httpx.AsyncClient, feeds, route: str, url: str) -> dict:
         t0 = time.monotonic()
         etag_prev = await feeds.get.aio(f"{route}:etag")
         headers = {"If-None-Match": etag_prev} if etag_prev else {}

         try:
             resp = await client.get(url, headers=headers, timeout=10.0)
         except Exception as e:
             # Don't overwrite good data — only record the failure.
             await feeds.put.aio(f"{route}:last_error", repr(e))
             await feeds.put.aio(f"{route}:last_error_ts", time.time())
             return {"route": route, "status": "error", "ms": _ms(t0)}

         if resp.status_code == 304:
             await feeds.put.aio(f"{route}:checked_ts", time.time())
             return {"route": route, "status": "304", "ms": _ms(t0)}

         if resp.status_code != 200:
             await feeds.put.aio(f"{route}:last_error", f"http {resp.status_code}")
             await feeds.put.aio(f"{route}:last_error_ts", time.time())
             return {"route": route, "status": resp.status_code, "ms": _ms(t0)}

         now = time.time()
         await feeds.put.aio(f"{route}:bytes", resp.content)
         await feeds.put.aio(f"{route}:etag", resp.headers.get("etag", ""))
         await feeds.put.aio(f"{route}:ts", now)
         await feeds.put.aio(f"{route}:checked_ts", now)
         return {"route": route, "status": "200", "bytes": len(resp.content), "ms": _ms(t0)}


     def _ms(t0: float) -> int:
         return int((time.monotonic() - t0) * 1000)


     async def poll() -> dict:
         feeds = modal.Dict.from_name(DICT_NAME, create_if_missing=False)

         async with httpx.AsyncClient(http2=False) as client:
             results = await asyncio.gather(
                 *(_fetch_one(client, feeds, route, url) for route, url in FEED_URLS.items())
             )

         summary = {
             "ts": time.time(),
             "fetched": [r for r in results if r["status"] == "200"],
             "unchanged": [r for r in results if r["status"] == "304"],
             "failed": [r for r in results if r["status"] not in ("200", "304")],
         }
         await feeds.put.aio("_meta:last_poll", summary)
         return summary
     """},
    {"app/web.py",
     """
     \"\"\"
     The stateless web tier. Reads from the shared Modal.Dict
     populated by the poller; never touches MTA directly.

     Three response states for /trains/{route}:
       * 503 warming    — poller hasn't filled this feed yet (first run).
       * 200 + X-Stale-Seconds header — normal; serve from Dict.
       * 503 stale      — feed older than STALE_THRESHOLD_SECS.
     \"\"\"
     import os
     import time
     from typing import Any

     import modal
     from fastapi import FastAPI, HTTPException
     from fastapi.responses import JSONResponse, Response

     from app.feeds import FEED_URLS, ROUTE_TO_GROUP

     DICT_NAME = os.environ.get("FEEDS_DICT_NAME", "nyct-feeds")
     STALE_THRESHOLD_SECS = 300


     def serve():
         # Module-level — one hydration per container.
         feeds = modal.Dict.from_name(DICT_NAME, create_if_missing=False)

         app = FastAPI()

         async def _get(key: str, default: Any = None) -> Any:
             return await feeds.get.aio(key, default)

         @app.get("/trains/{route}")
         async def trains(route: str):
             group = ROUTE_TO_GROUP.get(route.upper())
             if not group:
                 raise HTTPException(404, detail=f"unknown route {route!r}")
             return await _serve_group(group, route_filter=route.upper())

         @app.get("/feeds/{group}")
         async def feed_group(group: str):
             if group not in FEED_URLS:
                 raise HTTPException(404, detail=f"unknown group {group!r}; try one of {sorted(FEED_URLS)}")
             return await _serve_group(group)

         @app.get("/health")
         async def health():
             results = {}
             for group in FEED_URLS:
                 ts = await _get(f"{group}:ts")
                 checked_ts = await _get(f"{group}:checked_ts")
                 last_err = await _get(f"{group}:last_error")
                 last_err_ts = await _get(f"{group}:last_error_ts")
                 results[group] = {
                     "feed_age_secs": _age(ts),
                     "checked_age_secs": _age(checked_ts),
                     "last_error": last_err,
                     "last_error_age_secs": _age(last_err_ts),
                 }
             meta = await _get("_meta:last_poll")
             return {"feeds": results, "last_poll": meta}

         @app.get("/")
         async def root():
             return {
                 "service": "nyct-gtfs",
                 "routes": sorted(set(ROUTE_TO_GROUP.keys())),
                 "groups": sorted(FEED_URLS.keys()),
                 "endpoints": ["/trains/{route}", "/feeds/{group}", "/health"],
             }

         async def _serve_group(group: str, route_filter: str | None = None):
             bytes_ = await _get(f"{group}:bytes")
             if bytes_ is None:
                 raise HTTPException(503, detail=f"warming — poller hasn't filled {group!r} yet")
             ts = await _get(f"{group}:ts", 0.0)
             age = time.time() - ts
             if age > STALE_THRESHOLD_SECS:
                 raise HTTPException(
                     503, detail=f"feed {group!r} is {int(age)}s stale (poller may be down)"
                 )

             # Defer protobuf parsing until we know we'll respond.
             from google.transit import gtfs_realtime_pb2
             feed = gtfs_realtime_pb2.FeedMessage()
             feed.ParseFromString(bytes_)

             trips = []
             for entity in feed.entity:
                 if not entity.HasField("trip_update"):
                     continue
                 tu = entity.trip_update
                 r = tu.trip.route_id
                 if route_filter and r != route_filter:
                     continue
                 stops = [
                     {
                         "stop_id": s.stop_id,
                         "arrival": s.arrival.time if s.HasField("arrival") else None,
                         "departure": s.departure.time if s.HasField("departure") else None,
                     }
                     for s in tu.stop_time_update[:6]
                 ]
                 trips.append({"trip_id": tu.trip.trip_id, "route": r, "stops": stops})

             return JSONResponse(
                 {
                     "group": group,
                     "feed_timestamp": feed.header.timestamp,
                     "stale_seconds": int(age),
                     "trips_count": len(trips),
                     "trips": trips[:50],
                 },
                 headers={"X-Stale-Seconds": str(int(age)), "Cache-Control": "max-age=10"},
             )

         return app


     def _age(ts):
         return None if ts in (None, 0.0) else int(time.time() - ts)
     """},
    {"tests/__init__.py", ""},
    {"tests/test_parsing.py",
     """
     \"\"\"
     Tests for the static feed-group mapping. Pure-Python — no Modal,
     no network — so they run in the transient pytest sandbox before
     any deploy.
     \"\"\"
     from app.feeds import FEED_URLS, ROUTE_TO_GROUP


     def test_every_letter_route_maps_to_a_group():
         # The expected routes drawn from MTA's GTFS-rt feed list.
         expected_routes = set("ABCDEFGJLMNQRSWZ12345671")
         missing = expected_routes - set(ROUTE_TO_GROUP)
         assert not missing, f"routes missing from ROUTE_TO_GROUP: {missing}"


     def test_every_group_is_a_known_feed():
         for route, group in ROUTE_TO_GROUP.items():
             assert group in FEED_URLS, f"route {route} → unknown group {group}"


     def test_feed_urls_are_mta_endpoints():
         for url in FEED_URLS.values():
             assert url.startswith("https://api-endpoint.mta.info/"), url
     """}
  ]

  # ── Run ──────────────────────────────────────────────────────────

  def run(_args) do
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    image_id = build_image!(client, app)
    run_pytest!(client, app, image_id)
    dict = ensure_dict!(client, app)
    secret_id = ensure_secret!(client, app)

    log_header("PHASE 4 — deploy both Functions with one AppPublish")
    t = now()

    {:ok, [poller, web]} =
      Modal.Function.deploy_many(client, [
        {:function,
         app: app,
         name: @poller_name,
         image_id: image_id,
         module: "app.poller",
         callable: "poll",
         schedule: Modal.Period.seconds(15),
         retries: 3,
         timeout_secs: 30,
         min_containers: 1,
         secret_ids: [secret_id]},
        {:asgi,
         app: app,
         name: @web_name,
         image_id: image_id,
         module: "app.web",
         callable: "serve",
         target_concurrent_inputs: 64,
         max_concurrent_inputs: 128,
         timeout_secs: 60,
         idle_timeout_secs: 120,
         secret_ids: [secret_id]}
      ])

    log("  ✓ deployed poll + web in #{elapsed(t)} (single AppPublish)")
    log("    poller: #{inspect(poller)}")
    log("    web:    #{inspect(web)}")

    verify_endpoints!(web, dict)
    print_persistent_urls(web)
  end

  # ── Phase 1: image ───────────────────────────────────────────────

  defp build_image!(client, app) do
    log_header("PHASE 1 — image build (FastAPI + GTFS protobufs + poller + web)")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM python:3.12-slim",
          "RUN pip install --no-cache-dir uv",
          "WORKDIR /work"
        ] ++
          file_layers(@initial_files) ++
          [
            "RUN uv pip install --system --no-cache-dir -e '.[dev]'",
            "ENV PYTHONPATH=/work"
          ],
        app: app,
        on_log:
          Modal.Image.line_buffered(fn line ->
            IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, line]))
          end)
      )

    log("  ✓ image: #{image_id} [#{status}] (#{elapsed(t)})")
    image_id
  end

  defp file_layers(files) do
    Enum.map(files, fn {path, content} ->
      dir = Path.dirname(path)
      mkdir = if dir in [".", "/"], do: "", else: "mkdir -p #{dir} && "
      "RUN #{mkdir}cat > #{path} <<'PYEOF'\n#{content}\nPYEOF"
    end)
  end

  # ── Phase 2: pytest in transient sandbox ─────────────────────────

  defp run_pytest!(client, app, image_id) do
    log_header("PHASE 2 — pytest in a transient sandbox (gate before deploy)")

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        workdir: "/work"
      )

    try do
      proc = Modal.Sandbox.exec!(sandbox, ["pytest", "-q", "tests/"])
      result = Modal.ContainerProcess.await!(proc, timeout: 120_000)
      Modal.ContainerProcess.close(proc)

      result.stdout
      |> String.split("\n", trim: true)
      |> Enum.each(&IO.puts(:stderr, IO.ANSI.format([:faint, "  | ", :reset, &1])))

      if result.stderr != "" do
        result.stderr
        |> String.split("\n", trim: true)
        |> Enum.each(&IO.puts(:stderr, IO.ANSI.format([:red, "  | ", :reset, &1])))
      end

      assert!(result.code == 0, "pytest failed (exit #{result.code})")
      log("  ✓ pytest passed")
    after
      Modal.Sandbox.terminate(sandbox)
    end
  end

  # ── Phase 3: Modal.Dict (shared cache) ───────────────────────────

  defp ensure_dict!(client, app) do
    log_header("PHASE 3 — Modal.Dict shared cache")
    {:ok, dict} = Modal.Dict.get_or_create(client, @dict_name, app: app)
    log("  ✓ dict: #{dict.name} (#{dict.id})")
    dict
  end

  defp ensure_secret!(client, app) do
    # The poller and web tier both read the dict name from env.
    # Bundling it in a Secret lets us redeploy with a different
    # Dict (e.g. for blue/green) without rebuilding the image.
    {:ok, secret_id} =
      Modal.Secret.create(client,
        app: app,
        name: "nyct-config",
        env: %{"FEEDS_DICT_NAME" => @dict_name}
      )

    secret_id
  end

  # ── Phase 6: verify ──────────────────────────────────────────────

  defp verify_endpoints!(%Modal.Function{web_url: url}, _dict) do
    log_header("PHASE 6 — verify endpoints (waits for first poller fire)")

    # Root endpoint — confirms the web tier is up regardless of
    # poller state.
    log("  GET /")
    %{status: 200, body: root} = Req.get!(url, receive_timeout: 30_000)
    log("    routes: #{length(root["routes"])}, groups: #{length(root["groups"])}")

    # Health endpoint — should respond even before the poller has
    # populated anything (every field will just be nil).
    log("\n  GET /health")
    %{status: 200, body: health} = Req.get!(url <> "/health", receive_timeout: 30_000)
    log("    last_poll: #{inspect(health["last_poll"])}")

    # Now poll /trains/F until the Dict has data. This is the
    # warming → ready transition. Max ~30s wait (two 15s schedule
    # firings if the first one cold-starts).
    log("\n  GET /trains/F (waiting for first poll, up to 30s)…")
    wait_for_data!(url <> "/trains/F", deadline_ms: 35_000)

    # Re-check health now that the poller has fired.
    %{body: health2} = Req.get!(url <> "/health")
    feed_f = health2["feeds"]["bdfm"]
    log("\n  /health post-fire — bdfm feed age: #{feed_f["feed_age_secs"]}s")

    # Spot-check a couple other lines.
    for route <- ["L", "1", "A"] do
      case Req.get(url <> "/trains/#{route}", receive_timeout: 30_000) do
        {:ok, %{status: 200, body: b, headers: h}} ->
          stale = h["x-stale-seconds"] |> List.first()

          log(
            "  ✓ /trains/#{route} → #{b["trips_count"]} trips, " <>
              "feed age #{stale}s, group #{b["group"]}"
          )

        {:ok, %{status: s, body: b}} ->
          log("  · /trains/#{route} → #{s} #{inspect(b)}")

        {:error, e} ->
          log("  ! /trains/#{route} → #{inspect(e)}")
      end
    end

    log(
      "\n  ✓ End-to-end live: poller is filling Modal.Dict every 15s, web tier serves from cache."
    )
  end

  defp wait_for_data!(url, opts) do
    deadline = now() + Keyword.fetch!(opts, :deadline_ms)
    do_wait(url, deadline, _attempts = 0)
  end

  defp do_wait(url, deadline, attempts) do
    case Req.get(url, receive_timeout: 10_000, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        log("    ✓ ready after #{attempts} polls — #{body["trips_count"]} trips returned")

      {:ok, %{status: 503, body: %{"detail" => detail}}} ->
        if now() > deadline do
          raise "timed out waiting for first poll — last 503: #{inspect(detail)}"
        end

        log("    · 503 (#{detail}) — sleeping 2s, retrying")
        Process.sleep(2_000)
        do_wait(url, deadline, attempts + 1)

      other ->
        raise "unexpected /trains/F response: #{inspect(other)}"
    end
  end

  # ── Phase 7: persistent URLs ─────────────────────────────────────

  defp print_persistent_urls(%Modal.Function{web_url: base}) do
    log_header("LIVE")

    log("""
      Service is live. Hit it directly:

        curl #{base}/
        curl #{base}/health
        curl #{base}/trains/F
        curl #{base}/feeds/bdfm

      Both Functions stay deployed; re-running this script updates
      them in place. The Modal.Dict #{inspect(@dict_name)} persists
      across runs.
    """)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp assert!(true, _msg), do: :ok
  defp assert!(false, msg), do: raise("ASSERTION FAILED — #{msg}")
  defp log_header(msg), do: IO.puts(:stderr, "\n\e[1m── #{msg} ──────────────\e[0m")
  defp log(msg), do: IO.puts(:stderr, msg)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: fmt_ms(now() - t)
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"
end

FastapiNyct.run(System.argv())
