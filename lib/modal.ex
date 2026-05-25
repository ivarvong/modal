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

      {:ok, proc}   = Modal.Sandbox.exec(sandbox, ["echo", "hello"])
      {:ok, stream} = Modal.ContainerProcess.stream(proc)
      Enum.each(stream, &IO.write/1)
      {:ok, 0} = Modal.ContainerProcess.exit_code(proc)
      Modal.ContainerProcess.close(proc)

      Modal.Sandbox.terminate(sandbox)

  ## Modules

    * `Modal.Client` - gRPC connection to `api.modal.com`
    * `Modal.App` - app lookup/creation
    * `Modal.Image` - container image builds
    * `Modal.Sandbox` - sandbox lifecycle, exec, logs, tunnels, snapshots
    * `Modal.Filesystem` - sandbox-side file I/O
    * `Modal.ContainerProcess` - a running command with streaming stdout and stdin
    * `Modal.Secret` - environment-variable bags injected into sandboxes
    * `Modal.Volume` - typed handle for a volume mount
    * `Modal.Error` - structured error returned by every operation that can fail

  ## Error handling

  Every operation that can fail returns `{:error, %Modal.Error{}}`. The
  struct is also an `Exception` — `Modal.ContainerProcess.stream/1`'s
  Stream consumer raises it (Elixir's `Enum.*` callbacks can't return
  tuples), and the bang variants raise it on failure.

  See `Modal.Error` for the kind table and pattern-matching examples.

  ## Bang (`!`) variants

  The library ships a small, principled set of bang variants:
  `Modal.Sandbox.create!/2`, `Modal.Sandbox.exec!/3`,
  `Modal.Filesystem.read_file!/2`, `Modal.Filesystem.write_file!/3`.

  The rule: a bang variant exists only when the non-bang form returns
  `{:ok, value}` and the caller commonly wants the value unwrapped — i.e.
  the bang variant returns `value` directly and raises `Modal.Error` on
  failure. Operations that already return `:ok | {:error, _}` (e.g.
  `terminate/1`, `wait/2`, `mkdir/3`, `rm/3`,
  `ContainerProcess.write/3`, `Modal.Secret.delete/2`) do not have bang
  variants — the non-bang form is already as short as a bang variant
  would be, and callers can pattern-match on `:ok` directly.
  """
end
