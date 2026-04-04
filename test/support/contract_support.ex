defmodule Modal.Contract.Support do
  @moduledoc """
  Shared setup for contract tests.

  Contract tests verify that the real Modal API returns responses in the exact
  shape that our Mox mocks simulate. They are the bridge between fast unit tests
  and slow integration tests — cheap to run (single RPC each), but they catch
  mock drift before it reaches production.

  Run with:

      mix test --include contract

  Requires MODAL_TOKEN_ID and MODAL_TOKEN_SECRET environment variables.
  """

  def client! do
    token_id = System.get_env("MODAL_TOKEN_ID")
    token_secret = System.get_env("MODAL_TOKEN_SECRET")

    unless token_id && token_secret do
      raise "Contract tests require MODAL_TOKEN_ID and MODAL_TOKEN_SECRET"
    end

    Application.put_env(:modal, :client_impl, Modal.Client)
    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    client
  end
end
