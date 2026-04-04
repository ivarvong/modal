defmodule Modal.Client.Behaviour do
  @moduledoc false

  @doc "Unary RPC."
  @callback rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: term(),
              timeout :: non_neg_integer()
            ) :: {:ok, term()} | {:error, term()}

  @doc "Server-streaming RPC — collects all messages into a list."
  @callback stream_rpc(
              client :: GenServer.server(),
              method :: atom(),
              request :: term(),
              timeout :: non_neg_integer()
            ) :: {:ok, [term()]} | {:error, term()}

  @doc "Server-streaming RPC — calls `callback` for each message."
  @callback stream_rpc_each(
              client :: GenServer.server(),
              method :: atom(),
              request :: term(),
              callback :: function(),
              timeout :: timeout()
            ) :: :ok | {:error, term()}
end
