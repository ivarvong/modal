defmodule Modal.TaskCommandRouter.Behaviour do
  @moduledoc false

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
