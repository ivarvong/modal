defmodule Modal.TaskCommandRouter.Behaviour do
  @moduledoc """
  Mock seam for the per-task worker-channel gRPC stub.

  `Modal.ContainerProcess` dispatches `task_exec_start`,
  `task_exec_stdio_read`, `task_exec_wait`, and `task_exec_stdin_write`
  through this behaviour. The default implementation is the generated
  grpc-elixir stub; tests in this repo override via the `:tcr_stub`
  option on `Modal.ContainerProcess.t()` to point at a Mox mock.

      # test/test_helper.exs
      Mox.defmock(MyApp.TCRMock, for: Modal.TaskCommandRouter.Behaviour)

      # somewhere in a test
      proc = %Modal.ContainerProcess{
        channel: :fake_channel,
        task_id: "ti-x",
        exec_id: "ex-y",
        jwt: "...",
        jwt_exp: 9_999_999_999,
        tcr_stub: MyApp.TCRMock
      }

  See `test/modal/container_process_test.exs` for a worked example.
  """

  @doc "Start a command exec on a worker."
  @callback task_exec_start(GRPC.Channel.t(), term(), keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc "Poll/wait for a command to finish."
  @callback task_exec_wait(GRPC.Channel.t(), term(), keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc "Open a server-streaming stdout/stderr read."
  @callback task_exec_stdio_read(GRPC.Channel.t(), term(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc "Write to a command's stdin."
  @callback task_exec_stdin_write(GRPC.Channel.t(), term(), keyword()) ::
              {:ok, term()} | {:error, term()}
end
