# Shipping a real Modal service from Elixir

A practical checklist for getting an Elixir-orchestrated Modal service
into production. Distilled from the lessons of building (and shipping)
the demos in [`scripts/`](https://github.com/ivarvong/modal/tree/main/scripts).

Most of these are things you'll trip over once and want to know
about. None of them are blockers — the library handles the wire shape;
this guide covers the operational seams.

## 1. Auth

Get tokens at <https://modal.com/settings/tokens>. Two env vars:

```sh
export MODAL_TOKEN_ID=ak-...
export MODAL_TOKEN_SECRET=as-...
```

In your supervision tree:

```elixir
children = [
  {Modal.Client,
   name: MyApp.Modal,
   token_id: System.fetch_env!("MODAL_TOKEN_ID"),
   token_secret: System.fetch_env!("MODAL_TOKEN_SECRET")}
]
```

**Multi-tenant**: start one named `Modal.Client` per tenant with that
tenant's credentials. RPCs dispatch through a per-client `Task.Supervisor`,
so a single client serves many concurrent requests without head-of-line
blocking. An optional `max_concurrency:` cap rejects new RPCs with
`{:error, %Modal.Error{kind: :overloaded}}` when saturated.

Never bake tokens into images; for sandboxes that need them at runtime,
use `Modal.Secret`:

```elixir
{:ok, secret_id} = Modal.Secret.create(client,
  app: app, name: "anthropic", env: %{"ANTHROPIC_API_KEY" => key})

Modal.Sandbox.create!(client, ..., secret_ids: [secret_id])
```

## 2. Error discrimination

Every error is a `%Modal.Error{kind:, code:, message:, metadata:}`. The
`:kind` atom is your branch:

```elixir
case Modal.Sandbox.create(client, opts) do
  {:ok, sandbox} ->
    handle(sandbox)

  {:error, %Modal.Error{kind: :validation, message: msg}} ->
    # Your opts didn't validate locally. Fix in code; never user input.
    Logger.error("modal: bad opts: #{msg}")

  {:error, %Modal.Error{kind: :grpc, code: 8}} ->
    # RESOURCE_EXHAUSTED — Modal is rate-limiting us. Already retried 3x
    # automatically. If you see this in logs, you're hitting concurrency caps.
    {:retry_later, :modal_overloaded}

  {:error, %Modal.Error{kind: :grpc, code: 7}} ->
    # PERMISSION_DENIED — token doesn't have access to this resource
    {:error, :forbidden}

  {:error, %Modal.Error{kind: :grpc, code: 13}} ->
    # INTERNAL — Modal-side bug. Surface verbatim, page on-call.
    Logger.error("modal internal: #{inspect(err)}")

  {:error, %Modal.Error{kind: :function_failed, message: msg, metadata: meta}} ->
    # A remote Python function raised an exception. meta.exception has the
    # message, meta.traceback has the Python traceback string.
    Logger.error("function raised: #{msg}\n#{meta[:traceback]}")

  {:error, %Modal.Error{} = err} ->
    Logger.error("modal: #{Exception.message(err)}")
end
```

**Transient vs definitive**: `Modal.Error.transient?/1` says whether the
client would retry it (UNAVAILABLE / DEADLINE_EXCEEDED / RESOURCE_EXHAUSTED
/ ABORTED on gRPC, or `:network` errors). The client retries up to 3 times
with exponential backoff automatically — by the time an error reaches your
code, it's already past the retry attempts.

Poll-style RPCs (`Sandbox.wait`, `Function.await` / `stream`) opt out of
retry — for those, DEADLINE_EXCEEDED means "not ready yet, ask again,"
not "transient failure." Look for `RPC.call_no_retry` in source if you
need this for your own escape-hatch calls.

## 3. Telemetry

Two event families, one shape:

| Prefix                    | Source                                                    |
| ------------------------- | --------------------------------------------------------- |
| `[:modal, :rpc, …]`       | Control-plane RPCs (App, Sandbox, Image, Function, …)     |
| `[:modal, :worker_rpc, …]`| Per-exec RPCs (task_exec_start / stdio_read / wait)       |

Each emits `:start`, `:stop`, `:exception`. Stop metadata for `:rpc`:

```elixir
%{
  method:     :SandboxCreate,
  kind:       :unary,                       # | :stream | :stream_reduce
  attempt:    0,                            # 0..3 for retried calls
  status:     :ok,                          # | :error
  error_kind: :grpc,                        # only on :error
  code:       8                             # only on :error
}
```

Each retry attempt emits its own span (with `:attempt` distinguishing
them) so dashboards see retry storms as discrete events, not one
mysteriously-slow call.

Bare-minimum wiring:

```elixir
:telemetry.attach_many("modal-metrics",
  [
    [:modal, :rpc, :stop],
    [:modal, :worker_rpc, :stop]
  ],
  fn _event, %{duration: ns}, meta, _ ->
    duration_ms = System.convert_time_unit(ns, :native, :millisecond)
    # ship to Telemetry.Metrics / your StatsD / whatever
  end, nil)
```

For Telemetry.Metrics, group by `:method` + `:status` to get per-RPC
error rates + latency histograms.

## 4. Cost monitoring

Modal bills per-second on CPU + memory + GPU. Roughly:

- **vCPU**: $0.0000131 / sec
- **memory**: $0.00000222 / GiB-sec
- **GPU**: varies wildly ($0.0001/sec T4 → $0.001+/sec H100)

Free tier: $30/month. The order-of-magnitude cost ranges by primitive:

| Pattern                          | Cost                          |
| -------------------------------- | ----------------------------- |
| Sandbox one-shot (e.g. `Sandbox.run/2` with 1s of work) | fractions of a cent / call |
| Function (scale-to-zero, light traffic) | pennies/day |
| Function with `min_containers: 1` warm | ~$5/month per warm container |
| `Modal.Cls` with GPU (`min_containers: 1`, A100) | ~$70/day per warm container |
| `Modal.Dict` / `Modal.Queue` storage + RPCs | negligible |

**Watch for**: `min_containers: N` keeps N containers running 24/7. Easy
to leave on by accident after a demo. Check the dashboard's billing page
weekly during development.

To stop everything in an app cleanly:

```elixir
Modal.App.publish(client, app, state: :stopped, function_ids: %{})
```

## 5. The AppPublish-replaces-registry gotcha

`Modal.App.publish/3` REPLACES the app's full function registry with the
`:function_ids` map you pass. If your app has multiple Functions, calling
`Modal.Function.deploy_*` individually for each one silently de-registers
the previous functions (each deploy's `AppPublish` overwrites the rest).

Fix: use `Modal.Function.deploy_many/2`, or pass `publish: false` on each
individual deploy and call `Modal.App.publish/3` once at the end with all
the IDs:

```elixir
{:ok, [poller, web]} =
  Modal.Function.deploy_many(client, [
    {:function, app: app, name: "poll", ...},
    {:asgi,     app: app, name: "web",  ...}
  ])
```

This trap cost me an afternoon. It's now caught by
`scripts/fastapi_nyct.exs` and pinned in
`test/contract/function_contract_test.exs`.

## 6. Teardown hygiene

`Modal.Sandbox` supports `:terminate_on_caller_exit` — a watchdog
process that calls `SandboxTerminate` if the calling Elixir process
dies. Closes the silent-money-leak footgun where a Phoenix request
handler dies mid-flight and leaves the sandbox running.

```elixir
Modal.Sandbox.create!(client, ...,
  terminate_on_caller_exit: true)
```

For Functions and Classes, redeployment is in-place by name — no
explicit teardown needed. To fully stop an app:

```elixir
Modal.App.publish(client, app, state: :stopped, function_ids: %{})
```

## 7. Choosing the right primitive (cheat sheet)

| Need                                                  | Use                       |
| ----------------------------------------------------- | ------------------------- |
| One-shot exec (`python -c ...`, run a script)         | `Modal.Sandbox.run/2`     |
| Persistent shell, multiple execs, snapshot/restore    | `Modal.Sandbox`           |
| Stateless autoscaling HTTP service                    | `Modal.Function.deploy_asgi/2` |
| Stateful service (load model once, serve N requests)  | `Modal.Cls`               |
| Background job on a schedule                          | `Modal.Function.deploy_function/2` + `:schedule` |
| Call a deployed function from Elixir                  | `Modal.Function.invoke/5` / `spawn/4` |
| Stream incremental results (LLM tokens)               | `Modal.Function.invoke_stream/5` (with `generator: true`) |
| Shared KV across containers                           | `Modal.Dict`              |
| Work queue with atomic pop                            | `Modal.Queue`             |
| Persistent file storage                               | `Modal.Volume`            |
| Mount existing S3 / R2 / GCS bucket                   | `Modal.CloudBucket`       |
| Egress allowlist (you restrict where you can reach)   | `Sandbox` `:network_access` |
| Static outbound IP (target allowlists you)            | `Modal.Proxy`             |

## 8. Cross-runtime with Python workers

`Modal.Pickle` produces bytes **byte-equivalent** to CPython's
`pickle.dumps(value, protocol=4)`. That means an Elixir orchestrator can
write to a `Modal.Dict` / `Modal.Queue` and a Python worker reads
natively via `modal.Queue.get()` / `modal.Dict.get(key)` — no monkey-
patching, no `json.loads`.

The byte-equality matters for **Dict keys** specifically: Modal's Dict
server compares keys as raw bytes. A semantically-equal but byte-
different pickle silently misses the lookup.

```elixir
Modal.Dict.put(d, "k", %{count: 42}, encoding: :pickle)
Modal.Queue.put(q, [1, 2, 3], encoding: :pickle)
```

```python
# Python — no special imports:
import modal
modal.Dict.from_name("...").get("k")   # → {'count': 42}
modal.Queue.from_name("...").get()     # → [1, 2, 3]
```

Supported: `nil` / bool / int (any width) / float / binary (str or
bytes) / list / tuple / map. Refuses pickle's `REDUCE` / `OBJ` /
`BUILD` opcodes on decode (the headline pickle security hole — and
naturally unavailable from BEAM anyway).

## 9. Running contract tests against your account

```sh
MODAL_TOKEN_ID=... MODAL_TOKEN_SECRET=... mix modal.contract
```

Drives real RPCs against Modal to verify the library's Mox-based unit
tests still match the live API. ~50 tests, ~80s end-to-end. Run
before pinning a new version of the library.

The task refuses to start without credentials — silent no-ops would
be indistinguishable from "tests didn't verify anything."

## 10. What's NOT in the library yet

Documented gaps as of v0.1 so you don't waste time looking:

- **i6pn (inter-container IPv6 mesh)** — distributed training across
  Modal containers. Not exposed; the proto field exists.
- **NetworkFileSystem** — legacy NFS-shaped shared storage. Most users
  want `Modal.Volume` instead (modern, content-addressed).
- **Function `.spawn_map`** — bulk fan-out via a single FunctionMap
  with many inputs. Use `Task.async_stream` + `Modal.Function.spawn/4`
  for now.
- **Mount manipulation** — `mount_client_dependencies: true` handles
  modal's own deps; you can't upload arbitrary mounts from Elixir yet.
- **Modal.Cls warm-restore / GPU snapshots** — newer Modal Python
  features for fast container resume.

None of these block production use of the library for the patterns
above. They're tracked.

---

If you hit something not covered here, or want to validate a pattern
end-to-end, the `scripts/` directory has runnable demos against real
Modal for each major primitive — they're the canonical "this is what
the API looks like in motion" reference.
