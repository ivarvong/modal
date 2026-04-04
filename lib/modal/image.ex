defmodule Modal.Image do
  @moduledoc "Modal container image management."

  require Logger
  alias Modal.RPC

  @doc """
  Get or create a container image from Dockerfile commands.

  Waits for the image build to complete. Returns `{:ok, image_id, status}` where
  `status` is `:cached` if the image already existed or `:built` if it was just
  built from scratch.

  Note: this function returns a 3-tuple. Use `{:ok, image_id, _status}` when
  only the image ID is needed in a `with` chain.
  """
  @spec get_or_create(GenServer.server(), [String.t()], keyword()) ::
          {:ok, String.t(), :cached | :built} | {:error, term()}
  def get_or_create(client, dockerfile_commands, opts \\ []) do
    image = %Modal.Client.Image{dockerfile_commands: dockerfile_commands}

    request = %Modal.Client.ImageGetOrCreateRequest{
      image: image,
      app_id: Keyword.get(opts, :app_id, "")
    }

    with {:ok, resp} <- RPC.call(client, :ImageGetOrCreate, request),
         {:ok, status} <- await_build(client, resp.image_id) do
      {:ok, resp.image_id, status}
    end
  end

  # Returns {:ok, :cached} if the image was already built (no log output
  # streamed back), or {:ok, :built} if a fresh build was performed.
  # The ImageJoinStreaming RPC with include_logs_for_finished: false emits
  # task_logs only during an active build, giving us this signal for free.
  defp await_build(client, image_id) do
    request = %Modal.Client.ImageJoinStreamingRequest{
      image_id: image_id,
      timeout: 600.0,
      include_logs_for_finished: false
    }

    case RPC.stream(client, :ImageJoinStreaming, request, 620_000) do
      {:ok, responses} ->
        failure =
          Enum.find(responses, fn resp ->
            resp.result &&
              resp.result.status not in [:GENERIC_STATUS_UNSPECIFIED, :GENERIC_STATUS_SUCCESS]
          end)

        if failure do
          Logger.error("[modal] image build failed: #{failure.result.status}")
          {:error, {:image_build_failed, failure.result.status}}
        else
          had_logs = Enum.any?(responses, fn resp -> resp.task_logs != [] end)
          {:ok, if(had_logs, do: :built, else: :cached)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
