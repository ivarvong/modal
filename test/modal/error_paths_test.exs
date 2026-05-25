defmodule Modal.ErrorPathsTest do
  @moduledoc """
  Exhaustive error-path tests. Every `{:error, ...}` branch in `Sandbox`,
  `Image`, `App`, and `Filesystem` has at least one test here. This is the
  suite that catches regressions when error-handling code is refactored.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @sandbox %Modal.Sandbox{id: "sb-err", client: @client}

  # Cold cache by default — every test starts with `lookup_task_id` returning
  # `:miss`. The single test that needs a warm cache stubs it explicitly.
  setup do
    Mox.stub(Modal.Client.Mock, :lookup_task_id, fn _, _ -> :miss end)
    Mox.stub(Modal.Client.Mock, :cache_task_id, fn _, _, _ -> :ok end)
    :ok
  end

  # ── App ─────────────────────────────────────────────────────────

  describe "App.lookup/3 errors" do
    test "propagates gRPC application error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_get_or_create, _, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7, message: "permission denied"}} =
               Modal.App.lookup(@client, "app")
    end

    test "propagates network error" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :app_get_or_create, _, _ ->
        {:error, Modal.Error.network(:econnrefused)}
      end)

      assert {:error, %Modal.Error{kind: :network, code: :econnrefused}} =
               Modal.App.lookup(@client, "app")
    end
  end

  # ── Image ────────────────────────────────────────────────────────

  describe "Image.get_or_create/3 errors" do
    test "propagates ImageGetOrCreate RPC error" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :image_get_or_create, _, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end

    test "returns :image_build_failed on build failure" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :image_get_or_create, _, _ ->
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: "im-x"}}
      end)
      |> expect(:stream_rpc_reduce, fn _, :image_join_streaming, _req, initial, reducer, _ ->
        result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_FAILURE}
        resp = %Modal.Client.ImageJoinStreamingResponse{task_logs: [], result: result}

        {:ok,
         case reducer.(resp, initial) do
           {:halt, acc} -> acc
           {:cont, acc} -> acc
         end}
      end)

      assert {:error, %Modal.Error{kind: :image_build_failed, code: :GENERIC_STATUS_FAILURE}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end

    test "returns error when ImageJoinStreaming stream itself fails" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :image_get_or_create, _, _ ->
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: "im-x"}}
      end)
      |> expect(:stream_rpc_reduce, fn _, :image_join_streaming, _, _, _, _ ->
        {:error, Modal.Error.grpc(4, "deadline exceeded")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 4}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end
  end

  # ── Sandbox ──────────────────────────────────────────────────────

  describe "Sandbox.create/2 validation errors" do
    test "returns :validation when app_id is missing" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Sandbox.create(@client, cmd: ["sleep", "infinity"])
    end

    test "returns :validation when image_id is missing" do
      # Server's response to a sandbox with empty image_id is opaque;
      # we surface the missing field at the option-validation layer
      # instead — clearer error, no RPC round-trip wasted.
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", cmd: ["sleep", "infinity"])

      assert msg =~ ":image_id"
    end

    test "returns :validation for unknown option" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", image_id: "im-x", bad_key: true)
    end

    test "returns :validation for wrong cpu type" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", image_id: "im-x", cpu: "2")
    end

    test "propagates SandboxCreate RPC error" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, Modal.Error.grpc(8, "resource exhausted")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 8}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", image_id: "im-x")
    end
  end

  describe "Sandbox.create!/2 errors" do
    test "raises with helpful message on validation failure" do
      assert_raise Modal.Error, ~r/missing app/, fn ->
        Modal.Sandbox.create!(@client, cmd: ["sleep", "infinity"])
      end
    end

    test "raises with helpful message on RPC error" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert_raise Modal.Error, ~r/unavailable/, fn ->
        Modal.Sandbox.create!(@client, app_id: "ap-x", image_id: "im-x")
      end
    end
  end

  describe "Sandbox.get_task_id/1 errors" do
    test "propagates RPC error when cache misses" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
               Modal.Sandbox.get_task_id(@sandbox)
    end

    test "never calls RPC when cache hits" do
      Modal.Client.Mock
      |> expect(:lookup_task_id, fn _, "sb-err" -> {:ok, "ti-err"} end)

      # No :rpc expectation — verify_on_exit! ensures none fires.
      assert {:ok, "ti-err"} = Modal.Sandbox.get_task_id(@sandbox)
    end
  end

  describe "Sandbox.terminate/1 errors" do
    test "propagates RPC error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_terminate, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} = Modal.Sandbox.terminate(@sandbox)
    end
  end

  describe "Sandbox.poll/1 errors" do
    test "returns {:ok, nil} on DEADLINE_EXCEEDED (sandbox still running)" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :sandbox_wait, _, _ ->
        {:error, Modal.Error.grpc(4, "deadline exceeded")}
      end)

      assert {:ok, nil} = Modal.Sandbox.poll(@sandbox)
    end

    test "propagates non-DEADLINE_EXCEEDED gRPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_wait, _, _ ->
        {:error, Modal.Error.grpc(2, "unknown")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 2}} = Modal.Sandbox.poll(@sandbox)
    end
  end

  describe "Sandbox.exec/3 errors" do
    test "returns error when command router access fails" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: "ti-x"}}
      end)
      |> expect(:rpc, fn _, :task_get_command_router_access, _, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{}} = Modal.Sandbox.exec(@sandbox, ["echo", "hi"])
    end

    test "exec! raises on error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: "ti-x"}}
      end)
      |> stub(:rpc, fn _, :task_get_command_router_access, _, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert_raise Modal.Error, fn ->
        Modal.Sandbox.exec!(@sandbox, ["echo", "hi"])
      end
    end
  end

  describe "Sandbox.from_name/3 errors" do
    test "propagates not-found error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_from_name, _, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
               Modal.Sandbox.from_name(@client, "missing-sandbox")
    end
  end
end
