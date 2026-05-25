defmodule Modal.AppTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock

  describe "lookup/3" do
    test "returns %Modal.App{} struct on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, _req, _timeout ->
        {:ok, %Modal.Client.AppGetOrCreateResponse{app_id: "ap-abc123"}}
      end)

      assert {:ok, %Modal.App{id: "ap-abc123", name: "my-app", client: @client}} =
               Modal.App.lookup(@client, "my-app")
    end

    test "passes environment_name option" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, req, _timeout ->
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.AppGetOrCreateResponse{app_id: "ap-staging"}}
      end)

      assert {:ok, %Modal.App{id: "ap-staging", name: "my-app"}} =
               Modal.App.lookup(@client, "my-app", environment_name: "staging")
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :app_get_or_create, _req, _timeout ->
        {:error, Modal.Error.grpc(2, "unknown")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 2}} = Modal.App.lookup(@client, "my-app")
    end
  end

  # ── resolve_app_id/1 ────────────────────────────────────────────

  describe "resolve_app_id/1" do
    test "accepts a %Modal.App{} via :app" do
      app = %Modal.App{id: "ap-xyz", name: "demo", client: @client}
      assert {:ok, "ap-xyz", []} = Modal.App.resolve_app_id(app: app)
    end

    test "accepts a raw id via :app_id (backwards-compat)" do
      assert {:ok, "ap-old", []} = Modal.App.resolve_app_id(app_id: "ap-old")
    end

    test "rejects a struct passed as :app_id with a directional hint" do
      app = %Modal.App{id: "ap-xyz", client: @client}

      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.App.resolve_app_id(app_id: app)

      assert msg =~ "use `app: %Modal.App{}`"
    end

    test "rejects both :app and :app_id at once" do
      app = %Modal.App{id: "ap-xyz", client: @client}

      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.App.resolve_app_id(app: app, app_id: "ap-something-else")

      assert msg =~ "either `:app` or `:app_id`, not both"
    end

    test "rejects a non-struct via :app" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.App.resolve_app_id(app: "ap-string-via-app")

      assert msg =~ "must be a `%Modal.App{}`"
    end

    test "errors when neither is present" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.App.resolve_app_id([])

      assert msg =~ "missing app"
    end

    test "leaves other opts untouched after popping :app" do
      app = %Modal.App{id: "ap-xyz", client: @client}

      assert {:ok, "ap-xyz", [foo: 1, bar: 2]} =
               Modal.App.resolve_app_id(foo: 1, app: app, bar: 2)
    end
  end
end
