defmodule Mix.Tasks.Modal.Smoketest do
  @moduledoc "Creates a sandbox, runs a Python script, and prints the output."
  @shortdoc "Create a sandbox, run Python, print the result"
  use Mix.Task

  import Modal.MixHelpers

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {token_id, token_secret} = credentials!()

    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    {:ok, app_id} = Modal.App.lookup(client, "elixir-smoketest")

    {:ok, image_id} =
      Modal.Image.get_or_create(client, ["FROM python:3.12-slim-bookworm"], app_id: app_id)

    Mix.shell().info("Image: #{image_id}")

    script = ~S"""
    import math
    print(f"2 + 2 = {2 + 2}")
    print(f"sqrt(144) = {math.sqrt(144)}")
    print(f"2^10 = {2**10}")
    """

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["python3", "-c", script],
        timeout: 300,
        idle_timeout: 30
      )

    Mix.shell().info("Sandbox: #{sandbox.id}")

    case Modal.Sandbox.wait(sandbox, timeout: 120.0) do
      {:ok, resp} ->
        if resp.result, do: Mix.shell().info("Status: #{resp.result.status}")

      {:error, reason} ->
        Mix.shell().error("Wait failed: #{inspect(reason)}")
    end

    case Modal.Sandbox.get_logs(sandbox, file_descriptor: :FILE_DESCRIPTOR_STDOUT) do
      {:ok, batches} ->
        output = batches |> Enum.flat_map(& &1.items) |> Enum.map_join(& &1.data)
        if output != "", do: Mix.shell().info("\n#{output}")

      {:error, _} ->
        :ok
    end

    Modal.Sandbox.terminate(sandbox)
    GenServer.stop(client)
  end
end
