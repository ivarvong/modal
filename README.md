# Modal

[![CI](https://github.com/ivarvong/modal/actions/workflows/ci.yml/badge.svg)](https://github.com/ivarvong/modal/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/modal.svg)](https://hex.pm/packages/modal)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/modal)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Elixir client for [Modal](https://modal.com) sandboxes. Spin up a container,
stream a command's stdout, snapshot the filesystem, restore it later — all
from a supervised `GenServer`.

> **Status: preview (v0.1.0).** The public API may change before `1.0`. Pin
> the exact version you depend on while we iterate.

```elixir
# mix.exs
{:modal, "~> 0.1.0"}
```

## Why Elixir for Modal?

If you are building anything that spawns sandboxes per user — a coding agent,
a notebook runner, a CI-in-a-box, a sandboxed code interpreter for an LLM
product — you eventually want each user's work to be its own supervised
process with its own credentials, lifecycle, and crash boundary. The BEAM is
the right runtime for that, and Modal is the right primitive underneath.

This library is the bridge: `Modal.Client` is a `GenServer` that holds one
gRPC channel and one set of credentials. Start one per tenant in your
supervision tree and the rest is ordinary Elixir.

## A more interesting demo

The headline example, [`mix modal.claude`](examples/modal.claude.ex), runs
[Claude Code](https://claude.ai/code) headless inside a Modal sandbox and
returns a diff:

```bash
export MODAL_TOKEN_ID=...
export MODAL_TOKEN_SECRET=...
export ANTHROPIC_API_KEY=sk-ant-...

mix modal.claude "fix the typo in the README and tighten the install steps"
```

The image (Claude CLI, Elixir, pre-cloned repo, warmed build cache) is
content-addressed by Modal — the second run boots from a cache hit. The
caller's `ANTHROPIC_API_KEY` is uploaded as an ephemeral Modal Secret at
exec time, never baked into the image. The whole thing — boot, pull, run,
diff — is a few seconds per ticket once the image is warm.

The same shape works for any agent that needs an isolated shell.

## Quick start

```elixir
{:ok, client} =
  Modal.Client.start_link(
    token_id: System.fetch_env!("MODAL_TOKEN_ID"),
    token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")
  )

{:ok, app_id}              = Modal.App.lookup(client, "my-app")
{:ok, image_id, _status}   = Modal.Image.get_or_create(client, ["FROM python:3.14-slim"])

sandbox =
  Modal.Sandbox.create!(client,
    app_id: app_id,
    image_id: image_id,
    cmd: ["sleep", "infinity"]
  )

# Stream stdout as it arrives.
{:ok, proc} = Modal.Sandbox.exec(sandbox, ["echo", "hello from modal"])
proc |> Modal.ContainerProcess.stream() |> Enum.each(&IO.write/1)
{:ok, 0} = Modal.ContainerProcess.exit_code(proc)
Modal.ContainerProcess.close(proc)

# Or block and collect.
{:ok, proc} = Modal.Sandbox.exec(sandbox, ["python3", "-c", "print(2+2)"])
{:ok, %{stdout: "4\n", code: 0}} = Modal.ContainerProcess.await(proc)
Modal.ContainerProcess.close(proc)

# File I/O against a running sandbox.
:ok           = Modal.Sandbox.write_file(sandbox, "/tmp/test.txt", "hello")
{:ok, "hello"} = Modal.Sandbox.read_file(sandbox, "/tmp/test.txt")
{:ok, files}   = Modal.Sandbox.ls(sandbox, "/tmp")

# Snapshot the filesystem as a reusable image, then boot a new sandbox
# from it instantly.
{:ok, snap_image_id} = Modal.Sandbox.snapshot_filesystem(sandbox)
Modal.Sandbox.terminate(sandbox)

sandbox2 =
  Modal.Sandbox.create!(client,
    app_id: app_id,
    image_id: snap_image_id,
    cmd: ["sleep", "infinity"]
  )
```

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

Every RPC emits:

- `[:modal, :rpc, :start]`
- `[:modal, :rpc, :stop]`
- `[:modal, :rpc, :exception]`

with `%{method: atom, kind: :unary | :stream | :stream_reduce}` metadata.
Attach a handler to surface latency, error rates, and per-method throughput
in your observability stack.

## Public modules

| Module                   | What it does                                                    |
| ------------------------ | --------------------------------------------------------------- |
| `Modal.Client`           | Supervised gRPC connection to `api.modal.com`                   |
| `Modal.App`              | App lookup / get-or-create                                      |
| `Modal.Image`            | Container image builds, with cached/built status                |
| `Modal.Sandbox`          | Sandbox lifecycle, exec, filesystem, logs, tunnels, snapshots   |
| `Modal.ContainerProcess` | A running command — streaming stdout, stdin, exit code, timeout |
| `Modal.Filesystem`       | `read_file/2`, `write_file/3`, `ls/2`, `mkdir/3`, `rm/3`        |

## Examples

In [`examples/`](examples/) (Mix tasks, not part of the published package):

| Task               | Demo                                                          |
| ------------------ | ------------------------------------------------------------- |
| `mix modal.claude` | Claude Code on a ticket, sandboxed, with an ephemeral secret  |
| `mix modal.eval`   | Two-phase: cache a per-repo test image, then `git pull` + run |
| `mix modal.demo`   | Clone, install, snapshot, restore — full coding-agent loop    |
| `mix modal.calc`   | A warm Python sandbox; first call is boot, rest are sub-100ms |
| `mix modal.screenshot URL` | Headless Chromium via Playwright                      |
| `mix modal.clip URL --end 30` | `ffmpeg` clip + resize to 720p                     |
| `mix modal.smoketest` | The smallest possible end-to-end check                     |

## Testing your own code

The library ships with behaviours and is fully mockable via [Mox](https://hex.pm/packages/mox):

- `Modal.Client.Behaviour` — the RPC surface
- `Modal.ModalStub.Behaviour` — the gRPC stub
- `Modal.TaskCommandRouter.Behaviour` — the worker-side TCR stub

Point `:modal, :client_impl` at your mock in `config/test.exs` and unit-test
without ever opening a socket. See [`test/`](test/) for ~100 tests including
property-based tests for `Modal.JWT`, `Modal.Filesystem`, and `Modal.Sandbox`
options coercion, plus a contract-test suite (`@moduletag :contract`) that
drives real RPCs to validate the mocks against the wire.

## Roadmap to 1.0

- Streaming logs as an `Enumerable` rather than a paged fetch
- A higher-level `Modal.Function` wrapper for stateless one-shot execs
- Volume mount ergonomics: `Modal.Volume`-style typed handle
- Optional `Application` callback for users who want auto-start

Open an issue if any of these would unblock you, or if there's something else
the BEAM needs to talk to Modal well.

## Attribution

Proto definitions are generated from
[modal-labs/modal-client](https://github.com/modal-labs/modal-client)
(Apache 2.0). See [NOTICE](NOTICE).

## License

[MIT](LICENSE).
