defmodule Modal.SandboxTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @sandbox_id "sb-abc123"
  @task_id "ti-xyz789"

  defp sandbox, do: %Modal.Sandbox{id: @sandbox_id, client: @client}

  # Stub the task_id cache so it always misses — every test gets a cold
  # cache. The few tests that want a hit override this with their own
  # `expect/3`.
  setup do
    Mox.stub(Modal.Client.Mock, :lookup_task_id, fn _, _ -> :miss end)
    Mox.stub(Modal.Client.Mock, :cache_task_id, fn _, _, _ -> :ok end)
    :ok
  end

  # ── create/2 ────────────────────────────────────────────────────

  describe "create/2" do
    test "returns a Sandbox struct on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, %Modal.Sandbox{id: @sandbox_id, client: @client}} =
               Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")
    end

    test "sends cpu as millicores" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.resources.milli_cpu == 2000
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", cpu: 2.0)
    end

    test ":cpu_millis sends the exact value without truncation surprise" do
      # Fractional cores get truncated: 1.2345 * 1000 |> trunc == 1234.
      # :cpu_millis is the escape hatch for callers who want exact control.
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.resources.milli_cpu == 1500
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", cpu_millis: 1500)
    end

    test ":cpu and :cpu_millis together returns a :validation error" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 cpu: 1.5,
                 cpu_millis: 1500
               )

      assert msg =~ "either :cpu"
      assert msg =~ ":cpu_millis"
    end

    test "accepts %Modal.Volume{} struct in :volumes" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        [mount] = req.definition.volume_mounts
        assert mount.volume_id == "vo-abc"
        assert mount.mount_path == "/data"
        assert mount.read_only == true
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      vol = %Modal.Volume{id: "vo-abc", path: "/data", read_only: true}
      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", volumes: [vol])
    end

    test "still accepts a plain map in :volumes (backwards-compat)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        [mount] = req.definition.volume_mounts
        assert mount.volume_id == "vo-xyz"
        assert mount.mount_path == "/scratch"
        assert mount.read_only == false
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client,
        app_id: "ap-test",
        image_id: "im-test",
        volumes: [%{id: "vo-xyz", path: "/scratch"}]
      )
    end

    test "rejects a malformed :volumes entry with a :validation error" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 volumes: [%{name: "broken"}]
               )

      assert msg =~ "volume entry requires :id and :path"
    end

    test "rejects a non-struct, non-map :volumes entry with a :validation error" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 volumes: ["not a struct"]
               )

      assert msg =~ "%Modal.Volume{} structs or maps"
    end

    # ── :network_access — egress control via the NetworkAccess proto ──

    test "network_access: :open sets NetworkAccess{type: OPEN}" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert %Modal.Client.NetworkAccess{network_access_type: :OPEN} =
                 req.definition.network_access

        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client,
        app_id: "ap-test",
        image_id: "im-test",
        network_access: :open
      )
    end

    test "network_access: :blocked sets NetworkAccess{type: BLOCKED}" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert %Modal.Client.NetworkAccess{network_access_type: :BLOCKED} =
                 req.definition.network_access

        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client,
        app_id: "ap-test",
        image_id: "im-test",
        network_access: :blocked
      )
    end

    test "network_access: {:allowlist, cidrs} sets ALLOWLIST + allowed_cidrs" do
      cidrs = ["140.82.112.0/20", "143.55.64.0/20"]

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert %Modal.Client.NetworkAccess{
                 network_access_type: :ALLOWLIST,
                 allowed_cidrs: ^cidrs
               } = req.definition.network_access

        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client,
        app_id: "ap-test",
        image_id: "im-test",
        network_access: {:allowlist, cidrs}
      )
    end

    test "no network_access option leaves the proto field nil (Modal default)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert req.definition.network_access == nil
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")
    end

    test "network_access: {:allowlist, []} is rejected as a validation error" do
      # An empty allowlist would deny all egress — that's :blocked's
      # job. Refuse early rather than ship the confusing wire shape.
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 network_access: {:allowlist, []}
               )

      assert msg =~ "empty allowlist"
    end

    test "network_access: {:allowlist, [non_string]} is rejected" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 network_access: {:allowlist, [12_345]}
               )

      assert msg =~ "CIDR must be a string"
    end

    test "i6pn: true flips i6pn_enabled on the wire" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert req.definition.i6pn_enabled == true
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", i6pn: true)
    end

    test "i6pn defaults to false (proto field stays at false)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _ ->
        assert req.definition.i6pn_enabled == false
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")
    end

    test "network_access: garbage tuple is rejected" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 network_access: :everyone
               )
    end

    # ── :timeout_secs / :idle_timeout_secs (and their legacy aliases) ──

    test ":timeout_secs goes on the wire under its proto name" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.timeout_secs == 600
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", timeout_secs: 600)
    end

    test "legacy :timeout option is rejected (must use :timeout_secs)" do
      # We dropped the v0.1.0 :timeout / :idle_timeout legacy aliases
      # before going public — pin the deletion so a future refactor
      # doesn't accidentally re-add them. NimbleOptions surfaces an
      # unknown option as a `:validation` error.
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", timeout: 600)

      assert msg =~ "unknown options"
      assert msg =~ ":timeout"
    end

    test "idle_timeout_secs: nil leaves the proto field unset (no instant-death)" do
      # Bug we're fixing: a missing/0 idle_timeout used to send `0` on
      # the wire, which Modal interprets as "kill the sandbox the instant
      # the entrypoint goes idle." Unset on the wire = Modal default
      # = "no idle timeout."
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.idle_timeout_secs == nil
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")
    end

    test "idle_timeout_secs: 0 is treated as 'disabled' (also unset on the wire)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.idle_timeout_secs == nil
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", idle_timeout_secs: 0)
    end

    test "idle_timeout_secs: positive integer passes through" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.idle_timeout_secs == 60
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", idle_timeout_secs: 60)
    end

    test "legacy :idle_timeout option is rejected (must use :idle_timeout_secs)" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 idle_timeout: 60
               )

      assert msg =~ "unknown options"
      assert msg =~ ":idle_timeout"
    end

    test "coerces a single region string to a list" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.scheduler_placement.regions == ["us-east"]
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test", regions: "us-east")
    end

    test "returns validation error when app is missing" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client, cmd: ["sleep", "infinity"])

      assert msg =~ "missing app"
    end

    test "accepts :app (%Modal.App{}) as well as :app_id" do
      app = %Modal.App{id: "ap-from-struct", client: @client}

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.app_id == "ap-from-struct"
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, %Modal.Sandbox{}} =
               Modal.Sandbox.create(@client, app: app, image_id: "im-test")
    end

    test "rejects passing a %Modal.App{} under :app_id with a directional hint" do
      app = %Modal.App{id: "ap-x", client: @client}

      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client, app_id: app)

      assert msg =~ "use `app: %Modal.App{}`"
    end

    test "returns validation error for unknown option" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 unknown_opt: true
               )
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7, message: "permission denied"}} =
               Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")
    end
  end

  describe "create!/2" do
    test "returns the sandbox on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert %Modal.Sandbox{id: @sandbox_id} =
               Modal.Sandbox.create!(@client, app_id: "ap-test", image_id: "im-test")
    end

    test "raises on error" do
      Modal.Client.Mock
      |> stub(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert_raise Modal.Error, ~r/unavailable/, fn ->
        Modal.Sandbox.create!(@client, app_id: "ap-test", image_id: "im-test")
      end
    end
  end

  # ── get_task_id/1 ───────────────────────────────────────────────

  describe "get_task_id/1" do
    test "makes RPC when cache misses, populates cache, returns task_id" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        {:ok, %Modal.Client.SandboxGetTaskIdResponse{task_id: @task_id}}
      end)
      |> expect(:cache_task_id, fn @client, @sandbox_id, @task_id -> :ok end)

      assert {:ok, @task_id} = Modal.Sandbox.get_task_id(sandbox())
    end

    test "short-circuits without an RPC when cache hits" do
      # Override the default :miss stub with a hit for this sandbox.
      Modal.Client.Mock
      |> expect(:lookup_task_id, fn @client, @sandbox_id -> {:ok, @task_id} end)

      # No :rpc expectation — verify_on_exit! enforces zero RPCs.
      assert {:ok, @task_id} = Modal.Sandbox.get_task_id(sandbox())
    end

    test "propagates RPC errors and does NOT cache anything" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)
      # Override the default :cache_task_id stub so that any invocation
      # flunks. If the RPC fails the cache must NOT be touched.
      |> stub(:cache_task_id, fn _, _, _ ->
        flunk("cache_task_id must not be called when the RPC fails")
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5, message: "not found"}} =
               Modal.Sandbox.get_task_id(sandbox())
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
      |> stub(:rpc, fn @client, :sandbox_wait, _req, _timeout ->
        {:error, Modal.Error.grpc(4, "context deadline exceeded")}
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
    test "returns sandboxes as plain maps (proto struct not leaked)" do
      items = [
        %Modal.Client.SandboxInfo{id: "sb-1", app_id: "ap-x"},
        %Modal.Client.SandboxInfo{id: "sb-2", app_id: "ap-x"}
      ]

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_list, _req, _timeout ->
        {:ok, %Modal.Client.SandboxListResponse{sandboxes: items}}
      end)

      assert {:ok, [first, second]} = Modal.Sandbox.list(@client)
      assert is_map(first) and not is_struct(first)
      assert %{id: "sb-1", app_id: "ap-x"} = first
      assert %{id: "sb-2"} = second
      refute Map.has_key?(first, :__unknown_fields__)
    end

    test "passes filter options through" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_list, req, _timeout ->
        assert req.app_id == "ap-x"
        assert req.include_finished == true
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
      end)

      assert {:ok, []} =
               Modal.Sandbox.list(@client,
                 app_id: "ap-x",
                 include_finished: true,
                 environment_name: "staging"
               )
    end
  end

  # ── with_sandbox/3 ──────────────────────────────────────────────

  describe "with_sandbox/3" do
    test "creates, runs fun, terminates — happy path returns fun's value" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, req, _timeout ->
        assert req.sandbox_id == @sandbox_id
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      result =
        Modal.Sandbox.with_sandbox(
          @client,
          [app_id: "ap-test", image_id: "im-test"],
          fn sandbox ->
            assert %Modal.Sandbox{id: @sandbox_id} = sandbox
            :the_value
          end
        )

      assert result == :the_value
    end

    test "terminates even when fun raises (try/after)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, _req, _timeout ->
        # If this never fires, verify_on_exit! flags it.
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      assert_raise RuntimeError, "boom", fn ->
        Modal.Sandbox.with_sandbox(
          @client,
          [app_id: "ap-test", image_id: "im-test"],
          fn _sandbox ->
            raise "boom"
          end
        )
      end
    end

    test "raises on create failure (mirrors create!/2)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      # No :sandbox_terminate expected — never created, nothing to clean up.
      assert_raise Modal.Error, ~r/permission denied/, fn ->
        Modal.Sandbox.with_sandbox(@client, [app_id: "ap-test", image_id: "im-test"], fn _ ->
          :unreachable
        end)
      end
    end

    test "defaults :terminate_on_caller_exit to :silent (watchdog armed, no log)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, _req, _timeout ->
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      monitor_pid =
        Modal.Sandbox.with_sandbox(
          @client,
          [app_id: "ap-test", image_id: "im-test"],
          fn sandbox ->
            sandbox.monitor_pid
          end
        )

      # The watchdog was armed because the default kicked in.
      assert is_pid(monitor_pid)
    end

    test "caller can opt out via terminate_on_caller_exit: false" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, _req, _timeout ->
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      monitor_pid =
        Modal.Sandbox.with_sandbox(
          @client,
          [app_id: "ap-test", image_id: "im-test", terminate_on_caller_exit: false],
          fn sandbox -> sandbox.monitor_pid end
        )

      assert monitor_pid == nil
    end
  end

  # ── terminate_on_caller_exit ────────────────────────────────────

  describe "terminate_on_caller_exit:" do
    test "default false — no monitor process spawned, no auto-terminate" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, sandbox} =
               Modal.Sandbox.create(@client, app_id: "ap-test", image_id: "im-test")

      assert sandbox.monitor_pid == nil
    end

    test "true — spawns a monitor process whose pid lands on the struct" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, sandbox} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 terminate_on_caller_exit: true
               )

      assert is_pid(sandbox.monitor_pid)
      assert Process.alive?(sandbox.monitor_pid)

      # Clean up the monitor so it doesn't outlive the test and fire a
      # terminate against a non-existent sandbox.
      send(sandbox.monitor_pid, :cancel)
    end

    test "accepts :silent — watchdog enabled but no log fires" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      {:ok, sandbox} =
        Modal.Sandbox.create(@client,
          app_id: "ap-test",
          image_id: "im-test",
          terminate_on_caller_exit: :silent
        )

      assert is_pid(sandbox.monitor_pid)
      assert Process.alive?(sandbox.monitor_pid)

      send(sandbox.monitor_pid, :cancel)
    end

    test "accepts a Logger.level atom (:debug | :info | :warning | :error)" do
      Modal.Client.Mock
      |> expect(:rpc, 4, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      for level <- [:debug, :info, :warning, :error] do
        {:ok, sandbox} =
          Modal.Sandbox.create(@client,
            app_id: "ap-test",
            image_id: "im-test",
            terminate_on_caller_exit: level
          )

        assert is_pid(sandbox.monitor_pid),
               "level #{inspect(level)} did not enable the watchdog"

        send(sandbox.monitor_pid, :cancel)
      end
    end

    test "rejects nonsense values via NimbleOptions :in check" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.create(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 terminate_on_caller_exit: :loud
               )

      assert msg =~ "terminate_on_caller_exit"
    end

    test "monitor exits cleanly on :cancel (the path terminate/1 takes)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)

      {:ok, sandbox} =
        Modal.Sandbox.create(@client,
          app_id: "ap-test",
          image_id: "im-test",
          terminate_on_caller_exit: true
        )

      ref = Process.monitor(sandbox.monitor_pid)
      send(sandbox.monitor_pid, :cancel)

      assert_receive {:DOWN, ^ref, :process, _, :normal}, 1000
    end

    test "monitor fires terminate when the caller dies — exactly one RPC" do
      # End-to-end: spawn a caller, let it create a sandbox with the
      # watchdog enabled, then exit *without* calling terminate. The
      # monitor must invoke `:sandbox_terminate` exactly once. The
      # explicit Mox.allow on the monitor's pid is the bit that makes
      # this work under `async: true` — the watchdog runs in its own
      # process and would otherwise be denied by Mox's private mode.
      parent = self()

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, req, _timeout ->
        assert req.sandbox_id == @sandbox_id
        send(parent, :auto_terminated)
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      caller =
        spawn(fn ->
          # Wait for parent to grant Mox allowance before doing anything
          # that touches the mock.
          receive do
            :proceed -> :ok
          end

          {:ok, sandbox} =
            Modal.Sandbox.create(@client,
              app_id: "ap-test",
              image_id: "im-test",
              terminate_on_caller_exit: true
            )

          send(parent, {:sandbox_created, sandbox})

          # Block until parent says to die. Exits :normal — the
          # watchdog must still fire (any :DOWN reason triggers it).
          receive do
            :die_now -> :ok
          end
        end)

      Mox.allow(Modal.Client.Mock, self(), caller)
      send(caller, :proceed)

      assert_receive {:sandbox_created, sandbox}, 1000

      # Now that we know the monitor pid, allow it to call the mock too.
      Mox.allow(Modal.Client.Mock, self(), sandbox.monitor_pid)
      send(caller, :die_now)

      assert_receive :auto_terminated, 1000
    end
  end

  # ── run/2 ───────────────────────────────────────────────────────
  #
  # Full end-to-end coverage of run/2 needs the per-worker gRPC channel,
  # which is opened by `Modal.ContainerProcess.start/3` and isn't
  # mockable through the current seams. The contract tests + the
  # cloudflare-roundtrip script exercise the happy path against the
  # live API. These unit tests cover the argument validation and the
  # "create failed → don't terminate" invariant.

  describe "run/2" do
    test "returns :validation error when :cmd is missing" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.run(@client, app_id: "ap-test", image_id: "im-test")

      assert msg =~ "requires :cmd as a list of strings"
    end

    test "returns :validation error when :cmd is not a list of strings" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.run(@client,
                 app_id: "ap-test",
                 image_id: "im-test",
                 cmd: "echo hi"
               )

      assert msg =~ "requires :cmd as a list of strings"
    end

    test "does NOT terminate when create itself fails" do
      # No :sandbox_terminate expectation — verify_on_exit! enforces zero
      # cleanup calls when there's nothing to clean up. (Calling terminate
      # on a sandbox that never existed would log a spurious 404.)
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Sandbox.run(@client, app_id: "ap-test", image_id: "im-test", cmd: ["true"])
    end

    test "uses sleep-infinity entrypoint, not the caller's :cmd" do
      # The exec command is the caller's :cmd; the sandbox entrypoint is
      # forced to sleep so the box stays alive for the exec.
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, req, _timeout ->
        assert req.definition.entrypoint_args == ["sleep", "infinity"]
        # Return an error so we bail before reaching ContainerProcess.start,
        # which would try to open a real gRPC channel to the worker.
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      Modal.Sandbox.run(@client,
        app_id: "ap-test",
        image_id: "im-test",
        cmd: ["bash", "-c", "echo hi"]
      )
    end

    test "arms the caller-exit watchdog by default — terminates on a hard caller kill" do
      # run/2's `try/after` cleanup is skipped by a brutal kill, so run/2
      # also defaults `:terminate_on_caller_exit` to `:silent`. Park the
      # caller in the `SandboxGetTaskId` RPC (reached after create has
      # armed the watchdog), kill it, and assert the watchdog still fires
      # `SandboxTerminate`. The watchdog runs under Modal.WatchdogSupervisor
      # and reaches the mock via its `$callers` chain back to the caller.
      parent = self()

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        # create/2 has returned and the watchdog is armed. Park here
        # (mid-run, before the `after` cleanup) until the caller is killed.
        send(parent, :parked)

        receive do
          :never -> :ok
        end
      end)
      |> expect(:rpc, fn @client, :sandbox_terminate, req, _timeout ->
        assert req.sandbox_id == @sandbox_id
        send(parent, :auto_terminated)
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      caller =
        spawn(fn ->
          receive do
            :proceed -> :ok
          end

          Modal.Sandbox.run(@client, app_id: "ap-test", image_id: "im-test", cmd: ["true"])
        end)

      Mox.allow(Modal.Client.Mock, self(), caller)
      send(caller, :proceed)

      assert_receive :parked, 1000
      Process.exit(caller, :kill)
      assert_receive :auto_terminated, 1000
    end

    test "terminate_on_caller_exit: false opts out — a hard kill leaks (no watchdog)" do
      parent = self()

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_create, _req, _timeout ->
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
      end)
      |> expect(:rpc, fn @client, :sandbox_get_task_id, _req, _timeout ->
        send(parent, :parked)

        receive do
          :never -> :ok
        end
      end)
      # Signal if terminate ever fires. With the watchdog disabled it must
      # not — the refute below catches a wrongly-armed watchdog.
      |> stub(:rpc, fn @client, :sandbox_terminate, _req, _timeout ->
        send(parent, :auto_terminated)
        {:ok, %Modal.Client.SandboxTerminateResponse{}}
      end)

      caller =
        spawn(fn ->
          receive do
            :proceed -> :ok
          end

          Modal.Sandbox.run(@client,
            app_id: "ap-test",
            image_id: "im-test",
            cmd: ["true"],
            terminate_on_caller_exit: false
          )
        end)

      Mox.allow(Modal.Client.Mock, self(), caller)
      send(caller, :proceed)

      assert_receive :parked, 1000
      Process.exit(caller, :kill)
      refute_receive :auto_terminated, 200
    end
  end

  # ── exec_streaming/3 + raise_on_failure!/1 ──────────────────────
  #
  # Full end-to-end exec_streaming needs the per-worker gRPC channel
  # (opened by ContainerProcess.start/3 → connect_to_worker via real
  # GRPC.Stub.connect), which isn't mockable through the current
  # seams. These tests cover the wrapper logic that runs OUTSIDE that
  # boundary: the bang-variant pattern-match branches (extracted as
  # raise_on_failure!/1 for direct test surface) and the
  # transport-error propagation from upstream get_task_id.

  describe "raise_on_failure!/1" do
    test "returns the result unchanged on :code 0 (happy path)" do
      result = %{stdout: "hi\n", stderr: "", code: 0}
      assert ^result = Modal.Sandbox.raise_on_failure!({:ok, result})
    end

    test "raises :exec_failed on non-zero exit, with stdout/stderr in metadata" do
      err =
        assert_raise Modal.Error, fn ->
          Modal.Sandbox.raise_on_failure!(
            {:ok, %{stdout: "partial\n", stderr: "boom\n", code: 42}}
          )
        end

      assert err.kind == :exec_failed
      assert err.code == 42
      assert err.metadata.stdout == "partial\n"
      assert err.metadata.stderr == "boom\n"
      # Stderr tail surfaces in the exception message — caller doesn't
      # have to crack open metadata to see what went wrong.
      assert Exception.message(err) =~ "boom"
    end

    test "raises :exec_unknown_status when code is nil (worker didn't report)" do
      err =
        assert_raise Modal.Error, fn ->
          Modal.Sandbox.raise_on_failure!(
            {:ok, %{stdout: "started\n", stderr: "killed: 9\n", code: nil}}
          )
        end

      assert err.kind == :exec_unknown_status
      assert err.metadata.stdout == "started\n"
      assert err.metadata.stderr == "killed: 9\n"
    end

    test "re-raises a transport %Modal.Error{} as-is" do
      transport_err = Modal.Error.grpc(14, "unavailable")

      err =
        assert_raise Modal.Error, fn ->
          Modal.Sandbox.raise_on_failure!({:error, transport_err})
        end

      assert err.kind == :grpc
      assert err.code == 14
    end
  end

  describe "exec_streaming/3 — upstream-error propagation" do
    test "returns the :grpc error from get_task_id without trying to connect" do
      # No TaskGetCommandRouterAccess expectation — exec_streaming must
      # short-circuit at get_task_id and never try to open the worker
      # channel (which would fail differently and obscure the real
      # cause).
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Sandbox.exec_streaming(sandbox(), ["echo", "hi"])
    end

    test "bang variant raises on the same upstream error" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_get_task_id, _, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert_raise Modal.Error, ~r/permission/, fn ->
        Modal.Sandbox.exec_streaming!(sandbox(), ["echo", "hi"])
      end
    end
  end

  # ── from_name/3 ─────────────────────────────────────────────────

  describe "tunnels/1" do
    test "returns a map keyed by container_port with %Modal.Tunnel{} structs" do
      tunnels_proto = [
        %Modal.Client.TunnelData{
          host: "ta-abc-8000-xyz.w.modal.host",
          port: 443,
          container_port: 8000,
          unencrypted_host: nil,
          unencrypted_port: nil
        },
        %Modal.Client.TunnelData{
          host: "ta-abc-9090-xyz.w.modal.host",
          port: 443,
          container_port: 9090
        }
      ]

      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_tunnels, _req, _timeout ->
        {:ok, %Modal.Client.SandboxGetTunnelsResponse{tunnels: tunnels_proto}}
      end)

      assert {:ok, tunnels} = Modal.Sandbox.tunnels(sandbox())

      assert is_map(tunnels)
      assert map_size(tunnels) == 2

      # tunnels[8000] is the natural call shape (matches Python's
      # dict-by-container-port after v0.64.153).
      assert %Modal.Tunnel{
               host: "ta-abc-8000-xyz.w.modal.host",
               port: 443,
               container_port: 8000
             } = tunnels[8000]

      assert %Modal.Tunnel{container_port: 9090} = tunnels[9090]
    end

    test "returns an empty map when no ports are exposed" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_tunnels, _req, _timeout ->
        {:ok, %Modal.Client.SandboxGetTunnelsResponse{tunnels: []}}
      end)

      assert {:ok, tunnels} = Modal.Sandbox.tunnels(sandbox())
      assert tunnels == %{}
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> stub(:rpc, fn @client, :sandbox_get_tunnels, _req, _timeout ->
        {:error, Modal.Error.grpc(4, "deadline exceeded")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 4}} = Modal.Sandbox.tunnels(sandbox())
    end
  end

  describe "from_name/3" do
    test "returns sandbox struct on success — carries the looked-up name" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_from_name, req, _timeout ->
        assert req.sandbox_name == "my-worker"
        {:ok, %Modal.Client.SandboxGetFromNameResponse{sandbox_id: @sandbox_id}}
      end)

      assert {:ok, %Modal.Sandbox{id: @sandbox_id, name: "my-worker"}} =
               Modal.Sandbox.from_name(@client, "my-worker")
    end

    test "Inspect surfaces both id and the looked-up name" do
      sb = %Modal.Sandbox{id: @sandbox_id, name: "my-worker", client: @client}
      assert inspect(sb) =~ "id: #{@sandbox_id}"
      assert inspect(sb) =~ ~s|name: "my-worker"|
    end

    test "Inspect of a nameless sandbox (created via create/2) omits the name field" do
      sb = %Modal.Sandbox{id: @sandbox_id, client: @client}
      assert inspect(sb) == "#Modal.Sandbox<id: #{@sandbox_id}>"
    end

    test "returns error when not found" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_get_from_name, _req, _timeout ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5, message: "not found"}} =
               Modal.Sandbox.from_name(@client, "missing")
    end
  end

  # ── stdin_write/3 — :offset option, proto field :index ──────────

  describe "stdin_write/3" do
    test ":offset propagates to the proto's :index field (default 0)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_stdin_write, req, _timeout ->
        assert req.input == "hello"
        assert req.index == 0
        assert req.eof == false
        {:ok, %Modal.Client.SandboxStdinWriteResponse{}}
      end)

      assert :ok = Modal.Sandbox.stdin_write(sandbox(), "hello")
    end

    test "explicit :offset is honored" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_stdin_write, req, _timeout ->
        assert req.index == 42
        {:ok, %Modal.Client.SandboxStdinWriteResponse{}}
      end)

      assert :ok = Modal.Sandbox.stdin_write(sandbox(), "more", offset: 42)
    end

    test ":eof: true closes stdin in the same write" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :sandbox_stdin_write, req, _timeout ->
        assert req.eof == true
        {:ok, %Modal.Client.SandboxStdinWriteResponse{}}
      end)

      assert :ok = Modal.Sandbox.stdin_write(sandbox(), "", eof: true)
    end
  end

  # ── exec_streaming/3 — unknown-opt validation ───────────────────

  describe "exec_streaming/3 option validation" do
    test "an unknown option (e.g. :on_log copied from Image) returns :validation" do
      # No RPC expectations — validation must short-circuit before any
      # network call.
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Sandbox.exec_streaming(sandbox(), ["echo", "hi"], on_log: &IO.write/1)

      assert msg =~ ":on_log"
      assert msg =~ "Valid options"
    end
  end
end
