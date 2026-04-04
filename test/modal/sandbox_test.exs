defmodule Modal.SandboxTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @sandbox_id "sb-abc123"
  @task_id "ti-xyz789"

  defp sandbox(opts \\ []),
    do: %Modal.Sandbox{id: @sandbox_id, client: @client, task_id: opts[:task_id]}

  # ── create/2 ────────────────────────────────────────────────────

  describe "create/2" do
    test "returns a Sandbox struct on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, %Modal.Sandbox{id: @sandbox_id, client: @client}} =
               Modal.Sandbox.create(@client, app_id: "ap-test")
    end

    test "sends cpu as millicores" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.resources.milli_cpu == 2000
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", cpu: 2.0)
    end

    test "coerces a single region string to a list" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.scheduler_placement.regions == ["us-east"]
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", regions: "us-east")
    end

    test "returns validation error when app_id is missing" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Modal.Sandbox.create(@client, cmd: ["sleep", "infinity"])
    end

    test "returns validation error for unknown option" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Modal.Sandbox.create(@client, app_id: "ap-test", unknown_opt: true)
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, {:grpc, 7, "permission denied"}}
      end)

      assert {:error, {:grpc, 7, "permission denied"}} =
               Modal.Sandbox.create(@client, app_id: "ap-test")
    end
  end

  describe "create!/2" do
    test "returns the sandbox on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert %Modal.Sandbox{id: @sandbox_id} = Modal.Sandbox.create!(@client, app_id: "ap-test")
    end

    test "raises on error" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, {:grpc, 14, "unavailable"}}
      end)

      assert_raise RuntimeError, ~r/create! failed/, fn ->
        Modal.Sandbox.create!(@client, app_id: "ap-test")
      end
    end
  end

  # ── get_task_id/1 ───────────────────────────────────────────────

  describe "get_task_id/1" do
    test "makes RPC when task_id is nil, returns updated sandbox" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: @task_id}}
      end)

      assert {:ok, @task_id, %Modal.Sandbox{task_id: @task_id}} =
               Modal.Sandbox.get_task_id(sandbox())
    end

    test "skips RPC and returns immediately when task_id already set" do
      # No mock expectations — any RPC call would fail verify_on_exit!
      sb = sandbox(task_id: @task_id)
      assert {:ok, @task_id, ^sb} = Modal.Sandbox.get_task_id(sb)
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        {:error, {:grpc, 5, "not found"}}
      end)

      assert {:error, {:grpc, 5, "not found"}} = Modal.Sandbox.get_task_id(sandbox())
    end
  end

  # ── terminate/1 ─────────────────────────────────────────────────

  describe "terminate/1" do
    test "sends terminate RPC and returns :ok" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_terminate, req, _timeout ->
        assert req.sandbox_id == @sandbox_id
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      assert :ok = Modal.Sandbox.terminate(sandbox())
    end
  end

  # ── poll/1 ──────────────────────────────────────────────────────

  describe "poll/1" do
    test "returns {:ok, nil} when sandbox is still running (DEADLINE_EXCEEDED)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_wait, _req, _timeout ->
        {:error, {:grpc, 4, "context deadline exceeded"}}
      end)

      assert {:ok, nil} = Modal.Sandbox.poll(sandbox())
    end

    test "returns {:ok, nil} when result field is nil" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_wait, _req, _timeout ->
        {:ok, %Modal.Client.SandboxWaitResponse{result: nil}}
      end)

      assert {:ok, nil} = Modal.Sandbox.poll(sandbox())
    end

    test "returns {:ok, resp} when sandbox has finished" do
      result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_SUCCESS}

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_wait, _req, _timeout ->
        {:ok, %Modal.Client.SandboxWaitResponse{result: result}}
      end)

      assert {:ok, %Modal.Client.SandboxWaitResponse{result: ^result}} =
               Modal.Sandbox.poll(sandbox())
    end
  end

  # ── list/2 ──────────────────────────────────────────────────────

  describe "list/2" do
    test "returns list of sandboxes" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_list, _req, _timeout ->
        {:ok, %Modal.Client.SandboxListResponse{sandboxes: [%{id: "sb-1"}, %{id: "sb-2"}]}}
      end)

      assert {:ok, [%{id: "sb-1"}, %{id: "sb-2"}]} = Modal.Sandbox.list(@client)
    end
  end

  # ── from_name/3 ─────────────────────────────────────────────────

  describe "from_name/3" do
    test "returns sandbox struct on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_from_name, req, _timeout ->
        assert req.sandbox_name == "my-worker"
        {:ok, %Modal.Client.SandboxGetFromNameResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, %Modal.Sandbox{id: @sandbox_id}} =
               Modal.Sandbox.from_name(@client, "my-worker")
    end

    test "returns error when not found" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_from_name, _req, _timeout ->
        {:error, {:grpc, 5, "not found"}}
      end)

      assert {:error, {:grpc, 5, "not found"}} =
               Modal.Sandbox.from_name(@client, "missing")
    end
  end
end
