defmodule Modal.ModalStub.Behaviour do
  @moduledoc """
  Mock seam for the raw gRPC stub that `Modal.Client` dispatches to.

  Most callers should mock at the `Modal.Client.Behaviour` level
  instead — that's where the public RPC surface lives. This
  lower-level seam exists for tests that want to assert on the exact
  gRPC call shape (channel, method atom, message, opts) rather than
  the post-translation Modal response.

      # config/test.exs
      config :modal, :modal_stub, MyApp.ModalStubMock

  See `Modal.Client.Behaviour` for the recommended mock point.
  """

  @doc "Unary gRPC call to the Modal control plane."
  @callback call(GRPC.Channel.t(), atom(), term(), keyword()) ::
              {:ok, term()} | {:error, GRPC.RPCError.t()} | {:error, term()}

  @doc "Server-streaming gRPC call to the Modal control plane."
  @callback stream(GRPC.Channel.t(), atom(), term(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, GRPC.RPCError.t()} | {:error, term()}
end
