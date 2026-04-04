defmodule Modal.Test.SlowStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A stub that records metadata used per-call and sleeps to simulate a slow
  # RPC. Used to prove that Modal.Client dispatches requests concurrently.

  @impl true
  def call(_channel, _method, _request, _opts) do
    Process.sleep(50)
    {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    {:ok, []}
  end
end

defmodule Modal.Test.CredentialSpyStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # Records the token-id used in each call so credential isolation can be
  # verified: client A's credential must never appear in client B's RPCs.
  # The recorder PID is stored in :persistent_term under :modal_spy_recorder.

  @impl true
  def call(_channel, _method, _request, opts) do
    token_id = get_in(opts, [:metadata, "x-modal-token-id"])

    case :persistent_term.get(:modal_spy_recorder, nil) do
      nil -> :ok
      recorder -> send(recorder, {:spy_token, token_id})
    end

    {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
  end

  @impl true
  def stream(_channel, _method, _request, _opts), do: {:ok, []}
end
