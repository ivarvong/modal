# Modal

Elixir client for the [Modal](https://modal.com) Sandbox API.

Create sandboxes, execute commands with streaming stdout, snapshot
filesystems, and read/write files -- all from Elixir.

## Installation

```elixir
def deps do
  [
    {:modal, "~> 0.1.0"}
  ]
end
```

## Quick start

```elixir
{:ok, client} = Modal.Client.start_link(
  token_id: System.get_env("MODAL_TOKEN_ID"),
  token_secret: System.get_env("MODAL_TOKEN_SECRET")
)

{:ok, app_id} = Modal.App.lookup(client, "my-app")
{:ok, image_id} = Modal.Image.get_or_create(client, ["FROM python:3.12-slim"])

sandbox = Modal.Sandbox.create!(client,
  app_id: app_id,
  image_id: image_id,
  cmd: ["sleep", "infinity"]
)

# Execute with streaming stdout
proc = Modal.Sandbox.exec(sandbox, ["echo", "hello from modal"])
proc |> Enum.each(&IO.write/1)
{:ok, 0} = Modal.ContainerProcess.exit_code(proc)
Modal.ContainerProcess.close(proc)

# Or collect all output at once
proc = Modal.Sandbox.exec(sandbox, ["python3", "-c", "print(2+2)"])
{:ok, %{stdout: "4\n", code: 0}} = Modal.ContainerProcess.await(proc)
Modal.ContainerProcess.close(proc)

# File I/O
:ok = Modal.Sandbox.write_file(sandbox, "/tmp/test.txt", "hello")
{:ok, "hello"} = Modal.Sandbox.read_file(sandbox, "/tmp/test.txt")
{:ok, files} = Modal.Sandbox.ls(sandbox, "/tmp")

# Snapshot and restore
{:ok, image_id} = Modal.Sandbox.snapshot_filesystem(sandbox)
Modal.Sandbox.terminate(sandbox)

# New sandbox starts instantly from snapshot
sandbox2 = Modal.Sandbox.create!(client,
  app_id: app_id,
  image_id: image_id,
  cmd: ["sleep", "infinity"]
)
```

## Modules

- `Modal.Client` -- gRPC connection to `api.modal.com`
- `Modal.App` -- app lookup/creation
- `Modal.Image` -- container image builds
- `Modal.Sandbox` -- sandbox lifecycle, exec, filesystem, logs, tunnels, snapshots
- `Modal.ContainerProcess` -- a running command with streaming stdout and stdin

## Attribution

Proto definitions generated from [modal-labs/modal-client](https://github.com/modal-labs/modal-client)
(Apache License 2.0). See [NOTICE](NOTICE) for details.

## License

MIT
