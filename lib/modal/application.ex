defmodule Modal.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Shared DynamicSupervisor used by the gRPC client library to manage
      # HTTP/2 connections. One supervisor serves all Modal.Client instances —
      # each customer gets their own Modal.Client GenServer (with its own
      # credentials), but they share this connection-pool infrastructure.
      {DynamicSupervisor, strategy: :one_for_one, name: GRPC.Client.Supervisor},

      # Task.Supervisor for dispatching RPC calls concurrently from Modal.Client.
      # This allows a single Modal.Client GenServer to handle many concurrent
      # requests without serializing them through its mailbox.
      {Task.Supervisor, name: Modal.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Modal.Supervisor)
  end
end
