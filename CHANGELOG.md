# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `:volumes` option on `Modal.Function.deploy_asgi/2`, `deploy_web_server/2`,
  `deploy_function/2`, and `deploy_many/2` — mount `Modal.Volume`s into a
  deployed function's containers, same shape as `Modal.Sandbox.create/2`'s
  `:volumes` (`%Modal.Volume{}` structs or `%{id:, path:, read_only:}` maps).
  Lets a deployed app serve code/data straight from a Volume.
- `Modal.App.list/2` and `Modal.App.stop/2` (+ `stop!/2`) — list apps in an
  environment (`{:ok, [map]}` with `:app_id`, `:description`, `:state`,
  `:created_at`, `:stopped_at`, `:n_running_tasks`) and stop a deployed app
  by `%Modal.App{}` or id. Adds `:AppList` / `:AppStop` to `Modal.RPC`
  `@methods`.
- `Modal.Volume.list/2` — list named volumes in an environment
  (`{:ok, [map]}` with `:volume_id`, `:name`, `:created_at`), newest first.
  Server pagination is walked internally; cap with `:max_objects` or bound
  with `:created_before`. Adds `:VolumeList` to `Modal.RPC` `@methods`.
  Pairs with `delete/2` to prune volumes by name prefix.
- `Modal.Error` kind `:output_expired` — a function call's output is gone
  (expired / already consumed / input lost), distinct from `:timeout` (the
  call is still running).

### Fixed

- `Modal.Sandbox` volume mounts now set `allow_background_commits: true`, so
  writes to a mounted `Modal.Volume` actually persist (the worker commits
  periodically and on exit). Previously writes were lost unless committed
  from inside the container — which a sandbox can't do, since it has no
  Modal client credentials. Matches the Python SDK's sandbox volume mounts.
- `Modal.ContainerProcess.await/2` (and `Modal.Sandbox.exec_streaming/3`)
  no longer fail on execs that run longer than the per-attempt wait
  deadline (~60s). `TaskExecWait` blocks until the exec exits, so a long
  process tripped the deadline and surfaced as a non-retried gRPC
  CANCELLED; the wait now treats its own deadline expiry as "still
  running, poll again", bounded by the existing attempt cap, with the
  caller's overall `:timeout` still enforced by `await/2`.
- `Modal.Sandbox.run/2` now arms the caller-exit watchdog
  (`terminate_on_caller_exit: :silent` by default), so a brutal
  `Process.exit(caller, :kill)` mid-run — which skips the `try/after`
  cleanup — no longer leaks the sandbox. Pass
  `terminate_on_caller_exit: false` to opt out.
- Generator streams (`Modal.Function.stream/2` / `invoke_stream/5`) now
  raise `%Modal.Error{kind: :function_failed}` when the worker yields a
  blob-backed chunk (a large value stored out-of-band), instead of
  silently dropping the value and returning a gappy result. Blob-fetch
  is tracked on the roadmap; until then the failure is explicit and
  consistent with `await/2`.
- Generator streams now surface a *failed* generator (one that raises, or
  whose module fails to import on the worker) as a raised
  `%Modal.Error{kind: :function_failed}` with the worker traceback, instead
  of returning a silent empty/partial list. `stream/2` now polls the
  terminal `FunctionGetOutputs` result when the data-out stream ends without
  a `GENERATOR_DONE` terminator (matching CPython's `run_generator`).
- `Modal.Function.await/2` now distinguishes a call whose output has expired
  (or whose input was lost to worker preemption with no retry) from a
  genuine timeout: when the server reports no result **and** no unfinished
  inputs, it returns `%Modal.Error{kind: :output_expired}` immediately at the
  deadline instead of masking it as a generic `:timeout`. Mirrors CPython's
  `OutputExpiredError`.

### Changed

- Caller-exit monitor processes (`Modal.Sandbox`, `Modal.ContainerProcess`)
  now run under a supervised `Task.Supervisor` (`Modal.WatchdogSupervisor`)
  instead of a bare `spawn/1`, so a crash in a monitor is reported rather
  than silently dropping the cleanup it was responsible for.

## [0.1.0]

Initial preview release. Elixir client covering most of Modal's
production primitives.

### Core surface

- **`Modal.Client`** — supervised gRPC `GenServer` holding one
  connection + credentials. One client per tenant in your
  supervision tree; per-client `Task.Supervisor` handles concurrent
  RPCs without head-of-line blocking. Optional `:max_concurrency`
  cap surfaces `{:error, %Modal.Error{kind: :overloaded}}` when
  saturated.

- **Structured errors everywhere.** `%Modal.Error{kind:, code:,
  message:, metadata:}` for every failure mode. `Modal.Error.transient?/1`
  classifies retryable conditions; client retries up to 3 times
  with exponential backoff + jitter on transient gRPC codes
  (`UNAVAILABLE`, `DEADLINE_EXCEEDED`, `RESOURCE_EXHAUSTED`,
  `ABORTED`) and `:network` errors. Poll-style RPCs where
  `DEADLINE_EXCEEDED` carries domain meaning opt out via
  `Modal.RPC.call_no_retry/4`.

- **Telemetry on every RPC** — `[:modal, :rpc, …]` for control-plane
  + `[:modal, :worker_rpc, …]` for per-exec channel. Each emits
  `:start` / `:stop` / `:exception`. Stop metadata carries
  `:status`, `:error_kind`, `:code`, and `:attempt` (so retry
  storms surface as discrete events, not one mysteriously-slow call).

### Primitives

- **`Modal.Sandbox`** — full lifecycle (`create/2`, `run/2`,
  `run!/2`, `terminate/1`, `with_sandbox/3`), exec via
  `Modal.ContainerProcess` (`stream/2`, `await/2` with
  `:on_stdout`/`:on_stderr` callbacks, `line_buffered/1` helper),
  filesystem I/O (`Modal.Filesystem.read_file/2` /
  `write_file/3` / `ls/2` / `mkdir/3` / `rm/3`), snapshot/restore.
  `:terminate_on_caller_exit` watchdog ties sandbox lifetime to
  the calling Elixir process — closes the silent-money-leak
  footgun when a Phoenix request handler dies mid-flight.

- **`Modal.Function`** — deploy ASGI (`deploy_asgi/2`), web-server
  (`deploy_web_server/2`), or non-webhook (`deploy_function/2`)
  callables. Multi-function apps via `deploy_many/2` (single
  `AppPublish` covering N functions). Per-tier knobs: `:schedule`
  (with `Modal.Period`/`Modal.Cron` helpers), `:retries`,
  `:target_concurrent_inputs` + `:max_concurrent_inputs`,
  `:min_containers`, `:gpu` + `:gpu_count`, `:memory_mb`,
  `:cpu_millis`, `:disk_mb`, `:i6pn`. Call from Elixir via
  `invoke/5` / `spawn/4` / `await/2` / `invoke_stream/5` (for
  generator functions). Args/kwargs round-trip through pickle to
  match Modal's wire format; atom kwarg keys auto-stringify.

- **`Modal.Cls`** — class-based deploys with `@modal.enter` /
  `@modal.exit` lifecycle hooks. The canonical primitive for ML
  workloads where boot cost is high (load model, open pool, warm
  JIT) and you want it amortized across many method invocations.
  Six load-bearing CPython wire-shape conventions are pinned —
  `<Callable>.*` wildcard naming, `PICKLE` class-parameter format,
  five-field `MethodDefinition` populated even when empty,
  `Resources` + `AutoscalerSettings` + `object_dependencies`
  always present, `ClassCreate` with `only_class_function: true`
  only, two-key `AppPublish` (function_ids by `<Callable>.*`,
  class_ids by `<Callable>`).

- **`Modal.Dict`** + **`Modal.Queue`** — distributed coordination
  primitives. Server-side atomic pop on `Queue.get/2`; no
  application-level locking needed for fan-out work. JSON value
  encoding by default with `encoding: :raw` and `encoding: :pickle`
  opt-outs.

- **`Modal.Pickle`** — Python pickle codec emitting bytes
  **byte-equivalent** to CPython's `pickle.dumps(value, protocol=4)`.
  Lets Elixir write to Modal Dict/Queue and a Python worker read
  natively via `modal.Queue.get()` / `dict.get(key)` — no
  monkey-patching, no `json.loads`. Byte-equality matters for Dict
  keys: Modal's server compares keys as raw bytes, so a
  semantically-equal but byte-different pickle silently misses.
  Supports nil / bool / int (any width) / float / binary (str or
  bytes) / list / tuple / map. Refuses pickle's `REDUCE` / `OBJ` /
  `BUILD` opcodes on decode (the headline pickle security hole;
  naturally unavailable from BEAM anyway).

- **`Modal.Volume`** — full lifecycle. `put_file/5` lands files
  via the content-addressed block store directly from the
  orchestrator (no sandbox boot needed). `get_file/4`,
  `list_files/3` (v2 streaming), `reload/2`, `commit/2`.

- **`Modal.CloudBucket`** — mount S3 / R2 / GCS buckets as
  filesystem paths inside sandboxes. The most-asked-for feature
  for data-heavy ML workloads — no upload step, no Volume sync.

- **`Modal.Secret`** — environment-variable bags injected into
  sandboxes and functions.

- **`Modal.Proxy`** — outbound static IP lookup for when a target
  service allowlists by IP. Proxies are dashboard-provisioned;
  programmatic creation isn't supported by Modal's API.

- **`Modal.Tunnel`** — TLS/TCP ingress URLs for sandbox-exposed
  ports.

- **`Modal.Sandbox` `:network_access`** — first-class egress
  control via Modal's `NetworkAccess` proto:
  `:open` / `:blocked` / `{:allowlist, [cidr, ...]}`. Pairs with
  `Modal.Sandbox.github_cidrs!/1` (live-fetches from
  `api.github.com/meta`, IPv4-only by default since Modal's
  allowlist rejects IPv6).

- **`Modal.RPC`** — documented escape hatch for unwrapped RPCs.
  SemVer-protected dispatch table; full telemetry coverage.

### Testing

- 551 unit + property-based tests covering every primitive's
  happy path + validation + RPC propagation + transient-failure
  retry behavior + cross-runtime Pickle round-trip.
- 36 contract tests (`@moduletag :contract`, `test/contract/`)
  that drive real RPCs against Modal to validate the mocks against
  the wire. Run via `mix modal.contract` (refuses to start without
  `MODAL_TOKEN_ID` + `MODAL_TOKEN_SECRET`). ~3:30 end-to-end
  against a warm account.
- CI runs the contract suite against live Modal on every push to
  `main`, including a Python venv for the cross-runtime Pickle
  test.
- README has a self-checking test (`Modal.ReadmeClaimsTest`) that
  fails if the public-modules table, contract coverage list, or
  example-scripts table drifts from disk.

[0.1.0]: https://github.com/ivarvong/modal/releases/tag/v0.1.0
