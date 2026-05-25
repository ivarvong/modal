# Contributing

Thanks for reading. This document covers the things you would otherwise
have to ask.

## Status

Preview. The public API may change before `1.0`. Issues and PRs that
identify real friction with current call sites are especially welcome —
those have a direct line into the next minor release.

## Setup

```bash
git clone https://github.com/ivarvong/modal
cd modal
mix deps.get
mix test
```

Elixir `~> 1.17`, OTP 26 or 27. No live Modal account required for the
default test run.

## Running the test suite

The default `mix test` runs 270+ unit and property tests against in-process
Mox stubs — fast, hermetic, no network. CI runs this on every push.

```bash
mix test                       # unit + property (~0.3s)
mix test --include integration # boots real Modal sandboxes — needs MODAL_TOKEN_ID / MODAL_TOKEN_SECRET
mix test --include contract    # drives real RPCs to validate the mocks against the wire
```

Both `:integration` and `:contract` tags are excluded by default. They
require live Modal credentials in your environment.

## Credentials

Tests never read your `~/.modal.toml`. For local integration runs, export
the env vars directly in your shell (or use direnv / a tool of your
choice):

```bash
export MODAL_TOKEN_ID=ak-...
export MODAL_TOKEN_SECRET=as-...
```

We deliberately avoid `.env`-in-repo conventions for the maintainer
account — a misplaced `git add -A` can leak production credentials.
`.env` IS in `.gitignore`; if you do use one, keep it outside this
working directory or set up a pre-commit guard.

## Code style

Run before every commit:

```bash
mix format --check-formatted
mix credo --strict
mix docs                      # should emit zero warnings
```

If you add a public function, add a `@spec` and a `@doc` — both are
load-bearing for ExDoc rendering. If you add a public option, document
each option key in the `## Options` section of the function's docstring.

## Error returns vs. raises

The library's convention:

- Operations that can fail return `{:ok, value} | {:error, %Modal.Error{}}`
- Bang variants (`!`) unwrap `{:ok, value}` and raise `%Modal.Error{}` on failure
- Option-shape validation errors (missing `:cmd`, conflicting `:app`/`:app_id`)
  return `{:error, %Modal.Error{kind: :validation}}`, not `ArgumentError`
- True type-contract violations (passing an integer where a struct was required)
  raise `ArgumentError`

If you add a new failure mode, add a `kind:` atom to `Modal.Error` and
update the kind table in the `Modal.Error` moduledoc.

## Telemetry

Two event families, same shape: `[:modal, :rpc, …]` for control-plane,
`[:modal, :worker_rpc, …]` for per-exec. See `Modal.Telemetry` for the
documented event list and metadata contract. If you add a new RPC, it
should emit through `Modal.RPC.call/4` (or `Modal.ContainerProcess`'s
worker-channel span helper) so telemetry fires automatically — don't
add a new event family without discussion.

## Demo scripts

Live in `scripts/`, runnable directly via `elixir scripts/<name>.exs`.
Each one self-bootstraps via `Mix.install/2`. If you add a new script:

- Use `Modal.Credentials.load!()` to pick up credentials
- Use `Modal.Sandbox.with_sandbox/3` for the resource-scoped pattern
- Prefer `exec_streaming!/3` over manual `exec + await + close`
- App name should follow the `modal-elixir-<name>` convention
- Take any user-specific parameter (repo URL, ticket text) via `System.argv()`
  with a clearly-public default — no hardcoded private resources

## PR expectations

- One logical change per PR. A refactor and a feature is two PRs.
- Test coverage for new public behavior. Use Mox for unit tests; reserve
  `:integration` for things only real Modal can validate (snapshot/restore,
  tunnels, real wire-format compatibility).
- Update `CHANGELOG.md` under `[Unreleased]` — `Added`, `Changed`,
  `Fixed`, or `Removed`. The format isn't strict Keep-a-Changelog but
  it should be skimmable.
- For breaking changes during preview, flag in the changelog with a
  `BREAKING` tag and a migration note.

## Releasing (maintainers)

```bash
# Bump @version in mix.exs
# Move [Unreleased] → [N.M.0] in CHANGELOG.md with the release date
# Update the link defs at the bottom of CHANGELOG.md

git commit -am "Release vN.M.0"
git tag -a vN.M.0 -m "vN.M.0"
git push --follow-tags
```

Hex publish runs from the `v*` tag via `.github/workflows/release.yml`.

## Questions

Open an issue. Drive-by improvements to docs, scripts, or test coverage
are always welcome and don't need pre-discussion.
