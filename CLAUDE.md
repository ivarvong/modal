# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo identity

Elixir client for Modal (modal.com) — sandboxes, autoscaling Functions
+ Classes, Dict / Queue / Volume / Secret / Tunnel / Proxy /
CloudBucket, with cross-runtime Python pickle interop. Distributed on
Hex as `modal`. Public-facing — every change ships through CI on every
push.

Read `README.md` for the user-facing pitch and `CONTRIBUTING.md` for
conventions (option validation, error returns, bang variants, telemetry,
demo scripts). Read `guides/ship_checklist.md` for the operational
checklist this library was built around — it's the "why" behind a lot
of the API shape.

## Git workflow: PR-only

All changes land via pull request. Never `git push` directly to `main`,
and **never** force-push to `main`, even if explicitly authorized in
conversation — the answer is to open a PR. CI on `main` is the source
of truth for the published package; push-to-main breaks the property
that every commit on `main` shipped through a green PR.

After `gh pr create`, always run `open <pr-url>` so the user can review
in their browser — don't make them copy the URL out of terminal output.

Workflow:

1. `git switch -c <topic>` off `main`.
2. Commit on the branch (one logical change per PR — refactor + feature
   is two PRs).
3. `git push -u origin <topic>`.
4. `gh pr create` — then `open <url>`.
5. CI runs the matrix + live contract suite (PRs from this repo, not
   forks, hit live Modal).
6. `gh pr merge` once green.

## Toolchain

`.tool-versions` pins **Elixir 1.19.5 / OTP 28.4**. CI matrix also
runs **1.18.4 / OTP 27.3** for compat; new code must work on both. Keep
local in sync via asdf or `mise` so formatter / dialyzer output matches
CI (different patch versions of Elixir reformat differently — bumping
local without matching what CI runs will produce CI-only format diffs).

## Commands

```sh
mix test                          # 489 tests + 26 properties, all-Mox, ~6s
mix test test/path/to_test.exs    # one file
mix test test/path/to_test.exs:42 # one test by line
mix test --include integration    # adds @moduletag :integration (live Modal)
mix test --include contract       # adds @moduletag :contract — but use mix modal.contract instead
mix modal.contract                # the proper way: refuses to run without
                                  # MODAL_TOKEN_ID / MODAL_TOKEN_SECRET, ~3:30 live

mix format                        # auto-fix
mix format --check-formatted      # CI gate; must pass
mix credo --strict                # CI gate; must pass
MIX_ENV=dev mix docs              # ex_doc is dev-only; must emit zero warnings
mix dialyzer                      # CI gate; first run builds PLT (~2 min)
```

The contract task `mix modal.contract` deliberately refuses to start
without credentials — a silent no-op would be indistinguishable from
"tests didn't verify anything." Don't paper over that by hardcoding
fallback credentials.

## Architecture

### The `Modal.Client` GenServer is the unit of isolation

One `GenServer` holds one gRPC channel + one set of credentials. In
production it's supervised; in tests it's bypassed entirely via Mox.
Per-tenant SaaS pattern: one named `Modal.Client` per customer in the
supervision tree. Per-client `Task.Supervisor` dispatches RPCs
concurrently so one client serves many requests without head-of-line
blocking; `:max_concurrency` backpressures with
`{:error, %Modal.Error{kind: :overloaded}}`.

The library has **three behaviour seams** (`lib/modal/*/behaviour.ex`,
defined as mocks in `test/test_helper.exs`):

- `Modal.Client.Behaviour` — the RPC dispatch surface (`rpc/4`,
  `stream/4`). This is where unit tests hook in via
  `config :modal, :client_impl, Modal.Client.Mock`.
- `Modal.ModalStub.Behaviour` — the raw gRPC stub. Used by stubs that
  need to look at gRPC-level metadata (auth headers, etc).
- `Modal.TaskCommandRouter.Behaviour` — the worker-channel (per-exec
  TCR endpoint, separate from the control plane).

When adding a new public Modal API call, route through
`Modal.RPC.call/4` (or `stream/4` / `stream_reduce/6`) — never reach
straight to `Modal.Client.rpc/4`. Reasons:

1. The PascalCase atom in `@methods` (lib/modal/rpc.ex) gives
   compile-time-shaped errors for typos (FunctionClauseError, not a
   runtime stub crash).
2. You get the `[:modal, :rpc, :*]` telemetry span for free.
3. Transient gRPC codes (UNAVAILABLE / DEADLINE_EXCEEDED /
   RESOURCE_EXHAUSTED / ABORTED + network errors) get retried with
   exponential backoff + jitter via `Modal.Backoff` (up to 3 retries).

Add the PascalCase atom to `@methods` in `lib/modal/rpc.ex` for any new
RPC. A new entry is a **minor** version bump (additive); renaming or
removing one is **major**.

### `call/4` vs `call_no_retry/4` — load-bearing distinction

`call_no_retry/4` exists because some RPCs use transient gRPC codes
**as domain signals** — `SandboxWait`, `FunctionGetOutputs`,
`SandboxWaitUntilReady` use DEADLINE_EXCEEDED to mean "still running."
Retrying them silently inflates apparent latency and breaks poll
semantics. If you're wiring a poll-style RPC, use `call_no_retry/4`.
Same telemetry; the difference is exactly one attempt.

### Generated proto code

`lib/modal/proto/modal_proto/api.pb.ex` and
`lib/modal/proto/modal_proto/task_command_router.pb.ex` are generated
from `modal-labs/modal-client`. Treat them as read-only — regenerate
rather than edit. The `modal-client/` directory at repo root is the
upstream checkout used for codegen.

### Tests live in three tiers

- **Unit (`test/modal/*_test.exs`)** — pure Mox, never opens a socket.
  Runs by default in `mix test`. Use `Modal.Client.Mock` via
  `Mox.expect/3` (strict — every expectation must be met) or
  `Mox.stub/3` (loose — for transient-error propagation tests where the
  retry would inflate the expect count).
- **Contract (`test/contract/*_contract_test.exs`,
  `@moduletag :contract`)** — drives real RPCs against Modal and
  asserts the wire-format mocks match what Modal actually returns.
  Catches mock drift before it reaches users. Run with
  `mix modal.contract` (gated on credentials).
- **Integration (`@moduletag :integration`)** — heavier live runs;
  excluded by default.

Property-based tests live alongside in `test/modal/properties/`. The
big load-bearing one is `pickle_property_test.exs`'s `BYTE EQUALITY`
property — shells out to `python3 -c 'pickle.dumps(...)'` and asserts
byte-identical output. That property is what lets the library claim
"byte-equivalent to `pickle.dumps(v, protocol=4)`."

The `Modal.ReadmeClaimsTest` (`test/modal/readme_claims_test.exs`) is
a structural drift detector: every module in the README's Public
modules table must exist, every contract test file mentioned must be
present, every `scripts/*.exs` must be referenced. If you add a new
public module, contract file, or demo script, that test will fail
until the README is updated to match.

### Modal-specific wire-shape gotchas (each caught live, comments preserved at call sites)

- **Modal `Cls`**: the class-function's wire name is `<ClassName>.*`
  (literal `.*`), not `<ClassName>` — Modal uses the wildcard as
  "single Function handling all method dispatches." AppPublish for
  classes uses `function_ids` keyed by `<Class>.*` and `class_ids`
  keyed by `<Class>` — mixing them returns opaque INTERNAL errors. See
  `lib/modal/cls.ex` (deploy) and `test/modal/cls_test.exs`.
- **Modal generators**: must use `FUNCTION_CALL_INVOCATION_TYPE_SYNC_LEGACY`
  at spawn time AND the `FunctionCallGetDataOut` server-streaming RPC
  (not the regular outputs poller). Plain ASYNC silently returns `[]`
  for generator functions. See `lib/modal/function.ex` (`stream/2`,
  `invoke_stream/5`, `spawn/4`'s `:generator` opt).
- **Modal Volume v2**: `VolumeListFiles` returns
  `INVALID_ARGUMENT: Operation not supported for v2 volumes`. Use
  `VolumeListFiles2` (server-streaming) instead. Likewise
  `VolumeGetFile2`. `VolumeReload` / `VolumeCommit` are
  worker-only — they return `FAILED_PRECONDITION` from the
  orchestrator.
- **Modal Proxy**: dashboard-provisioned only.
  `ProxyGetOrCreate` returns "Creation method not supported." Library
  exposes `Modal.Proxy.get/3` only.
- **`github_cidrs!/1`**: Modal's `NetworkAccess.allowed_cidrs` rejects
  IPv6 — the helper filters IPv6 by default (`:family` opt).

### Error model is one struct

Every failable op returns
`{:ok, value} | {:error, %Modal.Error{kind:, code:, message:, metadata:}}`.
The bang variants raise `%Modal.Error{}` (which `use Exception`).
`Modal.Error.transient?/1` classifies for retry. Adding a new failure
mode means adding to the `kind` table in `lib/modal/error.ex`'s
moduledoc (the table is the canonical contract).

### Telemetry contract

Two event families, identical shape:

- `[:modal, :rpc, :start | :stop | :exception]` — control plane (every
  method in `Modal.RPC`'s dispatch table).
- `[:modal, :worker_rpc, :start | :stop | :exception]` — per-exec
  (task_exec_start, stdio_read, wait, stdin).

Stop metadata always includes `:status` (`:ok | :error`); error stops
add `:error_kind` (`:grpc | :network | :timeout | …`) and `:code` so
dashboards can group without pattern-matching the body. `:attempt`
(0..3) is on **both** start and stop spans for retry visibility — when
adding a new `call_*` path, include `:attempt` in stop metadata
manually (`:telemetry` doesn't auto-merge start into stop).

## Demo scripts (`scripts/`)

Self-bootstrapping `.exs` files via `Mix.install/2` — runnable directly
with `elixir scripts/<name>.exs`. App names follow
`modal-elixir-<name>`. They take user-specific parameters
(repo URL, ticket text) via `System.argv()`. They're live dogfood — a
script breaking is a real bug. If you add one, add a row to the
Examples table in `README.md` (or `Modal.ReadmeClaimsTest` will fail).

## When stuck

- Wire-format question? Check the corresponding
  `test/contract/*_contract_test.exs` first — those tests **document**
  the live wire shape with assertions.
- "Does Modal do X?" — look at `modal-client/` (upstream Python source
  checked out at repo root) before guessing. The Python SDK's
  `_runtime/user_code_imports.py`, `runner.py`, and `_container_io_manager.py`
  are the most reverse-engineered files in there.
- Don't add a new event family, error kind, or retry policy without
  updating the corresponding table in the moduledoc / README. Future
  Claude (and `Modal.ReadmeClaimsTest`) reads those tables as the
  contract.
