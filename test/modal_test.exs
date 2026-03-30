defmodule ModalTest do
  use ExUnit.Case

  @moduletag :integration

  setup_all do
    token_id = System.get_env("MODAL_TOKEN_ID")
    token_secret = System.get_env("MODAL_TOKEN_SECRET")

    if is_nil(token_id) or is_nil(token_secret) do
      raise "MODAL_TOKEN_ID and MODAL_TOKEN_SECRET must be set (source .env)"
    end

    {:ok, client} =
      start_supervised({Modal.Client, token_id: token_id, token_secret: token_secret})

    %{client: client}
  end

  test "lists sandboxes", %{client: client} do
    assert {:ok, sandboxes} = Modal.Sandbox.list(client)
    assert is_list(sandboxes)
  end
end
