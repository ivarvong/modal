# Modal

[![CI](https://github.com/ivarvong/modal/actions/workflows/ci.yml/badge.svg)](https://github.com/ivarvong/modal/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/modal.svg)](https://hex.pm/packages/modal)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/modal)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Elixir client for [Modal](https://modal.com). Sandboxes, autoscaling Functions
+ Classes, Dict/Queue/Volume/CloudBucket primitives, cross-runtime Python
pickle interop — all from a supervised `GenServer`.

> **Status: preview (v0.1).** The public API may change before `1.0`. Pin
> the exact version you depend on while we iterate.

```elixir
# mix.exs
{:modal, "~> 0.1.0"}
```

## What it is

A supervised gRPC client covering most of Modal's production primitives.
`Modal.Client` is a `GenServer` that holds one connection and one set of
credentials. Start one per tenant in your supervision tree to isolate
credentials and lifecycles; RPCs dispatch through a per-client
`Task.Supervisor`, so a single client serves concurrent requests without
head-of-line blocking.

Transient gRPC failures (`UNAVAILABLE` / `DEADLINE_EXCEEDED` /
`RESOURCE_EXHAUSTED` / `ABORTED`, plus network errors) are retried client-
side with exponential backoff + jitter (up to 3 retries). Poll-style RPCs
where DEADLINE_EXCEEDED carries domain meaning (`SandboxWait`,
`FunctionGetOutputs`) opt out via `RPC.call_no_retry/4`.

## What it's for

Three loosely-grouped workloads:

- **Coding agents** — per-user shell sandboxes, sandboxed code interpreters
  for LLM products, ephemeral exec with snapshot/restore. `Modal.Sandbox`
  + `Modal.ContainerProcess` + `Modal.Filesystem`.
- **Production HTTP services** — autoscaling FastAPI / ASGI deploys with
  per-tier knobs (concurrency, warm pools, GPU, schedule). `Modal.Function`
  + `Modal.Cls` for stateful containers.
- **Distributed orchestration** — fan out work via `Modal.Queue`,
  share state via `Modal.Dict`, persist via `Modal.Volume` (or mount
  S3/GCS/R2 via `Modal.CloudBucket`). Cross-language with Python workers
  via byte-equivalent `Modal.Pickle`.

The library is BEAM-shaped where it matters:

- **`:terminate_on_caller_exit: true`** ties a sandbox's lifetime to the
  calling process. When a Phoenix request dies mid-flight or a
  `Task.async_stream` cancels the losers in a speculative race, a watchdog
  fires `SandboxTerminate` Modal-side. Other SDKs require manual
  `try/finally` bookkeeping; here, process supervision does it.
- **Per-tenant `Modal.Client` GenServer** with a per-client
  `Task.Supervisor` and `:max_concurrency` backpressure. One client per
  customer in your supervision tree; saturation surfaces as
  `{:error, %Modal.Error{kind: :overloaded}}`.
- **Telemetry on every RPC** (both control-plane and per-exec worker
  channel) with `:status` and `:error_kind` on the `:stop` events.
  Wire into Telemetry.Metrics for per-method error rates and latency
  histograms.

See [`scripts/`](https://github.com/ivarvong/modal/tree/main/scripts) for
end-to-end demos against live Modal — including
[`speculative_repair.exs`](https://github.com/ivarvong/modal/blob/main/scripts/speculative_repair.exs)
(parallel test-driven repair: Python repo, Elixir orchestrator, 3
candidate patches race, first one passing wins, losers brutal_killed
mid-flight, watchdogs clean up) and
[`llm_repair.exs`](https://github.com/ivarvong/modal/blob/main/scripts/llm_repair.exs)
(same loop but Claude generates the patches).

## Example: Claude Code in a sandbox

[`scripts/claude_code.exs`](https://github.com/ivarvong/modal/blob/main/scripts/claude_code.exs)
runs [Claude Code](https://claude.ai/code) headless inside a Modal sandbox
and returns a diff:

```bash
export MODAL_TOKEN_ID=...
export MODAL_TOKEN_SECRET=...
export ANTHROPIC_API_KEY=sk-ant-...

elixir scripts/claude_code.exs "fix the typo in the README and tighten the install steps"
```

The image (Claude CLI, Elixir, pre-cloned repo, warmed build cache) is
content-addressed by Modal — the second run boots from a cache hit. The
caller's `ANTHROPIC_API_KEY` is uploaded as an ephemeral Modal Secret at
exec time, never baked into the image.

Indicative wallclock on a warm cache, measured from a single developer
laptop (US East, residential gigabit) against `us-east` Modal. Numbers
move with region, network, image size, and Modal's load — treat as
ballpark, not SLA.

| Phase                                    | Cold cache | Warm cache |
| ---------------------------------------- | ---------- | ---------- |
| `Modal.Image.get_or_create`              | builds     | ~300ms     |
| Sandbox boot (image already pulled)      | ~5–10s     | ~2s        |
| Secret create + git pull                 | ~2s        | ~2s        |
| Claude (the actual work)                 | varies     | varies     |
| Diff back to caller                      | <1s        | <1s        |

## Quick start

```elixir
{:ok, client} =
  Modal.Client.start_link(
    token_id: System.fetch_env!("MODAL_TOKEN_ID"),
    token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")
  )

{:ok, app}               = Modal.App.lookup(client, "my-app")
{:ok, image_id, _status} = Modal.Image.get_or_create(client, ["FROM python:3.14-slim"], app: app)

# One-shot: create + exec + await + terminate, stdout + stderr captured.
{:ok, %{stdout: "4\n", stderr: "", code: 0}} =
  Modal.Sandbox.run(client,
    app: app,
    image_id: image_id,
    cmd: ["python3", "-c", "print(2+2)"]
  )

# Long-running sandbox you exec into multiple times.
sandbox =
  Modal.Sandbox.create!(client,
    app: app,
    image_id: image_id,
    cmd: ["sleep", "infinity"]
  )

# Stream stdout as it arrives.
{:ok, proc}   = Modal.Sandbox.exec(sandbox, ["echo", "hello from modal"])
{:ok, stream} = Modal.ContainerProcess.stream(proc)
Enum.each(stream, &IO.write/1)
{:ok, 0} = Modal.ContainerProcess.exit_code(proc)
Modal.ContainerProcess.close(proc)

# Or block and collect both stdout + stderr.
{:ok, proc} = Modal.Sandbox.exec(sandbox, ["python3", "-c", "print(2+2)"])
{:ok, %{stdout: "4\n", stderr: "", code: 0}} = Modal.ContainerProcess.await(proc)
Modal.ContainerProcess.close(proc)

# File I/O against a running sandbox.
:ok            = Modal.Filesystem.write_file(sandbox, "/tmp/test.txt", "hello")
{:ok, "hello"} = Modal.Filesystem.read_file(sandbox, "/tmp/test.txt")
{:ok, files}   = Modal.Filesystem.ls(sandbox, "/tmp")

# Snapshot the filesystem as a reusable image, then boot a new sandbox
# from it instantly.
{:ok, snap_image_id} = Modal.Sandbox.snapshot_filesystem(sandbox)
Modal.Sandbox.terminate(sandbox)

sandbox2 =
  Modal.Sandbox.create!(client,
    app: app,
    image_id: snap_image_id,
    cmd: ["sleep", "infinity"]
  )
```

## Beyond sandboxes

For long-running services or distributed work, reach past `Sandbox`.

### Autoscaling HTTP service (FastAPI / ASGI)

```elixir
{:ok, web} =
  Modal.Function.deploy_asgi(client,
    app: app,
    name: "api",
    image_id: image_id,
    module: "entry",
    callable: "serve",
    target_concurrent_inputs: 64,    # pack many requests / container
    min_containers: 1,               # avoid cold-start on first request
    timeout_secs: 60
  )

# web.web_url → "https://<workspace>--api.modal.run"
```

### Scheduled poller (every 15s)

```elixir
{:ok, poller} =
  Modal.Function.deploy_function(client,
    app: app,
    name: "poll",
    image_id: image_id,
    module: "entry",
    callable: "poll",
    schedule: Modal.Period.seconds(15),
    retries: 3,
    min_containers: 1                # keep warm so the schedule fires on time
  )
```

### ML inference with persistent state (GPU)

```elixir
{:ok, model} =
  Modal.Cls.deploy(client,
    app: app,
    image_id: image_id,
    module: "entry",
    callable: "Llama",               # Python class with @modal.enter
    method_names: ["predict"],
    gpu: "A100",                     # or "T4" / "H100" / "L40S" / ...
    min_containers: 1                # load the model ONCE, amortize across calls
  )

{:ok, text} = Modal.Cls.invoke(client, model, "predict", ["prompt"])
```

### Call deployed functions from Elixir (no HTTP)

```elixir
{:ok, fn_struct} = Modal.Function.get(client, app, "compute")

# Sync — pickle args + kwargs, get pickle result back
{:ok, 49} = Modal.Function.invoke(client, fn_struct, [7])

# Async — spawn N, await all
calls =
  for n <- 1..8 do
    {:ok, call} = Modal.Function.spawn(client, fn_struct, [n])
    call
  end

results = Enum.map(calls, &Modal.Function.await!/1)

# Streaming (generator function)
Modal.Function.invoke_stream(client, gen_fn, ["prompt"]) |> Enum.each(&IO.write/1)
```

### Distributed coordination (Dict + Queue)

```elixir
{:ok, q} = Modal.Queue.get_or_create(client, "jobs", app: app)
{:ok, d} = Modal.Dict.get_or_create(client, "results", app: app)

# Producer
Modal.Queue.put_many(q, [%{job: 1}, %{job: 2}, %{job: 3}])

# Consumer (server-side atomic pop — no application-level locking)
{:ok, job} = Modal.Queue.get(q, timeout_secs: 5.0)
Modal.Dict.put(d, "result:#{job["job"]}", compute(job))
```

### Cross-language with a Python worker

```elixir
# Elixir writes pickle bytes Modal's Python SDK reads natively —
# no monkey-patching, no json.loads.
Modal.Queue.put(q, %{"prompt" => "hello"}, encoding: :pickle)
Modal.Dict.put(d, "config", %{"max_tokens" => 1000}, encoding: :pickle)
```

```python
# Python side, no special imports:
import modal
q = modal.Queue.from_name("jobs")
job = q.get()        # → {'prompt': 'hello'}
```

### Sandbox network restrictions

```elixir
# Allowlist GitHub's API CIDRs (auto-fetched from api.github.com/meta).
gh = Modal.Sandbox.github_cidrs!()

Modal.Sandbox.create!(client,
  app: app,
  image_id: image_id,
  cmd: ["python", "agent.py"],
  network_access: {:allowlist, gh}   # also :open / :blocked
)

# Or: outbound static IP (when *target* allowlists you, e.g. customer DB).
{:ok, proxy} = Modal.Proxy.get(client, "customer-db")
Modal.Sandbox.create!(client, ..., proxy_id: proxy.id)
```

### Choosing the right primitive

| Need                                                  | Use                       |
| ----------------------------------------------------- | ------------------------- |
| One-shot exec (`python -c ...`, run a script)         | `Modal.Sandbox.run/2`     |
| Persistent shell, multiple execs, snapshot/restore    | `Modal.Sandbox`           |
| Stateless autoscaling HTTP service                    | `Modal.Function.deploy_asgi/2` |
| Stateful service (load model once, serve N requests)  | `Modal.Cls`               |
| Background job on a schedule                          | `Modal.Function.deploy_function/2` + `schedule:` |
| Call a deployed function from Elixir                  | `Modal.Function.invoke/5` / `spawn/4` |
| Stream incremental results (LLM tokens)               | `Modal.Function.invoke_stream/5` (with `generator: true` deploy) |
| Shared KV state across containers                     | `Modal.Dict`              |
| Work queue with atomic pop                            | `Modal.Queue`             |
| Persistent file storage you control                   | `Modal.Volume`            |
| Mount existing S3 / R2 / GCS bucket                   | `Modal.CloudBucket`       |
| Egress allowlist (you restrict where you can reach)   | `Sandbox` `:network_access` |
| Static outbound IP (target allowlists you)            | `Modal.Proxy`             |

## Shipping a service

See [`guides/ship_checklist.md`](https://github.com/ivarvong/modal/blob/main/guides/ship_checklist.md)
for a practical operational checklist: auth, error discrimination,
telemetry wiring, cost math, the `AppPublish`-replaces-registry gotcha,
teardown hygiene, and the primitive-selection cheat sheet. Distilled
from lessons of building the demos in this repo.

## Supervision

`Modal.Client` is a `GenServer`. In production, supervise it:

```elixir
children = [
  {Modal.Client,
   name: MyApp.ModalClient,
   token_id: System.fetch_env!("MODAL_TOKEN_ID"),
   token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Multi-tenant: start one named `Modal.Client` per tenant, each with that
tenant's credentials. RPCs dispatch through a per-client `Task.Supervisor`,
so a single client serves many concurrent requests without head-of-line
blocking. An optional `max_concurrency:` cap rejects new RPCs with
`{:error, :overloaded}` when saturated.

## Telemetry

See `Modal.Telemetry` for the full event surface and helper attach API.
Short version: two event families, same shape.

| Event prefix              | What fires it                                            |
| ------------------------- | -------------------------------------------------------- |
| `[:modal, :rpc, …]`       | Control-plane RPCs (every method in `Modal.RPC`'s dispatch table — App, Sandbox, Image, Function, Cls, Dict, Queue, Volume, Secret, Proxy, …) |
| `[:modal, :worker_rpc, …]`| Per-exec RPCs (task_exec_start / stdio_read / wait / stdin) |

Each family emits `:start`, `:stop`, `:exception`. Start metadata:
`%{method: atom, kind: :unary | :stream | :stream_reduce, attempt: 0..3}`
for `:rpc`, `%{method: atom}` for `:worker_rpc`. Stop metadata adds
`:status` (`:ok | :error`) and — when the error carries them —
`:error_kind` (`:grpc | :network | :timeout | …`) and `:code`
(numeric, e.g. a gRPC status code). `:attempt` is also threaded into
the stop event so dashboards can see retry storms as discrete events.

```elixir
:telemetry.attach_many("my-modal-metrics",
  [
    [:modal, :rpc, :stop],
    [:modal, :worker_rpc, :stop]
  ],
  fn _event, %{duration: ns}, meta, _config ->
    :telemetry.execute([:my_app, :modal_call],
      %{duration_ms: System.convert_time_unit(ns, :native, :millisecond)},
      meta
    )
  end,
  nil
)
```

For an end-to-end example of per-method counters under fan-out concurrency,
see [`scripts/parallel_pi.exs`](https://github.com/ivarvong/modal/blob/main/scripts/parallel_pi.exs).

## Public modules

| Module                   | What it does                                                          |
| ------------------------ | --------------------------------------------------------------------- |
| `Modal.Client`           | Supervised gRPC connection to `api.modal.com` with per-tenant isolation |
| `Modal.App`              | App lookup / publish; `:function_ids` + `:class_ids` registry         |
| `Modal.Image`            | Container image builds, `:on_log` callback, `line_buffered/1` helper  |
| `Modal.Sandbox`          | Lifecycle, exec, `run/2`, snapshots, `:network_access` egress control |
| `Modal.ContainerProcess` | A running command — `stream/2`, `await/2` w/ callbacks                |
| `Modal.Filesystem`       | `read_file/2`, `write_file/3`, `ls/2`, `mkdir/3`, `rm/3`              |
| `Modal.Function`         | Deploy ASGI / web-server / non-webhook functions; `invoke`/`spawn`/`await`/`stream` |
| `Modal.FunctionCall`     | Handle for an in-flight invocation, returned by `spawn/4`             |
| `Modal.Cls`              | Class-based deploys with `@enter`/`@exit` lifecycle — ML workloads    |
| `Modal.Period`           | Ergonomic schedule helper — `seconds/1`, `minutes/1`, `compose/1`     |
| `Modal.Cron`             | `utc/1`, `in_timezone/2` for calendar-aligned schedules               |
| `Modal.Dict`             | Distributed KV store; JSON / `:raw` / `:pickle` value encodings       |
| `Modal.Queue`            | Distributed work queue with server-side atomic pop                    |
| `Modal.Pickle`           | Python pickle codec, **byte-equivalent** to `pickle.dumps(v, protocol=4)` |
| `Modal.Secret`           | Environment-variable bags injected into sandboxes / functions         |
| `Modal.Volume`           | Persistent volume — `put_file/5`, `get_file/4`, `list_files/3`, `reload/2`, `commit/2` |
| `Modal.CloudBucket`      | Mount S3 / R2 / GCS buckets as filesystem paths inside containers     |
| `Modal.Proxy`            | Outbound static IP — `get/3` lookup (proxies are dashboard-provisioned) |
| `Modal.Tunnel`           | TLS / TCP ingress URLs for sandbox-exposed ports                       |
| `Modal.RPC`              | Documented escape hatch for unwrapped RPCs (SemVer-protected)         |
| `Modal.Error`            | Structured errors with `:kind`, `:code`, `:message`, `:metadata`      |

## Examples

Standalone `.exs` scripts under
[`scripts/`](https://github.com/ivarvong/modal/tree/main/scripts),
runnable directly
via `elixir scripts/<name>.exs` (each one uses `Mix.install/2` so no
project setup is needed — copy + paste to share). Live dogfood demos
against real Modal.

| Script                       | What it shows                                                  |
| ---------------------------- | -------------------------------------------------------------- |
| `smoketest.exs`              | The smallest possible end-to-end: boot, exec, print, terminate |
| `cloudflare_roundtrip.exs`   | `Sandbox.run!/2` one-shot: clone repo, sum data, return        |
| `calc.exs`                   | Warm Python sandbox by name — first call is boot, rest sub-100ms |
| `parallel_pi.exs`            | 8-way fan-out via `Task.async_stream`, telemetry under load    |
| `volume_roundtrip.exs`       | `Modal.Volume` + Filesystem + caller-exit watchdog live        |
| `seed_and_fan_out.exs`       | `Volume.put_file/5` seed-from-orchestrator + N read-only consumers |
| `snapshot_demo.exs`          | Clone, install, snapshot, restore — full coding-agent baseline |
| `coding_session.exs`         | Multi-turn coding session in one long-lived sandbox            |
| `speculative_repair.exs`     | Parallel test-driven repair: 3 candidates race, winner ships   |
| `llm_repair.exs`             | Same loop, but Claude generates the candidate patches          |
| `eval.exs`                   | Two-phase: cache a per-repo test image, then `git pull` + run  |
| `claude_code.exs`            | Claude Code CLI on a ticket, sandboxed, ephemeral secret       |
| `fastapi_endpoint.exs`       | Boot a FastAPI service in a sandbox, hit it over HTTPS         |
| `screenshot.exs`             | Headless Chromium via Playwright                               |
| `video_clip.exs`             | `ffmpeg` clip + resize to 720p                                 |
| `uv_roundtrip.exs`           | Full circle: Elixir scaffolds a uv project via exgit → CF Artifacts → Modal+Claude adds a feature + pushes back → Elixir clones the post-Claude repo |
| `fastapi_nyct.exs`           | Real NYC Transit GTFS-Realtime service on Modal in the staff+ shape: a scheduled poller `Modal.Function.deploy_function/2` (15s `:period`, `retries: 3`, `min_containers: 1`) writes feed bytes + ETags to a shared `Modal.Dict`; an autoscaling web tier `Modal.Function.deploy_asgi/2` (`target_concurrent_inputs: 64`) reads from the Dict and never touches MTA directly. Conditional GET, three-state freshness, pytest gate before deploy. |
| `distributed_pi.exs`         | Map-reduce Monte Carlo π entirely orchestrated from Elixir using `Modal.Queue` + `Modal.Dict` as the shared coordination layer — producer pushes 16 jobs, 8 parallel Elixir consumers atomic-pop and write results, aggregator reads from Dict. Same problem as `parallel_pi.exs`, different orchestration primitive (shared state vs. throwaway sandboxes). |
| `pickle_stress.exs`          | Cross-runtime stress: Elixir writes 100 random pickle-encoded payloads to `Modal.Queue` + `Modal.Dict`; Python reads them via the native `modal.Queue.get()` / `Dict.get(key)` (no monkey-patch); a Python-Elixir mutual-modify cycle validates Pickle round-trip in both directions. The load-bearing demo for `Modal.Pickle`'s byte-equivalence to `pickle.dumps(v, protocol=4)`. |
| `manhattanhenge.exs`         | Reproduce Manhattanhenge end-to-end, no human in the loop, in three steps: Elixir boots a sandbox and runs the **Claude Code CLI live** to write a DE440/Skyfield calc + FastAPI app (uv/Python) from a short brief; reads the app back out, bakes it into an Image, and `Modal.Function.deploy_asgi/2`'s it to a persistent endpoint; then curl-verifies the live URL reports the published 2026 dates (May 28 @ 20:13 EDT, May 29 @ 20:12 EDT) at the correct **apparent** (refraction-corrected) altitude. The careful bit: refraction (~0.5°) exceeds the Sun's radius (0.27°), so on May 28 the geometric center is *below* the horizon while the apparent disk is visibly up — geometric altitude would be wrong. |

## Testing your own code

The library ships with behaviours so it can be mocked via [Mox](https://hex.pm/packages/mox):

- `Modal.Client.Behaviour` — the RPC surface
- `Modal.ModalStub.Behaviour` — the gRPC stub
- `Modal.TaskCommandRouter.Behaviour` — the worker-side TCR stub

Point `:modal, :client_impl` at your mock in `config/test.exs` and unit-test
without ever opening a socket. The
[`test/`](https://github.com/ivarvong/modal/tree/main/test) tree is all-Mox
by default (no socket), plus property-based tests (Pickle round-trip +
byte-equality vs CPython, JWT parsing, filesystem option coercion, Sandbox
option building, integer bignum overflow, repeated-string memoization). A
separate tier of **live contract tests** (`@moduletag :contract`,
`test/contract/`) drives real RPCs against Modal to validate the mocks
against the wire.

Run contract tests with:

```sh
MODAL_TOKEN_ID=... MODAL_TOKEN_SECRET=... mix modal.contract
```

The task refuses to run without credentials — silent no-ops would be
indistinguishable from "tests didn't verify anything." Tests cover
**App, Image, Sandbox, Dict, Queue, Volume, Function** (deploy +
invoke / spawn / await + generator stream), **Cls** (deploy + method
dispatch + lifecycle), **Pickle** cross-runtime via CPython,
**Proxy**, **network_access** (open / blocked / CIDR allowlist with
real `curl`-in-sandbox behavior verification) — ~3:30 end-to-end
against a warm account.

## Roadmap

Tracked but not yet landed:

- `Modal.Filesystem.ls/2` returning entry metadata (size, type) instead of
  bare filenames — matches the Python SDK's shape. (Today returns
  `[String.t()]`; the wire response already carries the metadata, we just
  flatten it.)
- Per-request deadline propagation through retries and reconnects. The
  current retry loop gives each attempt its own timeout but doesn't
  enforce an aggregate deadline budget across attempts.
- `Modal.NetworkFileSystem` — legacy NFS-shaped shared storage. Mostly
  superseded by `Modal.Volume`; not exposed yet.
- `Modal.Function.spawn_map` — bulk fan-out via one `FunctionMap` with
  many inputs (not yet implemented). `Task.async_stream` + `Modal.Function.spawn/4`
  works today; spawn_map would batch the wire call.
- `Modal.Cls` warm-restore / GPU snapshots — newer Modal Python features
  for fast container resume.
- Blob-backed Function results. Modal stores large outputs (above a size
  threshold) in blob storage and returns a `blob_id` instead of inline
  bytes; fetching them needs a separate download path that isn't
  implemented yet. `Modal.Function.await/2` surfaces such a result as a
  clear `:function_failed` error rather than hanging or returning garbage.

Open an issue if any of these would unblock you, or to discuss other gaps.

## Audit trail

The verifiable claims in this README are pinned against actual test runs
(test *counts* are deliberately left out — they're noisy under parametrized
tests and drift; `Modal.ReadmeClaimsTest` audits the structural claims):

- "Modal.Pickle is byte-equivalent to `pickle.dumps(v, protocol=4)`" —
  `test/modal/properties/pickle_property_test.exs` `BYTE EQUALITY`
  property runs `pickle.dumps` via `python3` and compares bytes
- "retries 3 times on transient gRPC failures" — `test/modal/rpc_test.exs`
  `retry-with-jitter` describe (counts attempts via `:counters`)
- ":overloaded backpressure" — `test/modal/concurrent_client_test.exs`
  `max_concurrency`
- "credential isolation across clients" —
  `test/modal/concurrent_client_test.exs` `credential isolation`
- "terminate_on_caller_exit watchdog" — `test/modal/sandbox_test.exs`
  `terminate_on_caller_exit:` describe
- Every primitive's deploy + happy-path + error-path is covered by a
  per-module unit test (`test/modal/<module>_test.exs`) plus a live
  contract test (`test/contract/<module>_contract_test.exs`) for the
  ones whose wire shape Modal could drift.

## Attribution

Proto definitions are generated from
[modal-labs/modal-client](https://github.com/modal-labs/modal-client)
(Apache 2.0). See [NOTICE](NOTICE).

## License

[MIT](LICENSE).
