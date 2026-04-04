defmodule Modal.App do
  @moduledoc "Modal App management."

  alias Modal.RPC

  @doc """
  Look up a Modal App by name, creating it if it doesn't exist.

  Returns `{:ok, app_id}`.
  """
  @spec lookup(GenServer.server(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def lookup(client, app_name, opts \\ []) do
    request = %Modal.Client.AppGetOrCreateRequest{
      app_name: app_name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
    }

    with {:ok, resp} <- RPC.call(client, :AppGetOrCreate, request) do
      {:ok, resp.app_id}
    end
  end
end
