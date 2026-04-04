defmodule Modal.ModalStub.Behaviour do
  @moduledoc false

  @doc "Unary gRPC call to the Modal control plane."
  @callback call(GRPC.Channel.t(), atom(), term(), keyword()) ::
              {:ok, term()} | {:error, GRPC.RPCError.t()} | {:error, term()}

  @doc "Server-streaming gRPC call to the Modal control plane."
  @callback stream(GRPC.Channel.t(), atom(), term(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, GRPC.RPCError.t()} | {:error, term()}
end
