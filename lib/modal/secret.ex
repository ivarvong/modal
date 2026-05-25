defmodule Modal.Secret do
  @moduledoc """
  Modal Secret lifecycle.

  A Modal Secret is a named bag of environment variables that is injected
  into a sandbox at boot time via `secret_ids:` on `Modal.Sandbox.create/2`.
  Use this module to mint a secret for a sandbox, list existing secrets,
  and delete secrets when they're no longer needed.

  ## Quick start

      # One-shot ephemeral env for a single sandbox boot.
      {:ok, secret_id} =
        Modal.Secret.create(client,
          app_id: app_id,
          name: "my-task-env",
          env: %{"ANTHROPIC_API_KEY" => key, "DATABASE_URL" => db_url}
        )

      sandbox =
        Modal.Sandbox.create!(client,
          app_id: app_id,
          image_id: image_id,
          secret_ids: [secret_id]
        )

  ## Secret names

  Names are unique per app. Re-using a name with `create/2` overwrites the
  existing secret's env_dict by default — the same `secret_id` is returned.
  Pass `if_exists: :fail` to refuse the overwrite, or `if_exists: :ephemeral`
  to mint an unnamed secret tied to the calling client's lifecycle.
  """

  alias Modal.RPC

  @create_opts [
    app_id: [type: :string, required: true],
    name: [type: :string, required: true],
    env: [type: {:map, :string, :string}, required: true],
    environment_name: [type: :string, default: ""],
    if_exists: [type: {:in, [:overwrite, :fail, :ephemeral]}, default: :overwrite]
  ]

  @doc """
  Create or update a named secret. Returns `{:ok, secret_id}`.

  Pass the owning app via `app: %Modal.App{}` (recommended — see
  `Modal.App.lookup/3`) or `app_id: "ap-..."`.

  ## Options

  #{NimbleOptions.docs(@create_opts)}
  """
  @spec create(GenServer.server(), keyword()) :: {:ok, String.t()} | {:error, Modal.Error.t()}
  def create(client, opts) do
    with {:ok, app_id, opts} <- Modal.App.resolve_app_id(opts),
         opts = Keyword.put(opts, :app_id, app_id),
         {:ok, validated} <- validate_opts(opts, @create_opts) do
      request = %Modal.Client.SecretGetOrCreateRequest{
        deployment_name: validated[:name],
        app_id: validated[:app_id],
        environment_name: validated[:environment_name],
        env_dict: validated[:env],
        object_creation_type: creation_type(validated[:if_exists])
      }

      with {:ok, resp} <- RPC.call(client, :SecretGetOrCreate, request) do
        {:ok, resp.secret_id}
      end
    end
  end

  @doc "Like `create/2` but raises on error."
  @spec create!(GenServer.server(), keyword()) :: String.t()
  def create!(client, opts) do
    case create(client, opts) do
      {:ok, id} -> id
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  @doc """
  Delete a secret by id. Returns `:ok` whether or not the secret existed.
  """
  @spec delete(GenServer.server(), String.t()) :: :ok | {:error, Modal.Error.t()}
  def delete(client, secret_id) when is_binary(secret_id) do
    request = %Modal.Client.SecretDeleteRequest{secret_id: secret_id}
    with {:ok, _} <- RPC.call(client, :SecretDelete, request), do: :ok
  end

  @doc """
  List secrets in the current environment.

  Returns `{:ok, [map()]}` where each map has at least `:secret_id` and
  `:label`. The shape mirrors Modal's proto `SecretListItem` fields and
  may grow over time; pattern-match on the keys you care about.

  ## Options

    * `:environment_name` — Modal environment to list from (default: workspace default)
  """
  @spec list(GenServer.server(), keyword()) :: {:ok, [map()]} | {:error, Modal.Error.t()}
  def list(client, opts \\ []) do
    request = %Modal.Client.SecretListRequest{
      environment_name: Keyword.get(opts, :environment_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :SecretList, request) do
      {:ok, Enum.map(resp.items, &secret_list_item_to_map/1)}
    end
  end

  defp secret_list_item_to_map(item) do
    item
    |> Map.from_struct()
    |> Map.delete(:__unknown_fields__)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp creation_type(:overwrite), do: :OBJECT_CREATION_TYPE_CREATE_OVERWRITE_IF_EXISTS
  defp creation_type(:fail), do: :OBJECT_CREATION_TYPE_CREATE_FAIL_IF_EXISTS
  defp creation_type(:ephemeral), do: :OBJECT_CREATION_TYPE_EPHEMERAL

  defp validate_opts(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = err} -> {:error, Modal.Error.validation(err)}
    end
  end
end
