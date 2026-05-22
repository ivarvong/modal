defmodule Modal do
  @moduledoc """
  Elixir client for the [Modal](https://modal.com) API.

  ## Quick start

      {:ok, client} = Modal.Client.start_link(
        token_id: System.get_env("MODAL_TOKEN_ID"),
        token_secret: System.get_env("MODAL_TOKEN_SECRET")
      )

      {:ok, app_id} = Modal.App.lookup(client, "my-app")
      {:ok, image_id, _status} = Modal.Image.get_or_create(client, ["FROM python:3.14-slim"])

      sandbox = Modal.Sandbox.create!(client, app_id: app_id, image_id: image_id, cmd: ["sleep", "infinity"])

      {:ok, proc} = Modal.Sandbox.exec(sandbox, ["echo", "hello"])
      proc |> Modal.ContainerProcess.stream() |> Enum.each(&IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)
      Modal.ContainerProcess.close(proc)

      Modal.Sandbox.terminate(sandbox)

  ## Modules

    * `Modal.Client` - gRPC connection to `api.modal.com`
    * `Modal.App` - app lookup/creation
    * `Modal.Image` - container image builds
    * `Modal.Sandbox` - sandbox lifecycle, exec, filesystem, logs, tunnels, snapshots
    * `Modal.ContainerProcess` - a running command with streaming stdout and stdin
  """
end
