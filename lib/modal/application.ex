defmodule Modal.Application do
  @moduledoc false

  # OTP application callback for the `:modal` library.
  #
  # The single job of this supervisor is to own the
  # `GRPC.Client.Supervisor` DynamicSupervisor. The `grpc` library expects
  # that name to be registered globally (it routes every channel through
  # it), and the supervisor's process must outlive every individual
  # gRPC channel.
  #
  # The previous design started this DynamicSupervisor lazily inside
  # `Modal.Client.init/1` with `DynamicSupervisor.start_link/1`. That
  # linked the supervisor to whichever Modal.Client called `init` first.
  # In a multi-tenant setup, terminating that one client took down every
  # tenant's gRPC connections — the opposite of the per-tenant isolation
  # the rest of the design works hard to achieve.
  #
  # Now the supervisor lives under the library's own application
  # supervision tree, started once by the BEAM at app boot, and is owned
  # by no individual Modal.Client. Every client adds and removes channels
  # under it; clients come and go, the supervisor stays.
  #
  # It also owns `Modal.WatchdogSupervisor`, a Task.Supervisor for the
  # caller-exit monitor processes (see `Modal.Sandbox` and
  # `Modal.ContainerProcess`). Same rationale as above: those monitors
  # must outlive the Modal.Client that spawned them, and a crash in one
  # should be reported, not silent.

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # `GRPC.Client.Supervisor` is a hard-coded name inside the grpc
      # library. Registering it ourselves under a one_for_one means any
      # transient supervisor crash recovers without taking down the
      # client GenServers, which are siblings.
      {DynamicSupervisor, strategy: :one_for_one, name: GRPC.Client.Supervisor},

      # Owns the caller-exit watchdog processes — the per-sandbox monitor
      # that fires `SandboxTerminate` when the calling pid dies, and the
      # per-exec channel monitor in `Modal.ContainerProcess`. These used
      # to be bare `spawn/1`s; under a Task.Supervisor a crash in a
      # monitor (which would otherwise silently leave the very leak it
      # exists to prevent) is reported through the logger like any other
      # task. Tasks default to `:temporary` restart — correct here, since
      # each monitor is bound to one caller pid and restarting it with a
      # stale ref would be wrong; let it stay dead.
      {Task.Supervisor, name: Modal.WatchdogSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Modal.Supervisor)
  end
end
