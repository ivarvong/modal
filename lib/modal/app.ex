defmodule Modal.App do
  @moduledoc """
  Modal App management.

  An **App** is Modal's top-level namespace: a stable name that groups
  the sandboxes, secrets, images, volumes, and queues that belong to a
  single deployment. Names are unique per environment; two clients
  calling `lookup/3` with the same name resolve to the same `app_id`
  (the second caller's `create-if-missing` is a no-op).

  Apps don't run code themselves — they're just the container that other
  Modal objects attach to. You'll typically call `Modal.App.lookup/3`
  once near process start and then thread the returned `%Modal.App{}`
  through to `Modal.Sandbox.create/2`, `Modal.Secret.create/2`,
  `Modal.Image.get_or_create/3`, etc., via the `:app` option.

      {:ok, app} = Modal.App.lookup(client, "my-service")

      {:ok, image, _} = Modal.Image.get_or_create(client, dockerfile, app: app)
      secret           = Modal.Secret.create!(client, app: app, name: "...", env: %{})
      {:ok, sandbox}   = Modal.Sandbox.create(client, app: app, image_id: image)

  See [Modal's App docs](https://modal.com/docs/guide/apps) for the
  product-level concept.
  """

  alias Modal.RPC

  defstruct [:id, :name, :client]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          client: GenServer.server()
        }

  @doc """
  Look up a Modal App by name, creating it if it doesn't exist.

  Returns `{:ok, %Modal.App{}}`. Pass the struct to any function that
  accepts an `:app` option — it carries the `:id` plus the `:client`
  reference so call sites don't have to thread both.

      {:ok, app} = Modal.App.lookup(client, "my-service")
      app.id      #=> "ap-abc123"
      app.name    #=> "my-service"

  Use `:environment_name` to look up an app in a non-default environment.
  """
  @spec lookup(GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def lookup(client, app_name, opts \\ []) do
    request = %Modal.Client.AppGetOrCreateRequest{
      app_name: app_name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
    }

    with {:ok, resp} <- RPC.call(client, :AppGetOrCreate, request) do
      {:ok, %__MODULE__{id: resp.app_id, name: app_name, client: client}}
    end
  end

  # ── Deploy / publish ────────────────────────────────────────────

  @publish_opts [
    function_ids: [
      type: {:map, :string, :string},
      default: %{},
      doc:
        "Map of `{tag => function_id}` to register in the app's routing " <>
          "table. `tag` becomes the function's URL slug on `*.modal.run`."
    ],
    class_ids: [
      type: {:map, :string, :string},
      default: %{},
      doc:
        "Map of `{tag => class_id}` for `Modal.Cls`-deployed classes. " <>
          "Registered alongside `:function_ids` (a class also has an " <>
          "underlying class-function entry under the same tag)."
    ],
    state: [
      type: {:in, [:deployed, :stopped]},
      default: :deployed,
      doc:
        "App state after publish. `:deployed` makes URLs live and persistent; " <>
          "`:stopped` halts all running containers for this app."
    ],
    deployment_tag: [type: :string, default: ""]
  ]

  @doc """
  Publish the app — registers the given functions in the app's routing
  table and flips the app to `:deployed`.

  This is the step that makes a `Modal.Function`'s `web_url` actually
  routable. Pre-publish, `FunctionCreate` returns a URL but hitting it
  yields `modal-http: invalid function call`. Most callers won't invoke
  this directly — `Modal.Function.deploy_asgi/2` calls it for you as
  the third RPC in the deploy dance.

  ## Options

    * `:function_ids` (required) — `%{"tag" => "fu-..."}` map.
      Each tag becomes the function's URL subdomain segment:
      `<workspace>--<app>-<tag>.modal.run`.
    * `:state` — `:deployed` (default) or `:stopped`.
    * `:deployment_tag` — optional human label for the deployment record.

  ## Returns

  `{:ok, %{url: String.t(), deployed_at: float()}}` on success — `url`
  is the Modal dashboard URL for the app, NOT the function URLs (those
  come back from `FunctionCreate`).
  """
  @spec publish(GenServer.server(), t(), keyword()) ::
          {:ok, %{url: String.t(), deployed_at: float()}} | {:error, Modal.Error.t()}
  def publish(client, %__MODULE__{} = app, opts \\ []) do
    case NimbleOptions.validate(opts, @publish_opts) do
      {:ok, validated} ->
        do_publish(client, app, validated)

      {:error, %NimbleOptions.ValidationError{} = err} ->
        {:error, Modal.Error.validation(err)}
    end
  end

  defp do_publish(client, app, validated) do
    app_state =
      case validated[:state] do
        :deployed -> :APP_STATE_DEPLOYED
        :stopped -> :APP_STATE_STOPPED
      end

    request = %Modal.Client.AppPublishRequest{
      app_id: app.id,
      name: app.name || "",
      app_state: app_state,
      function_ids: validated[:function_ids],
      class_ids: validated[:class_ids],
      deployment_tag: validated[:deployment_tag]
    }

    with {:ok, resp} <- RPC.call(client, :AppPublish, request) do
      {:ok, %{url: resp.url, deployed_at: resp.deployed_at}}
    end
  end

  # ── Internal helpers ────────────────────────────────────────────
  #
  # `resolve_app_id/1` is the single place every other module
  # (Sandbox, Secret, Image, …) consults to translate the caller's
  # `:app`-or-`:app_id` keyword into a plain `app_id` string. Keep
  # this logic here so the supported shapes stay in lockstep.

  @doc false
  @spec resolve_app_id(keyword()) :: {:ok, String.t(), keyword()} | {:error, Modal.Error.t()}
  def resolve_app_id(opts) do
    {app, opts} = Keyword.pop(opts, :app)
    {app_id, opts} = Keyword.pop(opts, :app_id)

    case {app, app_id} do
      {nil, nil} ->
        {:error,
         Modal.Error.validation_msg(
           "missing app — pass `app: %Modal.App{}` from `Modal.App.lookup/3` " <>
             "(or `app_id: \"ap-...\"` if you have a raw id)."
         )}

      {%__MODULE__{}, id} when is_binary(id) ->
        {:error, Modal.Error.validation_msg("pass either `:app` or `:app_id`, not both.")}

      {%__MODULE__{id: id}, nil} ->
        {:ok, id, opts}

      {nil, %__MODULE__{}} ->
        # A struct landed in :app_id — almost certainly a copy-paste of
        # the post-v1.0 style with the wrong key. Tell the caller exactly
        # what to do rather than crashing later in the protobuf encoder.
        {:error,
         Modal.Error.validation_msg(
           "use `app: %Modal.App{}` (not `app_id: %Modal.App{}`). " <>
             "Pass the struct via the `:app` option, or pull its `:id` if you " <>
             "really want to keep using `:app_id` with a string."
         )}

      {nil, id} when is_binary(id) ->
        {:ok, id, opts}

      {other, _} when not is_nil(other) ->
        {:error,
         Modal.Error.validation_msg(
           "`:app` must be a `%Modal.App{}` (from `Modal.App.lookup/3`), got #{inspect(other)}."
         )}
    end
  end

  # ── Inspect — id + name only ────────────────────────────────────

  defimpl Inspect do
    def inspect(%Modal.App{id: id, name: nil}, _opts), do: "#Modal.App<id: #{id}>"

    def inspect(%Modal.App{id: id, name: name}, _opts),
      do: "#Modal.App<id: #{id}, name: #{inspect(name)}>"
  end
end
