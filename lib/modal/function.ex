defmodule Modal.Function do
  @moduledoc """
  Modal Functions — serverless containers that Modal autoscales and
  routes HTTP traffic to directly. The right primitive for serving a
  FastAPI / ASGI app from Modal; `Modal.Sandbox` is the right primitive
  for stateful per-tenant containers you exec into.

  ## Why Functions over Sandbox+tunnel for HTTP

  A `Modal.Sandbox` with `:ports` and `Modal.Sandbox.tunnels/1` gives
  you an HTTPS endpoint, but each request routes through Modal's tunnel
  layer (extra ~100ms hop), and you pay for the sandbox's full
  wall-clock lifetime. A Modal `Function` deployed via this module is:

    * **Edge-routed** — Modal's HTTP frontend dispatches directly to
      the container, no tunnel.
    * **Scale-to-zero** — idle containers are reaped after
      `:idle_timeout_secs`; cold start spins one up.
    * **Persistent** — the URL stays live across deploys; redeploying
      with the same `:name` updates the function in place.

  ## Quick start — deploy a FastAPI app

      {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
      {:ok, app}    = Modal.App.lookup(client, "my-service")

      # Image must:
      #   * have `pip install modal` (Modal's worker imports it at boot)
      #   * contain a Python module that defines a *bare* callable
      #     returning the ASGI app — NO `@modal.asgi_app()` decorator
      #     (those are for Python SDK's deploy path; runtime calls
      #     the callable directly per `_runtime/user_code_imports.py`).
      {:ok, image_id, _} =
        Modal.Image.get_or_create(client, [
          "FROM python:3.14-slim",
          "RUN pip install --no-cache-dir modal fastapi",
          ~s|RUN cat > /root/entry.py <<'PY'
      from fastapi import FastAPI

      def serve():
          web = FastAPI()
          @web.get("/")
          def root():
              return {"hello": "world"}
          return web
      PY|
        ], app: app)

      {:ok, fn} =
        Modal.Function.deploy_asgi(client,
          app: app,
          name: "web",
          image_id: image_id,
          module: "entry",
          callable: "serve"
        )

      # fn.web_url → "https://<workspace>--my-service-web.modal.run"
      # Live immediately; routed by Modal's edge directly to your
      # container; auto-scales.

  ## Three RPCs under one call

  `deploy_asgi/2` orchestrates the same three-RPC dance Modal's
  Python SDK does (`runner.py:_deploy_app`):

    1. **`FunctionPrecreate`** — reserves the `function_id` with the
       ASGI format declaration. Critical: this is the toggle that
       tells Modal's edge to bridge HTTP↔ASGI directly, not wrap
       responses as async function calls (PICKLE/CBOR default).

    2. **`FunctionCreate`** — full Function definition with image,
       webhook config, timeouts, secrets. Uses `existing_function_id`
       from the precreate response.

    3. **`Modal.App.publish/3`** (which fires `AppPublish`) — flips
       app state to `:APP_STATE_DEPLOYED` and registers
       `{tag => function_id}` in the app's routing table. Without
       this, the function exists and returns a URL, but the URL
       returns `modal-http: invalid function call`.

  ## Webhook types

  `deploy_asgi/2` is the recommended path. `deploy_web_server/2` exists
  for the case where you'd rather start a long-running server in the
  container (uvicorn, nginx, anything) and have Modal proxy TCP to it
  — comparable to `@modal.web_server(port)` in Python.

  Both go through the same Precreate→Create→Publish flow with
  different `WebhookConfig.type` and slightly different worker
  semantics (`_runtime/user_code_imports.py:206-232`):

    * `WEBHOOK_TYPE_ASGI_APP` — worker calls `callable()`, expects an
      ASGI app back, runs ASGI dispatch.
    * `WEBHOOK_TYPE_WEB_SERVER` — worker calls `callable()` (which
      starts a server), then proxies HTTP to `127.0.0.1:port` inside
      the container.
  """

  alias Modal.RPC

  alias Modal.Client.{
    Function,
    FunctionCallGetDataRequest,
    FunctionCreateRequest,
    FunctionGetOutputsRequest,
    FunctionGetRequest,
    FunctionInput,
    FunctionMapRequest,
    FunctionPrecreateRequest,
    FunctionPutInputsItem,
    FunctionRetryPolicy,
    Schedule,
    WebhookConfig
  }

  defstruct [:id, :name, :web_url, :app]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          web_url: String.t() | nil,
          app: Modal.App.t()
        }

  # Format declaration: the field on FunctionPrecreate/FunctionCreate
  # that flips Modal's edge into ASGI-direct routing. Without this the
  # default is PICKLE/CBOR, which routes through Modal's async
  # function-call protocol (303 + `__modal_function_call_id`).
  @asgi_input_formats [:DATA_FORMAT_ASGI]
  @asgi_output_formats [:DATA_FORMAT_ASGI, :DATA_FORMAT_GENERATOR_DONE]

  @common_deploy_opts [
    app: [
      type: {:struct, Modal.App},
      required: true,
      doc: "The `%Modal.App{}` returned by `Modal.App.lookup/3`."
    ],
    name: [
      type: :string,
      required: true,
      doc:
        "Function URL tag. Becomes the subdomain segment in the deployed " <>
          "URL: `<workspace>--<app>-<name>.modal.run`."
    ],
    image_id: [
      type: :string,
      required: true,
      doc: "Image id from `Modal.Image.get_or_create/3`. Must have `pip install modal`."
    ],
    module: [
      type: :string,
      required: true,
      doc: "Python module name Modal worker imports (e.g. `\"entry\"` for `/root/entry.py`)."
    ],
    callable: [
      type: :string,
      doc: "Name of the callable inside `:module`. Defaults to `:name`."
    ],
    secret_ids: [type: {:list, :string}, default: []],
    timeout_secs: [
      type: :pos_integer,
      default: 300,
      doc: "Per-request wall-clock limit in seconds."
    ],
    idle_timeout_secs: [
      type: :pos_integer,
      default: 300,
      doc:
        "Container scale-down delay in seconds. Lower → tighter cost; higher → fewer cold starts."
    ],
    requires_proxy_auth: [
      type: :boolean,
      default: false,
      doc: "Require `Modal-Key`/`Modal-Secret` headers on every request."
    ],
    requested_suffix: [
      type: :string,
      doc:
        "URL subdomain segment. Defaults to `:name` so the deployed URL " <>
          "matches the dashboard tag. Override only if you want the URL " <>
          "slug to differ from the AppPublish tag."
    ],
    schedule: [
      type: {:custom, __MODULE__, :validate_schedule, []},
      doc: """
      Server-side recurring schedule. Modal keeps a single container warm
      and invokes the callable on the schedule. Two forms:

        * `{:period, seconds: 15}` — runs every N seconds (any combination
          of `:years`, `:months`, `:weeks`, `:days`, `:hours`, `:minutes`,
          `:seconds`). Equivalent to Python's `modal.Period(seconds=15)`.
        * `{:cron, "*/15 * * * * *"}` — cron expression in UTC. Pass
          `{:cron, expr, timezone: "America/New_York"}` to align to a
          specific zone. Equivalent to Python's `modal.Cron(...)`.

      Use Period for "every N seconds, no skew." Use Cron when you want
      calendar-aligned execution (e.g. top of every quarter-minute so
      multiple consumers all expect fresh data at :00/:15/:30/:45).
      """
    ],
    target_concurrent_inputs: [
      type: :pos_integer,
      doc: """
      Soft target for concurrent inputs per container. Modal's autoscaler
      tries to keep load below this. For I/O-bound HTTP handlers (reading
      from a Dict, calling an upstream API), pushing this to 32 or 64
      collapses container count substantially. Equivalent to the
      `target_inputs=` param of Python's `@modal.concurrent(...)`.
      """
    ],
    max_concurrent_inputs: [
      type: :pos_integer,
      doc: """
      Hard limit on concurrent inputs per container. Modal refuses to
      pack more than this onto a single container even under load.
      Equivalent to `max_inputs=` on `@modal.concurrent(...)`.
      """
    ],
    min_containers: [
      type: :non_neg_integer,
      doc: """
      Warm-pool size — Modal keeps this many containers ready, eliminating
      cold-start latency on the first request. `0` (default) means
      scale-to-zero. Equivalent to `min_containers=` on the Python decorator.
      """
    ],
    retries: [
      type: :non_neg_integer,
      doc: """
      Retry failed invocations up to N times with exponential backoff
      (Modal's default policy: 1s initial, 60s max). The right knob for
      scheduled pollers hitting flaky upstream APIs.
      """
    ],
    generator: [
      type: :boolean,
      default: false,
      doc: """
      Deploy as a generator function — the Python callable uses
      `yield` and each yielded value streams back as a separate
      result. Call with `Modal.Function.invoke_stream/5` or
      `Modal.Function.stream/2` to consume as an `Enumerable`.
      Equivalent to a Python `def gen(): yield ...` deployed via
      `@app.function(...)`.
      """
    ],
    gpu: [
      type: :string,
      doc: """
      GPU type string — `"T4"`, `"A10G"`, `"A100"`, `"A100-80GB"`,
      `"L4"`, `"L40S"`, `"H100"`, `"H100!"`, `"H200"`, `"B200"`.
      Modal selects from any available unit of that type. Equivalent
      to Python's `gpu="T4"` parameter on `@app.function`.
      """
    ],
    gpu_count: [
      type: :pos_integer,
      default: 1,
      doc: "Number of GPUs per container. Most workloads want 1."
    ],
    memory_mb: [
      type: :non_neg_integer,
      doc: "Memory reservation per container, in MB. Default lets Modal pick."
    ],
    cpu_millis: [
      type: :non_neg_integer,
      doc:
        "CPU reservation per container in millicores (1000 = one full core). " <>
          "Default lets Modal pick."
    ],
    disk_mb: [
      type: :non_neg_integer,
      doc: "Ephemeral disk per container, in MB. Default lets Modal pick."
    ],
    i6pn: [
      type: :boolean,
      default: false,
      doc: """
      Enable Modal's i6pn (internal IPv6 network) for this Function's
      containers. Lets containers in the same app reach each other on
      a private IPv6 mesh — the canonical wire for distributed
      training, parameter servers, or any peer-to-peer pattern. Each
      container exposes its address via `MODAL_I6PN_ADDR` env var on
      the Python side.
      """
    ],
    publish: [
      type: :boolean,
      default: true,
      doc: """
      Whether to fire `Modal.App.publish/3` after `FunctionCreate`.
      `AppPublish` REPLACES the app's full function registry, so when
      deploying multiple functions into the same app pass `publish: false`
      on each `deploy_*` call and finish with a single
      `Modal.App.publish(client, app, function_ids: %{name1 => id1, name2 => id2})`.
      Otherwise the second deploy silently de-registers the first.
      """
    ]
  ]

  @web_server_extra [
    web_server_port: [
      type: :pos_integer,
      default: 8000,
      doc: "Container port the user's server binds to. Modal proxies HTTP to it."
    ],
    web_server_startup_timeout: [
      type: :pos_integer,
      default: 30,
      doc: "Seconds Modal waits for the user's server to bind before erroring."
    ]
  ]

  # ── deploy_asgi ─────────────────────────────────────────────────

  @doc """
  Deploy a Python ASGI application (FastAPI, Starlette, Quart, …) as
  a Modal Function. Fires `FunctionPrecreate`, `FunctionCreate`, and
  `Modal.App.publish/3` in sequence — see the moduledoc.

  ## Options

  #{NimbleOptions.docs(@common_deploy_opts)}

  ## Returns

  `{:ok, %Modal.Function{}}` with `:web_url` populated and live, or
  `{:error, %Modal.Error{}}`.
  """
  @spec deploy_asgi(GenServer.server(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def deploy_asgi(client, opts) do
    with {:ok, validated} <- validate_opts(opts, @common_deploy_opts) do
      webhook = %WebhookConfig{
        type: :WEBHOOK_TYPE_ASGI_APP,
        requested_suffix: validated[:requested_suffix] || validated[:name],
        async_mode: :WEBHOOK_ASYNC_MODE_AUTO,
        requires_proxy_auth: validated[:requires_proxy_auth]
      }

      do_deploy(client, validated, webhook)
    end
  end

  @doc "Like `deploy_asgi/2` but raises on error."
  @spec deploy_asgi!(GenServer.server(), keyword()) :: t()
  def deploy_asgi!(client, opts) do
    case deploy_asgi(client, opts) do
      {:ok, fn_struct} -> fn_struct
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── deploy_function ─────────────────────────────────────────────

  @function_only_opts [
    app: @common_deploy_opts[:app],
    name: @common_deploy_opts[:name],
    image_id: @common_deploy_opts[:image_id],
    module: @common_deploy_opts[:module],
    callable: @common_deploy_opts[:callable],
    secret_ids: @common_deploy_opts[:secret_ids],
    timeout_secs: @common_deploy_opts[:timeout_secs],
    idle_timeout_secs: @common_deploy_opts[:idle_timeout_secs],
    schedule: @common_deploy_opts[:schedule],
    target_concurrent_inputs: @common_deploy_opts[:target_concurrent_inputs],
    max_concurrent_inputs: @common_deploy_opts[:max_concurrent_inputs],
    min_containers: @common_deploy_opts[:min_containers],
    retries: @common_deploy_opts[:retries],
    generator: @common_deploy_opts[:generator],
    gpu: @common_deploy_opts[:gpu],
    gpu_count: @common_deploy_opts[:gpu_count],
    memory_mb: @common_deploy_opts[:memory_mb],
    cpu_millis: @common_deploy_opts[:cpu_millis],
    disk_mb: @common_deploy_opts[:disk_mb],
    i6pn: @common_deploy_opts[:i6pn],
    publish: @common_deploy_opts[:publish]
  ]

  @doc """
  Deploy a non-webhook Function — the callable is invoked by Modal
  (on a `:schedule`, or via explicit `.remote()` calls) and does work
  directly. No HTTP routing, no ASGI; pair with `:schedule` for the
  canonical "background poller" shape.

  Same Precreate→Create→AppPublish dance as `deploy_asgi/2`, but with
  `webhook_config: nil` and Modal's default input/output formats
  (PICKLE/CBOR) — the function-call protocol Modal uses for non-web
  invocations.

  ## Options

  #{NimbleOptions.docs(@function_only_opts)}

  ## Returns

  `{:ok, %Modal.Function{}}` with `:web_url` nil (this is not a web
  endpoint), or `{:error, %Modal.Error{}}`.

  ## Example — a 15-second scheduled poller

      Modal.Function.deploy_function(client,
        app: app,
        name: "poll-feeds",
        image_id: image_id,
        module: "entry",
        callable: "poll",
        schedule: {:period, seconds: 15},
        retries: 3,
        timeout_secs: 30
      )
  """
  @spec deploy_function(GenServer.server(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def deploy_function(client, opts) do
    with {:ok, validated} <- validate_opts(opts, @function_only_opts) do
      do_deploy(client, validated, nil)
    end
  end

  @doc "Like `deploy_function/2` but raises on error."
  @spec deploy_function!(GenServer.server(), keyword()) :: t()
  def deploy_function!(client, opts) do
    case deploy_function(client, opts) do
      {:ok, fn_struct} -> fn_struct
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── deploy_many ─────────────────────────────────────────────────

  @doc """
  Deploy multiple Functions into the same app atomically. Use this
  whenever your app has more than one Function — `AppPublish`
  REPLACES the app's full function registry, so calling `deploy_*`
  individually with their own publishes silently de-registers each
  earlier function.

  Each entry is `{kind, opts}` where `kind` is `:asgi`,
  `:web_server`, or `:function` (matches the three `deploy_*/2`
  variants). All entries must share the same `:app`.

  Internally: runs `Precreate + Create` for each Function (no
  `AppPublish`), then fires ONE `Modal.App.publish/3` with the
  combined `function_ids` map. Mirrors Modal Python's
  `runner.py:_deploy_app` flow.

  ## Example — staff+ NYCT shape (scheduled poller + autoscaling web)

      {:ok, [poller, web]} =
        Modal.Function.deploy_many(client, [
          {:function,
           app: app,
           name: "poll",
           image_id: image_id,
           module: "app.poller",
           callable: "poll",
           schedule: Modal.Period.seconds(15),
           retries: 3,
           min_containers: 1},
          {:asgi,
           app: app,
           name: "web",
           image_id: image_id,
           module: "app.web",
           callable: "serve",
           target_concurrent_inputs: 64}
        ])

  ## Returns

  `{:ok, [%Modal.Function{}, ...]}` in the SAME order as input
  (so destructuring works), or `{:error, %Modal.Error{}}` on any
  failure (no partial publish).
  """
  @spec deploy_many(GenServer.server(), [{atom(), keyword()}]) ::
          {:ok, [t()]} | {:error, Modal.Error.t()}
  def deploy_many(_client, []) do
    {:ok, []}
  end

  def deploy_many(client, [{_kind, first_opts} | _] = entries) when is_list(entries) do
    app = Keyword.fetch!(first_opts, :app)

    if Enum.any?(entries, fn {_, opts} -> Keyword.get(opts, :app) != app end) do
      {:error,
       Modal.Error.validation(%NimbleOptions.ValidationError{
         message: "deploy_many/2: all entries must share the same :app",
         key: :app,
         value: nil,
         keys_path: []
       })}
    else
      do_deploy_many(client, app, entries)
    end
  end

  defp do_deploy_many(client, app, entries) do
    # Precreate + Create for each (publish: false) — collect IDs.
    create_result =
      Enum.reduce_while(entries, {:ok, []}, fn {kind, opts}, {:ok, acc} ->
        deferred = Keyword.put(opts, :publish, false)

        case deploy_kind(client, kind, deferred) do
          {:ok, fn_struct} -> {:cont, {:ok, [fn_struct | acc]}}
          {:error, err} -> {:halt, {:error, err}}
        end
      end)

    with {:ok, reversed_structs} <- create_result,
         structs = Enum.reverse(reversed_structs),
         function_ids = Map.new(structs, fn s -> {s.name, s.id} end),
         {:ok, _publish} <- Modal.App.publish(client, app, function_ids: function_ids) do
      {:ok, structs}
    end
  end

  defp deploy_kind(client, :asgi, opts), do: deploy_asgi(client, opts)
  defp deploy_kind(client, :web_server, opts), do: deploy_web_server(client, opts)
  defp deploy_kind(client, :function, opts), do: deploy_function(client, opts)

  defp deploy_kind(_client, kind, _opts) do
    {:error,
     Modal.Error.validation(%NimbleOptions.ValidationError{
       message:
         "deploy_many/2: unknown kind #{inspect(kind)}, expected :asgi | :web_server | :function",
       key: :kind,
       value: kind,
       keys_path: []
     })}
  end

  # ── deploy_web_server ───────────────────────────────────────────

  @doc """
  Deploy a long-running web server (uvicorn, nginx, anything that
  binds a port) as a Modal Function. Modal's edge proxies HTTP to the
  bound port; same Precreate→Create→Publish dance as `deploy_asgi/2`.

  The user's callable should *start* the server (e.g. fork uvicorn via
  `subprocess.Popen`) and not block — Modal waits for the port to bind,
  then takes over proxying. See
  `_runtime/user_code_imports.py:221` for the worker-side dispatch.

  ## Options

  #{NimbleOptions.docs(@common_deploy_opts ++ @web_server_extra)}
  """
  @spec deploy_web_server(GenServer.server(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def deploy_web_server(client, opts) do
    with {:ok, validated} <- validate_opts(opts, @common_deploy_opts ++ @web_server_extra) do
      webhook = %WebhookConfig{
        type: :WEBHOOK_TYPE_WEB_SERVER,
        requested_suffix: validated[:requested_suffix] || validated[:name],
        async_mode: :WEBHOOK_ASYNC_MODE_AUTO,
        requires_proxy_auth: validated[:requires_proxy_auth],
        web_server_port: validated[:web_server_port],
        web_server_startup_timeout: validated[:web_server_startup_timeout] * 1.0
      }

      do_deploy(client, validated, webhook)
    end
  end

  @doc "Like `deploy_web_server/2` but raises on error."
  @spec deploy_web_server!(GenServer.server(), keyword()) :: t()
  def deploy_web_server!(client, opts) do
    case deploy_web_server(client, opts) do
      {:ok, fn_struct} -> fn_struct
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── invoke / spawn / await ──────────────────────────────────────

  @doc """
  Invoke a deployed Function with positional + keyword arguments and
  wait for the result. The Elixir equivalent of Python's
  `func.remote(*args, **kwargs)`.

  Arguments are serialized via `Modal.Pickle` (Modal's wire format
  for function calls). The Python function receives them as a
  positional tuple + kwargs dict.

  ## Arguments

    * `client` — `Modal.Client.start_link/1` PID.
    * `func` — `%Modal.Function{}` from `deploy_*` or `get/4`.
    * `args` — list of positional arguments. Pickled as a tuple.
    * `kwargs` — map of keyword arguments. Pickled as a dict.
    * `opts` — `:timeout_secs` (default 60.0); how long to wait
      total. Server-side blocking polls are used internally.

  ## Returns

    * `{:ok, value}` — the decoded return value.
    * `{:error, %Modal.Error{kind: :function_failed}}` — the remote
      function raised an exception; `:metadata` has `:exception`
      and `:traceback`.
    * `{:error, %Modal.Error{kind: :timeout}}` — no output before
      the timeout.

  ## Example

      {:ok, web_fn} = Modal.Function.get(client, app, "compute")
      {:ok, 42} = Modal.Function.invoke(client, web_fn, [40, 2])
      {:ok, 21} = Modal.Function.invoke(client, web_fn, [], %{x: 7, y: 3})
  """
  @spec invoke(GenServer.server(), t(), [term()], map(), keyword()) ::
          {:ok, term()} | {:error, Modal.Error.t()}
  def invoke(client, %__MODULE__{} = func, args, kwargs \\ %{}, opts \\ []) do
    # invoke vs spawn differ in the FunctionMapRequest's invocation
    # type — SYNC tells the server "I'm waiting for this result
    # right now, optimize accordingly"; ASYNC means "I'll await
    # later." We use SYNC here.
    method_name = Keyword.get(opts, :method_name)

    with {:ok, call} <-
           do_dispatch(
             client,
             func,
             args,
             kwargs,
             :FUNCTION_CALL_INVOCATION_TYPE_SYNC,
             method_name
           ) do
      await(call, opts)
    end
  end

  @doc """
  Asynchronously invoke a Function. Returns a `%Modal.FunctionCall{}`
  immediately; pass it to `await/2` to get the result. The Elixir
  equivalent of Python's `func.spawn(*args, **kwargs)`.

  Useful for fan-out — `spawn` N calls in parallel and `await_all`
  the lot:

      calls =
        for i <- 1..8 do
          {:ok, call} = Modal.Function.spawn(client, work_fn, [i])
          call
        end

      results = Enum.map(calls, &Modal.Function.await!/1)
  """
  @spec spawn(GenServer.server(), t(), [term()], map(), keyword()) ::
          {:ok, Modal.FunctionCall.t()} | {:error, Modal.Error.t()}
  def spawn(client, %__MODULE__{} = func, args, kwargs \\ %{}, opts \\ []) do
    method_name = Keyword.get(opts, :method_name)

    # Generators require SYNC_LEGACY at spawn time — Modal's worker
    # uses this to route yielded values into the FunctionCallGetDataOut
    # stream rather than the standard output-polling path. Spawning
    # a generator with the default ASYNC silently returns 0 results.
    invocation_type =
      if Keyword.get(opts, :generator, false),
        do: :FUNCTION_CALL_INVOCATION_TYPE_SYNC_LEGACY,
        else: :FUNCTION_CALL_INVOCATION_TYPE_ASYNC

    do_dispatch(client, func, args, kwargs, invocation_type, method_name)
  end

  @doc false
  # Public-but-internal: lets Modal.Cls reuse the dispatch path with
  # a method_name set. Not part of the public API; signature may shift.
  def __dispatch__(client, func, args, kwargs, invocation_type, method_name) do
    do_dispatch(client, func, args, kwargs, invocation_type, method_name)
  end

  defp do_dispatch(
         client,
         %__MODULE__{id: function_id} = func,
         args,
         kwargs,
         invocation_type,
         method_name
       ) do
    # Modal's Python SDK serializes args as pickle((args_tuple, kwargs_dict))
    # — the worker unpacks `(args, kwargs) = pickle.loads(input.args)` and
    # calls `callable(*args, **kwargs)`. Match the wire shape exactly.
    #
    # Python kwargs are always string-keyed; auto-convert atom keys
    # so `%{c: 3}` works the way a caller expects.
    string_kwargs =
      for {k, v} <- kwargs, into: %{} do
        {if(is_atom(k), do: Atom.to_string(k), else: k), v}
      end

    args_pickled = Modal.Pickle.encode({List.to_tuple(args), string_kwargs})

    input =
      %FunctionInput{
        args_oneof: {:args, args_pickled},
        data_format: :DATA_FORMAT_PICKLE,
        final_input: true
      }
      |> maybe_put_method_name(method_name)

    request = %FunctionMapRequest{
      function_id: function_id,
      function_call_type: :FUNCTION_CALL_TYPE_UNARY,
      function_call_invocation_type: invocation_type,
      pipelined_inputs: [%FunctionPutInputsItem{idx: 0, input: input}]
    }

    with {:ok, resp} <- RPC.call(client, :FunctionMap, request) do
      {:ok,
       %Modal.FunctionCall{
         id: resp.function_call_id,
         function: func,
         client: client
       }}
    end
  end

  @doc """
  Wait for a `%Modal.FunctionCall{}` (from `spawn/4`) to complete.
  Uses Modal's server-side blocking await — no busy polling.

  ## Options

    * `:timeout_secs` (default 60.0) — total wall-clock budget.
  """
  @spec await(Modal.FunctionCall.t(), keyword()) ::
          {:ok, term()} | {:error, Modal.Error.t()}
  def await(%Modal.FunctionCall{} = call, opts \\ []) do
    total_timeout = Keyword.get(opts, :timeout_secs, 60.0)
    deadline = System.monotonic_time(:millisecond) + round(total_timeout * 1000)
    poll_await(call, deadline)
  end

  @doc "Like `await/2` but raises on error."
  @spec await!(Modal.FunctionCall.t(), keyword()) :: term()
  def await!(%Modal.FunctionCall{} = call, opts \\ []) do
    case await(call, opts) do
      {:ok, value} -> value
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Stream results from a generator function. Returns an `Enumerable`
  that yields each value the Python `yield`s back; halts when the
  worker emits `DATA_FORMAT_GENERATOR_DONE`.

  Pair with a function deployed via `generator: true`:

      # Python:  def chat(prompt):  yield from llm.stream(prompt)
      {:ok, gen_fn} = Modal.Function.get(client, app, "chat")
      {:ok, call} = Modal.Function.spawn(client, gen_fn, ["hello"])

      Modal.Function.stream(call)
      |> Enum.each(&IO.write/1)

  Remote failures — an exception raised inside the generator, or the
  function failing to start at all (e.g. an import error in its module)
  — surface as a raised `%Modal.Error{kind: :function_failed}` carrying
  the worker traceback, not as a silently-empty result. Wrap the
  consumption in `try` to handle them inline.

  ## Options

    * `:timeout_secs` (default 300.0) — total wall-clock budget for
      the whole stream. Each individual `FunctionGetOutputs` long-poll
      caps at 55s server-side.
  """
  @spec stream(Modal.FunctionCall.t(), keyword()) :: Enumerable.t()
  def stream(%Modal.FunctionCall{} = call, opts \\ []) do
    timeout = Keyword.get(opts, :timeout_secs, 300.0) |> round() |> Kernel.*(1000)

    # Generators use FunctionCallGetDataOut — a server-streaming RPC
    # that pushes one DataChunk per yielded value, plus a terminal
    # chunk with `data_format: DATA_FORMAT_GENERATOR_DONE` whose
    # payload deserializes to a GeneratorDone proto. This differs
    # from FunctionGetOutputs (which is what await/2 polls for
    # non-generator function calls). Caught by CPython source dive:
    # `_functions.py:1673` and `_utils/function_utils.py:436`.
    request = %FunctionCallGetDataRequest{
      call_info: {:function_call_id, call.id},
      last_index: 0
    }

    {:ok, {chunks, done?}} =
      RPC.stream_reduce(
        call.client,
        :FunctionCallGetDataOut,
        request,
        {[], false},
        &stream_reducer/2,
        timeout
      )

    # The data-out stream carries only the yielded values; the call's terminal
    # success/failure is delivered separately via FunctionGetOutputs (CPython's
    # `run_generator` at `_functions.py:333` merges the data stream with a
    # `poll_function` call that raises on failure). Without consulting that, a
    # generator that fails to import or raises — yielding nothing — surfaces as
    # a silent, partial/empty list.
    #
    # A clean run *may* end with a recognizable GENERATOR_DONE terminator
    # chunk, but live the stream often just EOFs after the data chunks, so
    # `done?` is unreliable as a success signal. We treat it only as a
    # definite-success fast path (skip the poll); otherwise poll the terminal
    # result and raise *only* if it reports failure (see
    # `raise_on_generator_failure!` — it checks status, never decodes).
    unless done?, do: raise_on_generator_failure!(call)

    Enum.reverse(chunks)
  end

  @doc """
  Spawn + stream in one call. The sync convenience wrapper for
  generator functions: send the inputs, return a stream of yielded
  values. Same options as `stream/2`.

      Modal.Function.invoke_stream(client, gen_fn, ["hello"])
      |> Enum.each(&IO.write/1)
  """
  @spec invoke_stream(GenServer.server(), t(), [term()], map(), keyword()) :: Enumerable.t()
  def invoke_stream(client, %__MODULE__{} = func, args, kwargs \\ %{}, opts \\ []) do
    # Generators specifically require SYNC_LEGACY (NOT SYNC) — Modal
    # uses the legacy invocation type to flag "this caller plans to
    # consume via the data-out stream, not poll FunctionGetOutputs."
    case do_dispatch(
           client,
           func,
           args,
           kwargs,
           :FUNCTION_CALL_INVOCATION_TYPE_SYNC_LEGACY,
           nil
         ) do
      {:ok, call} -> stream(call, opts)
      {:error, err} -> raise err
    end
  end

  # Reducer called once per DataChunk on the streaming RPC. The accumulator is
  # `{values, done?}` — `done?` records whether we saw the GENERATOR_DONE
  # terminator, which `stream/2` uses to tell a clean finish from a stream that
  # closed because the generator failed.
  defp stream_reducer(%{data_format: :DATA_FORMAT_GENERATOR_DONE}, {acc, _done}) do
    {:halt, {acc, true}}
  end

  defp stream_reducer(%{data_oneof: {:data, bytes}}, {acc, done}) do
    {:cont, {[Modal.Pickle.decode!(bytes) | acc], done}}
  end

  defp stream_reducer(%{data_oneof: {:data_blob_id, blob_id}}, _acc) do
    # Blob-backed chunks (large yielded values stored out-of-band) need a
    # separate download path that isn't implemented yet. Raise rather than
    # silently dropping the value — a gappy generator result is worse than
    # a clear failure. Matches `await/2`'s `{:error, :function_failed}` for
    # blob results, and the documented raise-on-error contract of
    # `stream/2` (remote exceptions surface mid-stream as a raise).
    raise Modal.Error.function_failed(
            "generator yielded a blob-backed chunk (#{blob_id}); " <>
              "blob-fetch not yet implemented"
          )
  end

  defp stream_reducer(_chunk, acc), do: {:cont, acc}

  # A generator's yielded values come over the data-out stream, but its
  # terminal pass/fail is delivered via FunctionGetOutputs — same as a plain
  # call. Called only when the data-out stream ended *without* a
  # GENERATOR_DONE terminator (the generator didn't finish cleanly): poll the
  # terminal result and re-raise the function's failure (with traceback)
  # rather than letting `stream/2` hand back a partial/empty list silently.
  # `clear_on_success: false` mirrors CPython's `poll_function` for
  # generators — a non-destructive read of the result.
  defp raise_on_generator_failure!(call) do
    request = %FunctionGetOutputsRequest{
      function_call_id: call.id,
      max_values: 1,
      timeout: 5.0,
      requested_at: :os.system_time(:second) * 1.0,
      last_entry_id: "0-0",
      clear_on_success: false
    }

    case RPC.call_no_retry(call.client, :FunctionGetOutputs, request, 10_000) do
      {:ok, %{outputs: [%{result: %{status: :GENERIC_STATUS_FAILURE} = result} | _]}} ->
        raise Modal.Error.function_failed(result.exception || "(no message)", result.traceback)

      _ ->
        # Success / terminated / no result yet / transport blip. We inspect
        # only the terminal *status* — a successful generator's result carries
        # a `GeneratorDone` protobuf, not a pickled value, so decoding it (as
        # `handle_output` does) would raise on non-pickle bytes. We only need
        # to distinguish an explicit failure from everything else.
        :ok
    end
  end

  defp poll_await(call, deadline), do: poll_await(call, deadline, nil)

  defp poll_await(call, deadline, last_unfinished) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      # Out of time. Disambiguate using the last poll's unfinished-input
      # count (mirrors CPython `poll_function`, `_functions.py:323`): no
      # inputs still running ⇒ the call's output expired or its input was
      # lost (worker preemption, no retry); otherwise it genuinely just
      # didn't finish in time. A distinct `:output_expired` beats masking a
      # gone call as a generic timeout.
      case last_unfinished do
        0 -> {:error, Modal.Error.output_expired()}
        _ -> {:error, Modal.Error.timeout()}
      end
    else
      # Server-side blocking long-poll. Cap at 55s so the client RPC
      # timeout doesn't beat the server's own deadline.
      poll_timeout = min(remaining_ms / 1000.0, 55.0)

      request = %FunctionGetOutputsRequest{
        function_call_id: call.id,
        max_values: 1,
        timeout: poll_timeout,
        requested_at: :os.system_time(:second) * 1.0,
        # Modal's server requires last_entry_id for ASYNC (spawn-flow)
        # polling — it errors with INVALID_ARGUMENT on empty string.
        # CPython client uses "0-0" as the universal initial cursor
        # (`_functions.py:237`); SYNC polling tolerates it too.
        last_entry_id: "0-0",
        # Without clear_on_success, Modal keeps the output around for
        # repeat reads; we want the standard "consume once" semantics.
        clear_on_success: true
      }

      # call_no_retry: long-poll DEADLINE_EXCEEDED means "no output
      # yet, poll again" — already handled by our outer loop. Letting
      # the RPC layer also retry would compound the wait time.
      case RPC.call_no_retry(
             call.client,
             :FunctionGetOutputs,
             request,
             round(poll_timeout * 1000) + 5_000
           ) do
        {:ok, %{outputs: [], num_unfinished_inputs: unfinished}} ->
          # No result yet — long-poll again, remembering whether any input
          # is still running so the deadline branch can tell a genuine
          # timeout from a call whose output has expired / been lost.
          poll_await(call, deadline, unfinished)

        {:ok, %{outputs: [output | _]}} ->
          handle_output(output)

        {:error, %Modal.Error{}} = err ->
          err
      end
    end
  end

  defp handle_output(%{result: nil}) do
    {:error, Modal.Error.function_failed("output missing result field")}
  end

  defp handle_output(%{result: result}) do
    case result.status do
      :GENERIC_STATUS_SUCCESS ->
        case result.data_oneof do
          {:data, bytes} ->
            {:ok, Modal.Pickle.decode!(bytes)}

          {:data_blob_id, blob_id} ->
            {:error,
             Modal.Error.function_failed(
               "result stored in blob #{blob_id}; blob-fetch not yet implemented"
             )}

          nil ->
            {:ok, nil}
        end

      :GENERIC_STATUS_FAILURE ->
        {:error,
         Modal.Error.function_failed(result.exception || "(no message)", result.traceback)}

      :GENERIC_STATUS_TIMEOUT ->
        {:error, Modal.Error.timeout()}

      other ->
        {:error,
         Modal.Error.function_failed("unexpected function status: #{other}", result.traceback)}
    end
  end

  # ── get ─────────────────────────────────────────────────────────

  @doc """
  Look up a deployed Function by app + name. Returns the `%Modal.Function{}`
  with `:id` and `:web_url` populated.

  ## Options

    * `:environment_name` — Modal environment (default: workspace default).
  """
  @spec get(GenServer.server(), Modal.App.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def get(client, %Modal.App{} = app, name, opts \\ []) do
    request = %FunctionGetRequest{
      app_name: app.name || "",
      object_tag: name,
      environment_name: Keyword.get(opts, :environment_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :FunctionGet, request) do
      web_url = resp.handle_metadata && resp.handle_metadata.web_url

      {:ok,
       %__MODULE__{
         id: resp.function_id,
         name: name,
         web_url: web_url,
         app: app
       }}
    end
  end

  # ── Internal: Precreate → Create → Publish ─────────────────────

  defp do_deploy(client, validated, webhook) do
    app = validated[:app]
    name = validated[:name]
    callable = validated[:callable] || name

    # Webhook functions need DATA_FORMAT_ASGI to flip Modal's edge
    # into HTTP↔ASGI bridging. Non-webhook functions use Modal's
    # default function-call formats (PICKLE/CBOR), expressed as no
    # explicit override.
    {input_formats, output_formats} =
      if webhook do
        {@asgi_input_formats, @asgi_output_formats}
      else
        {[], []}
      end

    function_type =
      if validated[:generator],
        do: :FUNCTION_TYPE_GENERATOR,
        else: :FUNCTION_TYPE_FUNCTION

    precreate_req = %FunctionPrecreateRequest{
      app_id: app.id,
      function_name: name,
      function_type: function_type,
      webhook_config: webhook,
      supported_input_formats: input_formats,
      supported_output_formats: output_formats
    }

    with {:ok, pre_resp} <- RPC.call(client, :FunctionPrecreate, precreate_req),
         function_id = pre_resp.function_id,
         function_def = build_function(validated, callable, webhook, app),
         create_req = %FunctionCreateRequest{
           function: function_def,
           app_id: app.id,
           existing_function_id: function_id
         },
         {:ok, create_resp} <- RPC.call(client, :FunctionCreate, create_req),
         {:ok, _publish} <- maybe_publish(client, validated, app, name, function_id) do
      web_url =
        (create_resp.handle_metadata && create_resp.handle_metadata.web_url) ||
          (create_resp.function && create_resp.function.web_url)

      {:ok, %__MODULE__{id: function_id, name: name, web_url: web_url, app: app}}
    end
  end

  defp maybe_publish(client, validated, app, name, function_id) do
    if Keyword.get(validated, :publish, true) do
      Modal.App.publish(client, app, function_ids: %{name => function_id})
    else
      {:ok, :skipped}
    end
  end

  defp build_function(opts, callable, webhook, app) do
    {input_formats, output_formats} =
      if webhook do
        {@asgi_input_formats, @asgi_output_formats}
      else
        {[], []}
      end

    function_type =
      if opts[:generator],
        do: :FUNCTION_TYPE_GENERATOR,
        else: :FUNCTION_TYPE_FUNCTION

    base = %Function{
      module_name: opts[:module],
      function_name: callable,
      image_id: opts[:image_id],
      app_name: app.name || "",
      definition_type: :DEFINITION_TYPE_FILE,
      function_type: function_type,
      webhook_config: webhook,
      supported_input_formats: input_formats,
      supported_output_formats: output_formats,
      # Required for the 2024.10+ image builder line — Modal's worker
      # mounts its own client deps into the container at runtime rather
      # than expecting them in the user's image. Matches Python SDK's
      # behaviour (_functions.py:957-959).
      mount_client_dependencies: true,
      _experimental_concurrent_cancellations: true,
      secret_ids: opts[:secret_ids],
      timeout_secs: opts[:timeout_secs],
      task_idle_timeout_secs: opts[:idle_timeout_secs]
    }

    base
    |> maybe_put(:schedule, build_schedule(opts[:schedule]))
    |> maybe_put(:target_concurrent_inputs, opts[:target_concurrent_inputs])
    |> maybe_put(:max_concurrent_inputs, opts[:max_concurrent_inputs])
    |> maybe_put(:warm_pool_size, opts[:min_containers])
    |> maybe_put(:retry_policy, build_retry_policy(opts[:retries]))
    |> maybe_put(:resources, build_resources(opts))
    |> maybe_put(:i6pn_enabled, opts[:i6pn] || nil)
  end

  defp build_resources(opts) do
    gpu = build_gpu_config(opts[:gpu], opts[:gpu_count] || 1)
    memory = opts[:memory_mb] || 0
    cpu = opts[:cpu_millis] || 0
    disk = opts[:disk_mb] || 0

    if gpu || memory > 0 || cpu > 0 || disk > 0 do
      %Modal.Client.Resources{
        memory_mb: memory,
        milli_cpu: cpu,
        ephemeral_disk_mb: disk,
        gpu_config: gpu
      }
    end
  end

  defp build_gpu_config(nil, _count), do: nil
  defp build_gpu_config(type, count), do: %Modal.Client.GPUConfig{gpu_type: type, count: count}

  defp maybe_put(struct, _key, nil), do: struct
  defp maybe_put(struct, key, value), do: Map.put(struct, key, value)

  defp maybe_put_method_name(input, nil), do: input
  defp maybe_put_method_name(input, name), do: %{input | method_name: name}

  defp build_schedule(nil), do: nil

  defp build_schedule({:period, period_opts}) when is_list(period_opts) do
    %Schedule{
      schedule_oneof:
        {:period,
         %Schedule.Period{
           years: Keyword.get(period_opts, :years, 0),
           months: Keyword.get(period_opts, :months, 0),
           weeks: Keyword.get(period_opts, :weeks, 0),
           days: Keyword.get(period_opts, :days, 0),
           hours: Keyword.get(period_opts, :hours, 0),
           minutes: Keyword.get(period_opts, :minutes, 0),
           seconds: Keyword.get(period_opts, :seconds, 0) * 1.0
         }}
    }
  end

  defp build_schedule({:cron, expr}) when is_binary(expr) do
    %Schedule{schedule_oneof: {:cron, %Schedule.Cron{cron_string: expr}}}
  end

  defp build_schedule({:cron, expr, opts}) when is_binary(expr) and is_list(opts) do
    %Schedule{
      schedule_oneof:
        {:cron,
         %Schedule.Cron{
           cron_string: expr,
           timezone: Keyword.get(opts, :timezone, "")
         }}
    }
  end

  defp build_retry_policy(nil), do: nil

  defp build_retry_policy(n) when is_integer(n) and n >= 0 do
    # Modal Python SDK's default `modal.Retries` policy: 1s initial,
    # 60s max, backoff coefficient 2.0. Match it.
    %FunctionRetryPolicy{
      retries: n,
      initial_delay_ms: 1_000,
      max_delay_ms: 60_000,
      backoff_coefficient: 2.0
    }
  end

  # NimbleOptions custom validator for the `:schedule` option.
  @doc false
  def validate_schedule({:period, opts}) when is_list(opts), do: {:ok, {:period, opts}}
  def validate_schedule({:cron, expr}) when is_binary(expr), do: {:ok, {:cron, expr}}

  def validate_schedule({:cron, expr, opts}) when is_binary(expr) and is_list(opts),
    do: {:ok, {:cron, expr, opts}}

  def validate_schedule(other),
    do:
      {:error,
       "expected {:period, opts} | {:cron, expr} | {:cron, expr, opts}, got #{inspect(other)}"}

  defp validate_opts(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = err} -> {:error, Modal.Error.validation(err)}
    end
  end

  # ── Inspect ─────────────────────────────────────────────────────

  defimpl Inspect do
    def inspect(%Modal.Function{} = fn_struct, _opts) do
      "#Modal.Function<id: #{fn_struct.id}, name: #{inspect(fn_struct.name)}, " <>
        "url: #{inspect(fn_struct.web_url)}>"
    end
  end
end
