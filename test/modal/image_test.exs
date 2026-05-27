defmodule Modal.ImageTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @dockerfile ["FROM python:3.14-slim"]
  @image_id "im-abc123"

  defp stub_get_or_create do
    Modal.Client.Mock
    |> expect(:rpc, fn @client, :image_get_or_create, _req, _timeout ->
      {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: @image_id}}
    end)
  end

  # Helper: drive `stream_rpc_reduce` with a fixed list of responses,
  # respecting the reducer's `{:cont, _} | {:halt, _}` contract so the
  # production code's halt-on-failure path is exercised.
  defp stub_stream_with(responses) do
    Modal.Client.Mock
    |> expect(:stream_rpc_reduce, fn @client, :image_join_streaming, _req, initial, reducer, _timeout ->
      {:ok, Enum.reduce_while(responses, initial, reducer)}
    end)
  end

  describe "get_or_create/3" do
    test "returns :cached when stream has no task_logs" do
      stub_get_or_create()
      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: []}])

      assert {:ok, @image_id, :cached} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end

    test "returns :built when stream has task_logs" do
      stub_get_or_create()

      log = %Modal.Client.TaskLogs{data: "Step 1/3 : FROM python:3.14-slim"}
      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: [log]}])

      assert {:ok, @image_id, :built} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end

    test "returns error when build fails (with build logs in :metadata)" do
      stub_get_or_create()

      log = %Modal.Client.TaskLogs{data: "ERROR: pip install failed\n"}
      result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_FAILURE, exception: "OOM"}

      stub_stream_with([
        %Modal.Client.ImageJoinStreamingResponse{task_logs: [log], result: result}
      ])

      assert {:error, err} = Modal.Image.get_or_create(@client, @dockerfile)
      assert err.kind == :image_build_failed
      assert err.code == :GENERIC_STATUS_FAILURE
      assert err.metadata.logs == "ERROR: pip install failed\n"
      # Exception message surfaces the log tail.
      assert Exception.message(err) =~ "pip install failed"
    end

    test ":on_log callback receives each non-empty log chunk in order" do
      stub_get_or_create()

      logs = [
        %Modal.Client.TaskLogs{data: "Step 1/3 : FROM python:3.14-slim\n"},
        # Empty chunks should be skipped — task_logs is a noisy proto field
        # and a callback firing for "" would just be churn.
        %Modal.Client.TaskLogs{data: ""},
        %Modal.Client.TaskLogs{data: "Step 2/3 : RUN pip install pandas\n"}
      ]

      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: logs}])

      # Capture chunks into a process dict — keeps the test self-contained
      # without standing up an extra GenServer.
      parent = self()
      on_log = fn chunk -> send(parent, {:log, chunk}) end

      assert {:ok, @image_id, :built} =
               Modal.Image.get_or_create(@client, @dockerfile, on_log: on_log)

      assert_received {:log, "Step 1/3 : FROM python:3.14-slim\n"}
      assert_received {:log, "Step 2/3 : RUN pip install pandas\n"}
      refute_received {:log, ""}
    end

    test ":on_log fires before the error return on a failing build" do
      stub_get_or_create()

      log = %Modal.Client.TaskLogs{data: "ERROR: layer build failed\n"}
      result = %Modal.Client.GenericResult{status: :GENERIC_STATUS_FAILURE}

      stub_stream_with([
        %Modal.Client.ImageJoinStreamingResponse{task_logs: [log], result: result}
      ])

      parent = self()
      on_log = fn chunk -> send(parent, {:log, chunk}) end

      assert {:error, %Modal.Error{kind: :image_build_failed}} =
               Modal.Image.get_or_create(@client, @dockerfile, on_log: on_log)

      assert_received {:log, "ERROR: layer build failed\n"}
    end

    test "returns :validation error when :on_log isn't a 1-arity function" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Image.get_or_create(@client, @dockerfile, on_log: "not a function")

      assert msg =~ "must be a 1-arity function"
    end

    test "passes app_id in the request" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :image_get_or_create, req, _timeout ->
        assert req.app_id == "ap-xyz"
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: @image_id}}
      end)

      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: []}])

      assert {:ok, @image_id, :cached} =
               Modal.Image.get_or_create(@client, @dockerfile, app_id: "ap-xyz")
    end

    test "accepts :app (%Modal.App{}) in place of :app_id" do
      app = %Modal.App{id: "ap-xyz", client: @client}

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :image_get_or_create, req, _timeout ->
        assert req.app_id == "ap-xyz"
        {:ok, %Modal.Client.ImageGetOrCreateResponse{image_id: @image_id}}
      end)

      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: []}])

      assert {:ok, @image_id, :cached} =
               Modal.Image.get_or_create(@client, @dockerfile, app: app)
    end

    test ":on_log paired with Modal.Image.line_buffered/1 fires once per line" do
      stub_get_or_create()

      # Three chunks that don't align with line boundaries — the
      # line_buffered/1 wrapper must reassemble them into per-line
      # callback invocations.
      logs = [
        %Modal.Client.TaskLogs{data: "Step 1: "},
        %Modal.Client.TaskLogs{data: "FROM python\nStep 2: RUN pip install\nStep 3: "},
        %Modal.Client.TaskLogs{data: "RUN cmd\n"}
      ]

      stub_stream_with([%Modal.Client.ImageJoinStreamingResponse{task_logs: logs}])

      parent = self()
      cb = Modal.Image.line_buffered(fn line -> send(parent, {:line, line}) end)

      assert {:ok, @image_id, :built} =
               Modal.Image.get_or_create(@client, @dockerfile, on_log: cb)

      assert_received {:line, "Step 1: FROM python"}
      assert_received {:line, "Step 2: RUN pip install"}
      assert_received {:line, "Step 3: RUN cmd"}
      refute_received {:line, ""}
    end

    test "line_buffered/1 holds an unterminated trailing line in the buffer (not delivered)" do
      stub_get_or_create()

      # Stream ends without a trailing newline. The wrapper's contract
      # says: this remainder is held and not dispatched. Image builds
      # end with newlines in practice; the test pins the documented
      # tradeoff.
      stub_stream_with([
        %Modal.Client.ImageJoinStreamingResponse{
          task_logs: [%Modal.Client.TaskLogs{data: "completed\nbut no trailing newline"}]
        }
      ])

      parent = self()
      cb = Modal.Image.line_buffered(fn line -> send(parent, {:line, line}) end)

      assert {:ok, @image_id, :built} =
               Modal.Image.get_or_create(@client, @dockerfile, on_log: cb)

      assert_received {:line, "completed"}
      refute_received {:line, "but no trailing newline"}
    end

    test "propagates RPC errors from get_or_create" do
      Modal.Client.Mock
      |> stub(:rpc, fn @client, :image_get_or_create, _req, _timeout ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14, message: "unavailable"}} =
               Modal.Image.get_or_create(@client, @dockerfile)
    end
  end
end
