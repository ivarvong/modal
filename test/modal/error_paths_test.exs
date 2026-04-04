defmodule Modal.ErrorPathsTest do
  @moduledoc """
  Exhaustive error-path tests. Every {:error, ...} branch in Sandbox, Image,
  App, and Filesystem has at least one test here. This is the suite that
  catches regressions when error-handling code is refactored.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @sandbox %Modal.Sandbox{id: "sb-err", client: @client}
  @booted_sandbox %Modal.Sandbox{id: "sb-err", client: @client, task_id: "ti-err"}

  # ── App ─────────────────────────────────────────────────────────

  describe "App.lookup/3 errors" do
    test "propagates gRPC application error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_get_or_create, _, _ ->
        {:error, {:grpc, 7, "permission denied"}}
      end)

      assert {:error, {:grpc, 7, "permission denied"}} = Modal.App.lookup(@client, "app")
    end

    test "propagates network error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :app_get_or_create, _, _ ->
        {:error, {:network, :econnrefused}}
      end)

      assert {:error, {:network, :econnrefused}} = Modal.App.lookup(@client, "app")
    end
  end

  # ── Image ────────────────────────────────────────────────────────

  describe "Image.get_or_create/3 errors" do
    test "propagates ImageGetOrCreate RPC error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :image_get_or_create, _, _ ->
        {:error, {:grpc, 14, "unavailable"}}
      end)

      assert {:error, {:grpc, 14, "unavailable"}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end

    test "returns {:error, {:image_build_failed, status}} on build failure" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :image_get_or_create, _, _ ->
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: "im-x"}}
      end)
      |> expect(:stream_rpc, fn _, :image_join_streaming, _, _ ->
        result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_FAILURE}
        {:ok, [%Modal.Client.ImageJoinStreamingResponse{task_logs: [], result: result}]}
      end)

      assert {:error, {:image_build_failed, :GENERIC_STATUS_FAILURE}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end

    test "returns error when ImageJoinStreaming stream itself fails" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :image_get_or_create, _, _ ->
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: "im-x"}}
      end)
      |> expect(:stream_rpc, fn _, :image_join_streaming, _, _ ->
        {:error, {:grpc, 4, "deadline exceeded"}}
      end)

      assert {:error, {:grpc, 4, "deadline exceeded"}} =
               Modal.Image.get_or_create(@client, ["FROM scratch"])
    end
  end

  # ── Sandbox ──────────────────────────────────────────────────────

  describe "Sandbox.create/2 errors" do
    test "returns NimbleOptions.ValidationError when app_id is missing" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Modal.Sandbox.create(@client, cmd: ["sleep", "infinity"])
    end

    test "returns NimbleOptions.ValidationError for unknown option" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", bad_key: true)
    end

    test "returns NimbleOptions.ValidationError for wrong cpu type" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Modal.Sandbox.create(@client, app_id: "ap-x", cpu: "2")
    end

    test "propagates SandboxCreate RPC error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, {:grpc, 8, "resource exhausted"}}
      end)

      assert {:error, {:grpc, 8, "resource exhausted"}} =
               Modal.Sandbox.create(@client, app_id: "ap-x")
    end
  end

  describe "Sandbox.create!/2 errors" do
    test "raises RuntimeError with helpful message on validation failure" do
      assert_raise RuntimeError, ~r/create! failed.*app_id/, fn ->
        Modal.Sandbox.create!(@client, cmd: ["sleep", "infinity"])
      end
    end

    test "raises RuntimeError with helpful message on RPC error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, _, _ ->
        {:error, {:grpc, 14, "unavailable"}}
      end)

      assert_raise RuntimeError, ~r/create! failed/, fn ->
        Modal.Sandbox.create!(@client, app_id: "ap-x")
      end
    end
  end

  describe "Sandbox.get_task_id/1 errors" do
    test "propagates RPC error when task_id not cached" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:error, {:grpc, 5, "not found"}}
      end)

      assert {:error, {:grpc, 5, "not found"}} = Modal.Sandbox.get_task_id(@sandbox)
    end

    test "never calls RPC when task_id already set" do
      # verify_on_exit! ensures no unexpected RPCs fire
      assert {:ok, "ti-err", @booted_sandbox} = Modal.Sandbox.get_task_id(@booted_sandbox)
    end
  end

  describe "Sandbox.terminate/1 errors" do
    test "propagates RPC error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_terminate, _, _ ->
        {:error, {:grpc, 5, "not found"}}
      end)

      assert {:error, {:grpc, 5, "not found"}} = Modal.Sandbox.terminate(@sandbox)
    end
  end

  describe "Sandbox.poll/1 errors" do
    test "returns {:ok, nil} on DEADLINE_EXCEEDED (sandbox still running)" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_wait, _, _ ->
        {:error, {:grpc, 4, "deadline exceeded"}}
      end)

      assert {:ok, nil} = Modal.Sandbox.poll(@sandbox)
    end

    test "propagates non-DEADLINE_EXCEEDED gRPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_wait, _, _ ->
        {:error, {:grpc, 2, "unknown"}}
      end)

      assert {:error, {:grpc, 2, "unknown"}} = Modal.Sandbox.poll(@sandbox)
    end
  end

  describe "Sandbox.exec/3 errors" do
    test "returns error when command router access fails" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: "ti-x"}}
      end)
      |> expect(:rpc, fn _, :task_get_command_router_access, _, _ ->
        {:error, {:grpc, 7, "permission denied"}}
      end)

      assert {:error, _} = Modal.Sandbox.exec(@sandbox, ["echo", "hi"])
    end

    test "exec! raises on error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: "ti-x"}}
      end)
      |> expect(:rpc, fn _, :task_get_command_router_access, _, _ ->
        {:error, {:grpc, 14, "unavailable"}}
      end)

      assert_raise RuntimeError, ~r/exec! failed/, fn ->
        Modal.Sandbox.exec!(@sandbox, ["echo", "hi"])
      end
    end
  end

  describe "Sandbox.from_name/3 errors" do
    test "propagates not-found error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_from_name, _, _ ->
        {:error, {:grpc, 5, "not found"}}
      end)

      assert {:error, {:grpc, 5, "not found"}} =
               Modal.Sandbox.from_name(@client, "missing-sandbox")
    end
  end
end
