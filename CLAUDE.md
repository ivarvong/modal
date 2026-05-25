# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Elixir client for Modal (modal.com) — supervised gRPC client for
sandboxes, autoscaling Functions + Classes, Dict / Queue / Volume /
Secret / Tunnel / Proxy / CloudBucket, with cross-runtime Python
pickle interop. Distributed on Hex as `modal`. **Public-facing,
critical infrastructure** — every change ships through CI on every
push and lands via PR. `README.md` is the user-facing pitch;
`CONTRIBUTING.md` covers option validation, error returns, bang
variants, and demo scripts; `guides/ship_checklist.md` is the
operational rationale behind a lot of the API shape.

## Git workflow: PR-only

Never `git push` directly to `main`. Never force-push to `main`, even
if explicitly authorized in conversation — the answer is to open a PR.
CI on `main` is the source of truth for the published package.

1. `git switch -c <topic>` off `main`.
2. Commit on the branch (one logical change per PR).
3. `git push -u origin <topic>`.
4. `gh pr create` — then **always** `open <url>` so the user can review.
5. `gh pr merge` once CI is green.

## Verification gate (run before every PR)

```sh
mix format --check-formatted && mix credo --strict && mix test \
  && MIX_ENV=dev mix docs && mix dialyzer
```

All five gate CI. Running locally first avoids round-trips. For
contract changes also run `mix modal.contract` (live, ~3:30, needs
credentials). The contract task deliberately refuses to start without
`MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET` — a silent no-op is
indistinguishable from "tests didn't verify anything," do not paper
over that.

## Toolchain

`.tool-versions` pins **Elixir 1.19.5 / OTP 28.4**. CI matrix also
runs **1.18.4 / OTP 27.3** for compat; new code must work on both.
Keep local in sync via asdf / mise — different patch versions of
Elixir reformat differently, and a local/CI mismatch produces CI-only
format diffs.

## Commands

```sh
mix test                          # 489 tests + 26 properties, all-Mox, ~6s
mix test test/path/to_test.exs    # one file
mix test test/path/to_test.exs:42 # one test by line
mix modal.contract                # live, gated on credentials
mix format                        # auto-fix
mix credo --strict
MIX_ENV=dev mix docs              # ex_doc is dev-only
mix dialyzer                      # first run builds PLT ~2 min
```

## Architecture rules

**`Modal.Client` is the unit of isolation.** One GenServer holds one
gRPC channel + one set of credentials. SaaS pattern is one named
`Modal.Client` per tenant. Per-client `Task.Supervisor` dispatches
RPCs concurrently; `:max_concurrency` returns
`{:error, %Modal.Error{kind: :overloaded}}` when saturated.

**Always route through `Modal.RPC.call/4`** (or `stream/4` /
`stream_reduce/6`) — never reach `Modal.Client.rpc/4` directly. The
PascalCase atom in `@methods` at `lib/modal/rpc.ex` gives compile-time
typo safety, emits `[:modal, :rpc, :*]` telemetry, and applies
exponential-backoff retry on transient gRPC codes (UNAVAILABLE,
DEADLINE_EXCEEDED, RESOURCE_EXHAUSTED, ABORTED + network). Adding a
new RPC = add the atom to `@methods` (additive = minor version bump;
rename/remove = major).

**Use `call_no_retry/4` for poll-style RPCs** where DEADLINE_EXCEEDED
is a domain signal, not a transport failure: `SandboxWait`,
`SandboxWaitUntilReady`, `FunctionGetOutputs`. Retrying these inflates
apparent latency and breaks poll semantics.

**Three behaviour seams** (`lib/modal/*/behaviour.ex`, mocks in
`test/test_helper.exs`):
- `Modal.Client.Behaviour` — RPC dispatch; tests hook via
  `config :modal, :client_impl, Modal.Client.Mock`
- `Modal.ModalStub.Behaviour` — raw gRPC stub (for tests inspecting
  auth headers / gRPC metadata)
- `Modal.TaskCommandRouter.Behaviour` — per-exec worker channel

**Three test tiers**:
- `test/modal/*_test.exs` — pure Mox, no socket. Runs by default. Use
  `Mox.expect/3` (strict) or `Mox.stub/3` (loose, when retry would
  inflate the expect count).
- `test/contract/*_contract_test.exs` (`@moduletag :contract`) —
  drives real RPCs, asserts wire shape matches mocks. Run via
  `mix modal.contract`.
- `@moduletag :integration` — heavier live runs; excluded by default.

**Telemetry contract**: two families, identical shape —
`[:modal, :rpc, ...]` (control plane) and `[:modal, :worker_rpc, ...]`
(per-exec). Stop metadata always includes `:status`; error stops add
`:error_kind` + `:code`. `:attempt` (0..3) on **both** start and stop
for retry visibility — when adding a new `call_*` path, include
`:attempt` in stop metadata manually (telemetry doesn't auto-merge).

## Wire-shape gotchas (each documented at the call site)

Read the moduledoc / call-site comment before editing these — they
encode behaviors Modal's API exposes that can't be inferred from the
proto alone:

- **`Modal.Cls`** — class-function wire name is `<Class>.*` (literal
  `.*`); AppPublish `function_ids` key has `.*`, `class_ids` does not.
- **Modal generators** — must use `SYNC_LEGACY` invocation type +
  `FunctionCallGetDataOut` streaming RPC. ASYNC silently returns `[]`.
- **`Modal.Volume`** v2 — `VolumeListFiles2` / `VolumeGetFile2` only;
  legacy returns `INVALID_ARGUMENT`. `reload`/`commit` are
  worker-only.
- **`Modal.Proxy`** — dashboard-provisioned only;
  `ProxyGetOrCreate` returns "Creation method not supported."
- **`github_cidrs!/1`** — Modal rejects IPv6 in `allowed_cidrs`; the
  helper filters by default.

## Anti-patterns (do not introduce)

- **Don't call `Modal.Client.rpc/4` directly** — always go through
  `Modal.RPC.call/4` (typo safety + telemetry + retry).
- **Don't add retries around `call_no_retry/4` callers** — the
  no-retry choice is load-bearing for the poll-style RPCs above.
- **Don't edit `lib/modal/proto/**`** — generated from
  `modal-client/`. Regenerate; never hand-edit.
- **Don't add a new `Modal.Error` `:kind`** without updating the kind
  table in `lib/modal/error.ex`'s moduledoc. The table is the contract.
- **Don't add a new `[:modal, …]` telemetry event family** without
  discussion — two families is intentional. New RPCs reuse
  `[:modal, :rpc, *]`.
- **Don't add backwards-compatibility shims for unreleased changes** —
  we're pre-1.0. Bump the version and document in `CHANGELOG.md`.
- **Don't add demo scripts without** adding a row to the README
  Examples table. `Modal.ReadmeClaimsTest` will fail until you do.
- **Don't reach for `Process.sleep/1` in tests** — use the
  `wait_retry_delay: 0` / `rpc_retry_base_ms: 0` test config and Mox
  to drive timing deterministically.

## Public-API surface = SemVer contract

These are versioned. Additive = minor, rename / remove / breaking
shape change = major:

- The set of atoms in `Modal.RPC.@methods`
- The `[:modal, :rpc, *]` and `[:modal, :worker_rpc, *]` event shapes
  + their metadata keys
- The `kind:` table in `Modal.Error`
- Every `@spec`-annotated public function in modules listed under
  "Public API" in `mix.exs`'s `groups_for_modules`
- The structs Mox tests pattern-match on
  (`Modal.Client.<Name>Request/Response`)

Drift detector: `Modal.ReadmeClaimsTest` asserts the README's Public
modules table, contract files, and scripts table stay in sync with the
actual repo. If you change those, run that test.

## When stuck

- Wire-format question → check the corresponding
  `test/contract/*_contract_test.exs`; those tests **document** the
  live wire shape with assertions.
- "Does Modal do X?" → look at `modal-client/` (upstream Python source
  checked out at repo root); `_runtime/user_code_imports.py`,
  `runner.py`, and `_container_io_manager.py` are the most
  reverse-engineered files.
- When a Mox test breaks after a retry-related change, check whether
  the test was using `Mox.expect/3` to assert error propagation — the
  retry now fires N times, breaking the expected count. Switch to
  `Mox.stub/3` for those cases.

## Maintaining this file

Update when: (a) a Claude session makes a mistake that a rule here
would have prevented, (b) you add a new public RPC / error kind /
telemetry event, (c) a wire-shape gotcha is discovered. Treat every
"Claude got this wrong" moment as a CLAUDE.md edit candidate. Keep
under ~200 lines — bloat causes rules to be ignored. If a section
grows into a recipe (multi-step "how to add X"), it belongs in
`.claude/skills/<name>/SKILL.md` instead.

When compacting a long session, preserve: files modified this session,
any failing test names, and the contents of `Modal.RPC.@methods` if
edited.
