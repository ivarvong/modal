defmodule Modal.SecretTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock

  describe "create/2" do
    test "returns {:ok, secret_id} on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_get_or_create, req, _timeout ->
        assert req.deployment_name == "my-env"
        assert req.app_id == "ap-test"
        assert req.env_dict == %{"FOO" => "bar"}
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_CREATE_OVERWRITE_IF_EXISTS
        {:ok, %Modal.Client.SecretGetOrCreateResponse{secret_id: "st-abc"}}
      end)

      assert {:ok, "st-abc"} =
               Modal.Secret.create(@client,
                 app_id: "ap-test",
                 name: "my-env",
                 env: %{"FOO" => "bar"}
               )
    end

    test "translates :fail into CREATE_FAIL_IF_EXISTS" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_get_or_create, req, _timeout ->
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_CREATE_FAIL_IF_EXISTS
        {:ok, %Modal.Client.SecretGetOrCreateResponse{secret_id: "st-1"}}
      end)

      Modal.Secret.create(@client, app_id: "ap-x", name: "n", env: %{}, if_exists: :fail)
    end

    test "translates :ephemeral into EPHEMERAL" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_get_or_create, req, _timeout ->
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_EPHEMERAL
        {:ok, %Modal.Client.SecretGetOrCreateResponse{secret_id: "st-1"}}
      end)

      Modal.Secret.create(@client, app_id: "ap-x", name: "n", env: %{}, if_exists: :ephemeral)
    end

    test "validation error when app is missing" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Secret.create(@client, name: "n", env: %{})

      assert msg =~ "missing app"
    end

    test "accepts :app (%Modal.App{}) in place of :app_id" do
      app = %Modal.App{id: "ap-from-struct", client: @client}

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_get_or_create, req, _timeout ->
        assert req.app_id == "ap-from-struct"
        {:ok, %Modal.Client.SecretGetOrCreateResponse{secret_id: "st-ok"}}
      end)

      assert {:ok, "st-ok"} = Modal.Secret.create(@client, app: app, name: "n", env: %{})
    end

    test "validation error when :name is missing" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Secret.create(@client, app_id: "ap-x", env: %{})
    end

    test "validation error when :env values are not strings" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Secret.create(@client, app_id: "ap-x", name: "n", env: %{"K" => 42})
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_get_or_create, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Secret.create(@client, app_id: "ap-x", name: "n", env: %{})
    end
  end

  describe "create!/2" do
    test "returns the secret_id on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :secret_get_or_create, _, _ ->
        {:ok, %Modal.Client.SecretGetOrCreateResponse{secret_id: "st-ok"}}
      end)

      assert "st-ok" = Modal.Secret.create!(@client, app_id: "ap-x", name: "n", env: %{})
    end

    test "raises on validation error" do
      assert_raise Modal.Error, fn ->
        Modal.Secret.create!(@client, name: "missing app_id", env: %{})
      end
    end
  end

  describe "delete/2" do
    test "returns :ok on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :secret_delete, req, _timeout ->
        assert req.secret_id == "st-doomed"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Secret.delete(@client, "st-doomed")
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :secret_delete, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
               Modal.Secret.delete(@client, "st-missing")
    end
  end

  describe "list/2" do
    test "returns the items as plain maps (proto struct not leaked)" do
      items = [
        %Modal.Client.SecretListItem{secret_id: "st-1", label: "a"},
        %Modal.Client.SecretListItem{secret_id: "st-2", label: "b"}
      ]

      Modal.Client.Mock
      |> expect(:rpc, fn _, :secret_list, _req, _timeout ->
        {:ok, %Modal.Client.SecretListResponse{items: items}}
      end)

      assert {:ok, [first, second]} = Modal.Secret.list(@client)
      assert is_map(first) and not is_struct(first)
      assert %{secret_id: "st-1", label: "a"} = first
      assert %{secret_id: "st-2", label: "b"} = second
      refute Map.has_key?(first, :__unknown_fields__)
    end

    test "passes environment_name through" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :secret_list, req, _timeout ->
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.SecretListResponse{items: []}}
      end)

      assert {:ok, []} = Modal.Secret.list(@client, environment_name: "staging")
    end
  end
end
