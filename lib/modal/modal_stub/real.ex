defmodule Modal.ModalStub.Real do
  @moduledoc false

  @behaviour Modal.ModalStub.Behaviour

  alias Modal.Client.ModalClient.Stub, as: ModalStub

  @impl true
  def call(channel, method, request, opts) do
    apply(ModalStub, method, [channel, request, opts])
  end

  @impl true
  def stream(channel, method, request, opts) do
    apply(ModalStub, method, [channel, request, opts])
  end
end
