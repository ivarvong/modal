defmodule Modal.Contract.AppTest do
  @moduledoc """
  Validates that Modal.AppTest mocks match the real API.

  Asserted contract:
    - `:app_get_or_create` returns `%AppGetOrCreateResponse{app_id: "ap-…"}`.
    - The call is idempotent (same name returns the same app_id).
    - `Modal.App.list/2` returns app items with `:app_id` / `:description`
      / `:state`. (`AppStop` is destructive — unit-tested only.)
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract

  setup_all do
    %{client: Support.client!()}
  end

  test "App.lookup returns {:ok, %Modal.App{}} with an id starting with 'ap-'",
       %{client: client} do
    app_name = Support.app_name()

    assert {:ok, %Modal.App{id: app_id, name: ^app_name, client: ^client}} =
             Modal.App.lookup(client, app_name)

    assert is_binary(app_id)
    assert String.starts_with?(app_id, "ap-")
  end

  test "App.lookup is idempotent — second call returns the same app_id", %{client: client} do
    {:ok, %Modal.App{id: id1}} = Modal.App.lookup(client, Support.app_name())
    {:ok, %Modal.App{id: id2}} = Modal.App.lookup(client, Support.app_name())
    assert id1 == id2
  end

  test "AppGetOrCreateResponse: shape", %{client: client} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :app_get_or_create,
        %Modal.Client.AppGetOrCreateRequest{app_name: Support.app_name()}
      )

    assert %Modal.Client.AppGetOrCreateResponse{} = resp
    assert_struct_shape(resp, %{app_id: {:string_prefix, "ap-"}})
  end

  test "App.list returns app items with the documented shape", %{client: client} do
    assert {:ok, apps} = Modal.App.list(client)
    assert is_list(apps)

    # AppList only surfaces deployed/running/recently-stopped apps, so a
    # freshly lookup-created app may not appear — validate the item shape
    # against whatever the workspace already has, if anything.
    for app <- Enum.take(apps, 1) do
      assert String.starts_with?(app.app_id, "ap-")
      assert is_binary(app.description)
      assert is_atom(app.state)
    end
  end
end
