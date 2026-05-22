# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-22

Initial preview release.

> **Preview status.** The public API is not yet frozen. Expect refinements to
> function signatures, option names, and error tuples until `1.0`. Pin a
> specific version in your `mix.exs` while we iterate.

### Added

- `Modal.Client` — supervised gRPC connection to `api.modal.com`, dispatches
  every RPC through a per-client `Task.Supervisor` so a single client serves
  many concurrent requests without head-of-line blocking. Optional
  `:max_concurrency` cap returns `{:error, :overloaded}` when saturated.
- `Modal.App` — `lookup/3` (get-or-create by name).
- `Modal.Image` — `get_or_create/3` blocks until the image build finishes and
  returns `{:ok, image_id, :cached | :built}` so callers can distinguish a
  cache hit from a fresh build.
- `Modal.Sandbox` — lifecycle (`create/2`, `terminate/1`, `wait/2`, `poll/1`,
  `wait_until_ready/2`), `from_name/3`, `list/2`, `get_task_id/1`,
  `stdin_write/3`, `get_logs/2`, tunnels (`tunnels/1`, `connect_token/2`),
  snapshots (`snapshot/2`, `restore/2`, `snapshot_filesystem/2`).
- `Modal.ContainerProcess` — streaming stdout (`stream/1`), block-and-collect
  (`await/2`), stdin (`write/3`), exit-code poll (`exit_code/1`),
  caller-monitored channel cleanup, JWT-expiry guard.
- `Modal.Filesystem` — `read_file/2`, `write_file/3`, `ls/2`, `mkdir/3`,
  `rm/3` against a running sandbox, exposed as delegates from `Modal.Sandbox`.
- Telemetry — every RPC emits `[:modal, :rpc, :start | :stop | :exception]`
  with `%{method: atom, kind: :unary | :stream | :stream_reduce}` metadata.
- Test surface — 105 unit + property tests (Mox + StreamData), a separate
  contract-test suite (`@moduletag :contract`) that drives real Modal RPCs to
  validate our mocks against the wire, and integration tests that boot real
  sandboxes (`@moduletag :integration`).
- Examples — `mix modal.{smoketest,calc,demo,eval,screenshot,clip,claude}`
  covering Python exec, warm sandboxes, snapshot/restore, two-phase eval,
  headless Chromium, ffmpeg, and Claude Code on a ticket.

[Unreleased]: https://github.com/ivarvong/modal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ivarvong/modal/releases/tag/v0.1.0
