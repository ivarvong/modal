defmodule Modal.Client.Behaviour do
  @moduledoc false

  @type rpc_error :: {:grpc, non_neg_integer(), String.t()} | {:network, term()}

  @doc "Unary RPC."
  @callback rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              timeout :: timeout()
            ) :: {:ok, struct()} | {:error, rpc_error()}

  @doc "Server-streaming RPC — collects all messages into a list."
  @callback stream_rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              timeout :: timeout()
            ) :: {:ok, [struct()]} | {:error, rpc_error()}

  @doc "Server-streaming RPC — reduces messages with an accumulator."
  @callback stream_rpc_reduce(
              client :: GenServer.server(),
              method :: atom(),
              request :: struct(),
              initial_acc :: acc,
              reducer :: (struct(), acc -> {:cont, acc} | {:halt, acc}),
              timeout :: timeout()
            ) :: {:ok, acc} | {:error, rpc_error()}
            when acc: term()
end
