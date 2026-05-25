defmodule Modal.Client.Behaviour do
  @moduledoc """
  Mock seam for the `Modal.Client` gRPC dispatch surface.

  `Modal.Client` implements this behaviour for the real (gun-backed)
  client. Tests in this repo set `config :modal, :client_impl,
  Modal.Client.Mock` and verify expectations with Mox; consumer
  apps can do the same.

      # test/test_helper.exs
      Mox.defmock(MyApp.ModalClientMock, for: Modal.Client.Behaviour)

      # config/test.exs
      config :modal, :client_impl, MyApp.ModalClientMock

      # somewhere in a test
      MyApp.ModalClientMock
      |> expect(:rpc, fn _, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: "sb-x"}}
      end)

  See `Modal.RPC` for the higher-level surface most callers should
  reach for; this behaviour is the seam for tests that want to
  intercept dispatch wholesale.
  """

  @doc "Unary RPC."
  @callback rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              timeout :: timeout()
            ) :: {:ok, struct()} | {:error, Modal.Error.t()}

  @doc "Server-streaming RPC — collects all messages into a list."
  @callback stream_rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              timeout :: timeout()
            ) :: {:ok, [struct()]} | {:error, Modal.Error.t()}

  @doc "Server-streaming RPC — reduces messages with an accumulator."
  @callback stream_rpc_reduce(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              initial_acc :: acc,
              reducer :: (struct(), acc -> {:cont, acc} | {:halt, acc}),
              timeout :: timeout()
            ) :: {:ok, acc} | {:error, Modal.Error.t()}
            when acc: term()

  @doc """
  Look up a sandbox's cached `task_id`. `:miss` means "not in cache —
  caller should RPC and then `cache_task_id/3`".
  """
  @callback lookup_task_id(client :: GenServer.server(), sandbox_id :: String.t()) ::
              {:ok, String.t()} | :miss

  @doc "Cache a sandbox's `task_id` so subsequent `lookup_task_id/2` calls hit."
  @callback cache_task_id(
              client :: GenServer.server(),
              sandbox_id :: String.t(),
              task_id :: String.t()
            ) :: :ok
end
