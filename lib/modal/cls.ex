defmodule Modal.Cls do
  @moduledoc """
  Modal Classes — stateful container deployments. The canonical
  primitive for ML workloads where boot cost is high (load a model,
  open a pool, warm a cache) and you want that cost amortized
  across many subsequent method invocations.

  ## Concept

  A Modal Class is a Python class whose lifecycle Modal manages:

      import modal

      class LlamaServer:
          @modal.enter()
          def boot(self):
              self.model = load_llama()         # ~30s, runs once per container

          @modal.exit()
          def shutdown(self):
              self.model.cleanup()

          def predict(self, prompt: str) -> str:
              return self.model.generate(prompt)

          def embed(self, text: str) -> list[float]:
              return self.model.embed(text)

  Modal:
    * Spins a container up on demand (or keeps `:min_containers`
      warm).
    * Instantiates the class **once per container** — `__init__` +
      `@modal.enter()` run on boot.
    * Routes subsequent `invoke`s to method calls on that instance.
    * Invokes `@modal.exit()` on shutdown.

  From Elixir, deploy the class once and invoke methods like
  functions:

      {:ok, server} =
        Modal.Cls.deploy(client,
          app: app,
          name: "llama",
          image_id: image_id,
          module: "entry",
          callable: "LlamaServer",
          method_names: ["predict", "embed"],
          min_containers: 1,
          gpu: "A100"
        )

      {:ok, "Once upon a time…"} =
        Modal.Cls.invoke(client, server, "predict", ["Once upon"])

  ## Why a separate primitive

  `Modal.Function` is stateless — every invocation may hit a fresh
  container, so per-request bootstrap is expensive. `Modal.Cls` is
  the right primitive when:

    * Boot cost > per-request cost (loading a 7B model, opening a
      DB pool, warming a JIT).
    * State should outlive a single call (in-process caches,
      conversation memory).
    * You want method-level dispatch (`predict`, `embed`, `health`
      on the same warm container).

  Under the hood, a class is exactly one Modal Function with
  `is_class: true` + `method_definitions`, plus a separate
  `ClassCreate` registration. Both get registered in `AppPublish`
  under the same tag.

  ## Method invocation = `Modal.Function.invoke` with a method_name

  `invoke/6` / `spawn/5` / `await/2` mirror `Modal.Function`'s
  equivalents and reuse the same FunctionMap protocol — the only
  difference is the `method_name` field on `FunctionInput`, which
  tells Modal's worker which method on the class instance to call.
  """

  alias Modal.RPC

  alias Modal.Client.{
    AutoscalerSettings,
    ClassCreateRequest,
    ClassGetRequest,
    ClassParameterInfo,
    Function,
    FunctionCreateRequest,
    FunctionPrecreateRequest,
    FunctionSchema,
    GenericPayloadType,
    GPUConfig,
    MethodDefinition,
    ObjectDependency,
    Resources,
    WebhookConfig
  }

  defstruct [:id, :name, :function_id, :app, :methods]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          function_id: String.t(),
          app: Modal.App.t(),
          methods: [String.t()]
        }

  # Common Cls deploy options — subset of Modal.Function's, minus
  # webhook-specific ones (classes are not webhooks).
  @deploy_opts [
    app: [type: {:struct, Modal.App}, required: true],
    image_id: [type: :string, required: true],
    module: [
      type: :string,
      required: true,
      doc: "Python module containing the class (e.g. `\"entry\"` for `/root/entry.py`)."
    ],
    callable: [
      type: :string,
      required: true,
      doc: """
      Name of the Python class itself (e.g. `\"LlamaServer\"`). Also the
      app-level tag — Modal registers classes under their class name.
      """
    ],
    method_names: [
      type: {:list, :string},
      required: true,
      doc: """
      List of method names callers will be allowed to invoke. Modal
      uses this for type-checking and dashboard surfacing; the
      worker dispatches at runtime by `method_name` on
      `FunctionInput`, so methods not in this list still work but
      won't show up in metadata.
      """
    ],
    secret_ids: [type: {:list, :string}, default: []],
    timeout_secs: [type: :pos_integer, default: 300],
    idle_timeout_secs: [type: :pos_integer, default: 300],
    target_concurrent_inputs: [type: :pos_integer],
    max_concurrent_inputs: [type: :pos_integer],
    min_containers: [type: :non_neg_integer],
    retries: [type: :non_neg_integer],
    gpu: [
      type: :string,
      doc: """
      GPU type — `"T4"`, `"A10G"`, `"A100"`, `"A100-80GB"`, `"L4"`,
      `"L40S"`, `"H100"`, `"H100!"`, `"H200"`, `"B200"`. The reason
      `Modal.Cls` exists: load a model in `@modal.enter` once,
      amortize across many invocations.
      """
    ],
    gpu_count: [type: :pos_integer, default: 1, doc: "GPUs per container."],
    memory_mb: [type: :non_neg_integer],
    cpu_millis: [type: :non_neg_integer],
    disk_mb: [type: :non_neg_integer],
    i6pn: [
      type: :boolean,
      default: false,
      doc: "Enable Modal's internal IPv6 mesh for peer-to-peer between containers."
    ],
    publish: [type: :boolean, default: true]
  ]

  # ── deploy ──────────────────────────────────────────────────────

  @doc """
  Deploy a Modal Class. Mirrors `Modal.Function.deploy_function/2`
  but emits the class-shaped wire form (one class-Function +
  ClassCreate, both registered in AppPublish under the same tag).

  ## Options

  #{NimbleOptions.docs(@deploy_opts)}

  ## Returns

  `{:ok, %Modal.Cls{}}` with the class id, the underlying Function
  id, and the list of method names, or `{:error, %Modal.Error{}}`.
  """
  @spec deploy(GenServer.server(), keyword()) :: {:ok, t()} | {:error, Modal.Error.t()}
  def deploy(client, opts) do
    with {:ok, validated} <- validate(opts) do
      do_deploy(client, validated)
    end
  end

  @doc "Like `deploy/2` but raises on error."
  @spec deploy!(GenServer.server(), keyword()) :: t()
  def deploy!(client, opts) do
    case deploy(client, opts) do
      {:ok, cls} -> cls
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── invoke / spawn / await ──────────────────────────────────────

  @doc """
  Synchronously invoke a method on a deployed class. Same shape as
  `Modal.Function.invoke/5` plus a method name.

      {:ok, embedding} =
        Modal.Cls.invoke(client, server, "embed", ["hello world"])
  """
  @spec invoke(GenServer.server(), t(), String.t(), [term()], map(), keyword()) ::
          {:ok, term()} | {:error, Modal.Error.t()}
  def invoke(client, %__MODULE__{} = cls, method, args, kwargs \\ %{}, opts \\ []) do
    enforce_known_method!(cls, method)

    underlying = underlying_function(cls)

    with {:ok, call} <-
           Modal.Function.__dispatch__(
             client,
             underlying,
             args,
             kwargs,
             :FUNCTION_CALL_INVOCATION_TYPE_SYNC,
             method
           ) do
      Modal.Function.await(call, opts)
    end
  end

  @doc """
  Asynchronously invoke a method; returns a `%Modal.FunctionCall{}`
  for later `Modal.Function.await/2`. Fan-out friendly.
  """
  @spec spawn(GenServer.server(), t(), String.t(), [term()], map()) ::
          {:ok, Modal.FunctionCall.t()} | {:error, Modal.Error.t()}
  def spawn(client, %__MODULE__{} = cls, method, args, kwargs \\ %{}) do
    enforce_known_method!(cls, method)

    Modal.Function.__dispatch__(
      client,
      underlying_function(cls),
      args,
      kwargs,
      :FUNCTION_CALL_INVOCATION_TYPE_ASYNC,
      method
    )
  end

  # ── get ─────────────────────────────────────────────────────────

  @doc """
  Look up a deployed class by app + tag. Returns a `%Modal.Cls{}`
  with `:id`, `:function_id`, and `:methods` populated.
  """
  @spec get(GenServer.server(), Modal.App.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def get(client, %Modal.App{} = app, name, opts \\ []) do
    request = %ClassGetRequest{
      app_name: app.name || "",
      object_tag: name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      only_class_function: true
    }

    with {:ok, resp} <- RPC.call(client, :ClassGet, request) do
      meta = resp.handle_metadata
      function_id = (meta && meta.class_function_id) || ""
      method_names = (meta && Enum.map(meta.methods, & &1.function_name)) || []

      {:ok,
       %__MODULE__{
         id: resp.class_id,
         name: name,
         function_id: function_id,
         app: app,
         methods: method_names
       }}
    end
  end

  # ── Internal ────────────────────────────────────────────────────

  defp do_deploy(client, validated) do
    app = validated[:app]
    callable = validated[:callable]
    # The class's app-level tag IS its callable name — Modal doesn't
    # support a separate alias here.
    name = callable
    method_names = validated[:method_names]

    # Modal's wire convention: the underlying class-function's name
    # is `<ClassName>.*` (literal `.*` — the wildcard slot for "all
    # methods dispatch through this one Function"). Each method's
    # `MethodDefinition.function_name` is `<ClassName>.<method>`.
    # Sending plain `<ClassName>` here surfaces as opaque
    # `gRPC INTERNAL: please contact support@modal.com`.
    class_function_name = "#{callable}.*"

    # Each method needs the full CPython shape: function_schema +
    # both PICKLE and CBOR in supported_input/output_formats. Verified
    # via wire-dump of a successful `@app.cls` deploy.
    method_defs =
      method_names
      |> Enum.map(fn m ->
        {m,
         %MethodDefinition{
           function_name: "#{callable}.#{m}",
           function_type: :FUNCTION_TYPE_FUNCTION,
           webhook_config: %WebhookConfig{},
           function_schema: %FunctionSchema{
             schema_type: :FUNCTION_SCHEMA_V1,
             return_type: %GenericPayloadType{base_type: :PARAM_TYPE_UNKNOWN}
           },
           supported_input_formats: [:DATA_FORMAT_PICKLE, :DATA_FORMAT_CBOR],
           supported_output_formats: [:DATA_FORMAT_PICKLE, :DATA_FORMAT_CBOR]
         }}
      end)
      |> Map.new()

    precreate_req = %FunctionPrecreateRequest{
      app_id: app.id,
      function_name: class_function_name,
      function_type: :FUNCTION_TYPE_FUNCTION,
      # CPython sends method_definitions on the Precreate too, so the
      # server can reserve typed method slots before FunctionCreate
      # lands. Without this, the server's class-validator chokes.
      method_definitions: method_defs
    }

    with {:ok, pre_resp} <-
           tagged(:precreate, RPC.call(client, :FunctionPrecreate, precreate_req)),
         function_id = pre_resp.function_id,
         function_def = build_class_function(validated, callable, method_defs, app),
         create_req = %FunctionCreateRequest{
           function: function_def,
           app_id: app.id,
           existing_function_id: function_id
         },
         {:ok, _create_resp} <- tagged(:create, RPC.call(client, :FunctionCreate, create_req)),
         {:ok, class_resp} <-
           tagged(
             :class_create,
             # CPython sends ClassCreate with ONLY `app_id` +
             # `only_class_function: true` — no `methods` list. The
             # method metadata flows in via the class-function's
             # `method_definitions` map, not via ClassCreate. Sending
             # methods here surfaces as opaque INTERNAL errors.
             RPC.call(client, :ClassCreate, %ClassCreateRequest{
               app_id: app.id,
               only_class_function: true
             })
           ),
         {:ok, _publish} <-
           tagged(
             :publish,
             maybe_publish(client, validated, app, name, function_id, class_resp.class_id)
           ) do
      {:ok,
       %__MODULE__{
         id: class_resp.class_id,
         name: name,
         function_id: function_id,
         app: app,
         methods: method_names
       }}
    end
  end

  defp tagged(stage, {:error, %Modal.Error{} = err}) do
    {:error, %{err | message: "[#{stage}] #{err.message}"}}
  end

  defp tagged(_stage, other), do: other

  defp build_class_function(opts, callable, method_defs, app) do
    base = %Function{
      module_name: opts[:module],
      function_name: "#{callable}.*",
      implementation_name: "#{callable}.*",
      image_id: opts[:image_id],
      app_name: app.name || "",
      definition_type: :DEFINITION_TYPE_FILE,
      function_type: :FUNCTION_TYPE_FUNCTION,
      is_class: true,
      method_definitions: method_defs,
      method_definitions_set: true,
      # PICKLE is what CPython's `@app.cls` decorator sends by
      # default (verified via wire dump). PROTO format is for
      # annotation-style classes that use `modal.parameter()` —
      # less common.
      class_parameter_info: %ClassParameterInfo{
        format: :PARAM_SERIALIZATION_FORMAT_PICKLE,
        schema: []
      },
      webhook_config: %WebhookConfig{},
      supported_input_formats: [],
      supported_output_formats: [],
      mount_client_dependencies: true,
      _experimental_concurrent_cancellations: true,
      secret_ids: opts[:secret_ids],
      timeout_secs: opts[:timeout_secs],
      task_idle_timeout_secs: opts[:idle_timeout_secs],
      # CPython sends startup_timeout_secs equal to timeout_secs by
      # default; the server rejects deploys missing it.
      startup_timeout_secs: opts[:timeout_secs],
      # Even empty, these structs MUST be present — the server reads
      # them unconditionally during validation. GPU + memory + disk
      # overrides slot into the same Resources struct.
      resources: build_resources(opts),
      autoscaler_settings: %AutoscalerSettings{},
      # The image is a required object dependency — CPython adds
      # this automatically from the function's image binding.
      object_dependencies: [%ObjectDependency{object_id: opts[:image_id]}]
    }

    base
    |> maybe_put(:target_concurrent_inputs, opts[:target_concurrent_inputs])
    |> maybe_put(:max_concurrent_inputs, opts[:max_concurrent_inputs])
    |> maybe_put(:warm_pool_size, opts[:min_containers])
    |> maybe_put(:i6pn_enabled, opts[:i6pn] || nil)
  end

  defp maybe_put(struct, _key, nil), do: struct
  defp maybe_put(struct, key, value), do: Map.put(struct, key, value)

  # Always returns a Resources struct (with empty gpu_config when no
  # GPU requested) — Modal's class-function validator rejects deploys
  # missing the resources field. User overrides slot in via :gpu /
  # :memory_mb / :cpu_millis / :disk_mb.
  defp build_resources(opts) do
    gpu =
      case opts[:gpu] do
        nil -> %GPUConfig{}
        type -> %GPUConfig{gpu_type: type, count: opts[:gpu_count] || 1}
      end

    %Resources{
      memory_mb: opts[:memory_mb] || 0,
      milli_cpu: opts[:cpu_millis] || 0,
      ephemeral_disk_mb: opts[:disk_mb] || 0,
      gpu_config: gpu
    }
  end

  defp maybe_publish(client, validated, app, _name, function_id, class_id) do
    callable = validated[:callable]

    if Keyword.get(validated, :publish, true) do
      # CPython's AppPublish for class deploys uses TWO different
      # key conventions in the same call:
      #   - `function_ids` keyed by `<Callable>.*` (the class-function's
      #     wildcard name, matching what we sent in FunctionPrecreate)
      #   - `class_ids` keyed by `<Callable>` (the class's lookup tag,
      #     no suffix)
      # Mixing these up returns opaque INTERNAL errors from the server.
      Modal.App.publish(client, app,
        function_ids: %{"#{callable}.*" => function_id},
        class_ids: %{callable => class_id}
      )
    else
      {:ok, :skipped}
    end
  end

  defp underlying_function(%__MODULE__{function_id: fid, name: name, app: app}) do
    %Modal.Function{id: fid, name: name, web_url: nil, app: app}
  end

  defp enforce_known_method!(%__MODULE__{methods: methods, name: name}, method) do
    if methods != [] and method not in methods do
      raise ArgumentError,
            "Modal.Cls #{inspect(name)} has methods #{inspect(methods)}; " <>
              "got call for unknown method #{inspect(method)}"
    end
  end

  defp validate(opts) do
    case NimbleOptions.validate(opts, @deploy_opts) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = err} -> {:error, Modal.Error.validation(err)}
    end
  end

  # ── Inspect ─────────────────────────────────────────────────────

  defimpl Inspect do
    def inspect(%Modal.Cls{} = cls, _opts) do
      "#Modal.Cls<id: #{cls.id}, name: #{inspect(cls.name)}, " <>
        "methods: #{inspect(cls.methods)}>"
    end
  end
end
