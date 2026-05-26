defmodule Modal.FunctionTest do
  @moduledoc """
  Tests for `Modal.Function.deploy_asgi/2` and `deploy_web_server/2`.

  The Function-deploy path fires THREE RPCs in sequence
  (Precreate → Create → AppPublish), each with load-bearing fields
  that, if wrong, silently break the routing instead of erroring:

    * Precreate must declare `DATA_FORMAT_ASGI` for input + output —
      otherwise Modal's edge wraps responses as async function calls
      (303 + `__modal_function_call_id`) instead of bridging HTTP↔ASGI.

    * Create must pass `existing_function_id` from the precreate
      response — the two RPCs are paired, not standalone.

    * AppPublish must include the `{tag => function_id}` map under
      `function_ids` — without it the URL returns
      "modal-http: invalid function call".

  These tests pin each of those invariants.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @app %Modal.App{id: "ap-test", name: "my-svc", client: @client}

  # ── deploy_asgi/2 — happy path ───────────────────────────────────

  describe "deploy_asgi/2 — three-RPC sequence" do
    test "fires Precreate → Create → AppPublish with the right shapes" do
      Modal.Client.Mock
      # 1. Precreate
      |> expect(:rpc, fn _, :function_precreate, req, _timeout ->
        assert req.app_id == "ap-test"
        assert req.function_name == "web"
        assert req.function_type == :FUNCTION_TYPE_FUNCTION
        assert req.webhook_config.type == :WEBHOOK_TYPE_ASGI_APP
        assert req.webhook_config.async_mode == :WEBHOOK_ASYNC_MODE_AUTO

        # The load-bearing format declaration — this is what flips
        # Modal's edge into ASGI direct-routing.
        assert req.supported_input_formats == [:DATA_FORMAT_ASGI]
        assert req.supported_output_formats == [:DATA_FORMAT_ASGI, :DATA_FORMAT_GENERATOR_DONE]

        {:ok,
         %Modal.Client.FunctionPrecreateResponse{
           function_id: "fu-precreated-id",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{
             web_url: "https://ivarvong--my-svc-web.modal.run"
           }
         }}
      end)
      # 2. Create
      |> expect(:rpc, fn _, :function_create, req, _timeout ->
        # MUST pass existing_function_id from precreate — they're paired.
        assert req.existing_function_id == "fu-precreated-id"
        assert req.app_id == "ap-test"

        f = req.function
        assert f.module_name == "entry"
        assert f.function_name == "serve"
        assert f.image_id == "im-test"
        assert f.app_name == "my-svc"
        assert f.definition_type == :DEFINITION_TYPE_FILE
        assert f.function_type == :FUNCTION_TYPE_FUNCTION
        assert f.webhook_config.type == :WEBHOOK_TYPE_ASGI_APP
        assert f.supported_input_formats == [:DATA_FORMAT_ASGI]
        assert f.mount_client_dependencies == true
        assert f._experimental_concurrent_cancellations == true
        assert f.timeout_secs == 300
        assert f.task_idle_timeout_secs == 300

        {:ok,
         %Modal.Client.FunctionCreateResponse{
           function_id: "fu-precreated-id",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{
             web_url: "https://ivarvong--my-svc-web.modal.run"
           }
         }}
      end)
      # 3. AppPublish — flips routing live
      |> expect(:rpc, fn _, :app_publish, req, _timeout ->
        assert req.app_id == "ap-test"
        assert req.name == "my-svc"
        assert req.app_state == :APP_STATE_DEPLOYED
        # The tag → function_id map. Tag becomes the URL slug.
        assert req.function_ids == %{"web" => "fu-precreated-id"}

        {:ok,
         %Modal.Client.AppPublishResponse{
           url: "https://modal.com/apps/ivarvong/main/deployed/my-svc",
           deployed_at: 123.45
         }}
      end)

      assert {:ok, fn_struct} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im-test",
                 module: "entry",
                 callable: "serve"
               )

      assert %Modal.Function{
               id: "fu-precreated-id",
               name: "web",
               web_url: "https://ivarvong--my-svc-web.modal.run",
               app: @app
             } = fn_struct
    end

    test "callable defaults to :name when omitted" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_precreate, _req, _ ->
        {:ok,
         %Modal.Client.FunctionPrecreateResponse{
           function_id: "fu-1",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
         }}
      end)
      |> expect(:rpc, fn _, :function_create, req, _ ->
        # No `:callable` passed → defaults to `:name`
        assert req.function.function_name == "serve"

        {:ok,
         %Modal.Client.FunctionCreateResponse{
           function_id: "fu-1",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
         }}
      end)
      |> expect(:rpc, fn _, :app_publish, _req, _ ->
        {:ok, %Modal.Client.AppPublishResponse{url: "https://dashboard", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "serve",
                 image_id: "im-x",
                 module: "entry"
               )
    end

    test "passes secret_ids + timeout overrides through to Create" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _req, _ ->
          {:ok,
           %Modal.Client.FunctionPrecreateResponse{
             function_id: "fu-x",
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
           }}

        _, :function_create, req, _ ->
          assert req.function.secret_ids == ["st-1", "st-2"]
          assert req.function.timeout_secs == 600
          assert req.function.task_idle_timeout_secs == 60

          {:ok,
           %Modal.Client.FunctionCreateResponse{
             function_id: "fu-x",
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
           }}

        _, :app_publish, _req, _ ->
          {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 secret_ids: ["st-1", "st-2"],
                 timeout_secs: 600,
                 idle_timeout_secs: 60
               )
    end
  end

  # ── deploy_asgi/2 — schedule + concurrency + warm pool ─────────

  describe "deploy_asgi/2 — schedule / concurrency / scaling opts" do
    # All four opts hit fields on the Function proto only — the
    # Precreate + AppPublish RPCs don't care. We mock those to no-ops
    # and inspect the Function in FunctionCreate.
    defp mock_three_rpcs_inspect_function(assertions) do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _req, _ ->
          {:ok,
           %Modal.Client.FunctionPrecreateResponse{
             function_id: "fu-x",
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
           }}

        _, :function_create, req, _ ->
          assertions.(req.function)

          {:ok,
           %Modal.Client.FunctionCreateResponse{
             function_id: "fu-x",
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://x"}
           }}

        _, :app_publish, _req, _ ->
          {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)
    end

    test "schedule: {:period, seconds: 15} sets Schedule.Period on the Function" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.Schedule{schedule_oneof: {:period, period}} = fn_proto.schedule
        assert period.seconds == 15.0
        # Unspecified fields default to 0 — pin them so we don't
        # accidentally start sending stale state from a parent struct.
        assert period.years == 0
        assert period.months == 0
        assert period.minutes == 0
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 schedule: {:period, seconds: 15}
               )
    end

    test "schedule: {:cron, expr} sets Schedule.Cron" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.Schedule{schedule_oneof: {:cron, cron}} = fn_proto.schedule
        assert cron.cron_string == "*/15 * * * * *"
        assert cron.timezone == ""
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 schedule: {:cron, "*/15 * * * * *"}
               )
    end

    test "schedule: {:cron, expr, timezone: ...} forwards the timezone" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.Schedule{schedule_oneof: {:cron, cron}} = fn_proto.schedule
        assert cron.timezone == "America/New_York"
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 schedule: {:cron, "0 9 * * *", timezone: "America/New_York"}
               )
    end

    test "target_concurrent_inputs + max_concurrent_inputs flow through to the proto" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert fn_proto.target_concurrent_inputs == 32
        assert fn_proto.max_concurrent_inputs == 64
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 target_concurrent_inputs: 32,
                 max_concurrent_inputs: 64
               )
    end

    test "min_containers maps to warm_pool_size on the proto" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert fn_proto.warm_pool_size == 1
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 min_containers: 1
               )
    end

    test "gpu: \"T4\" + gpu_count: 2 build the Resources/GPUConfig proto" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.Resources{} = res = fn_proto.resources
        assert %Modal.Client.GPUConfig{gpu_type: "T4", count: 2} = res.gpu_config
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 gpu: "T4",
                 gpu_count: 2
               )
    end

    test "memory_mb + cpu_millis + disk_mb flow into Resources" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.Resources{
                 memory_mb: 4096,
                 milli_cpu: 2500,
                 ephemeral_disk_mb: 10_000
               } = fn_proto.resources
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 memory_mb: 4096,
                 cpu_millis: 2500,
                 disk_mb: 10_000
               )
    end

    test "i6pn: true flips i6pn_enabled on the Function proto" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert fn_proto.i6pn_enabled == true
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 i6pn: true
               )
    end

    test "no resource opts leaves Function.resources nil (Modal uses defaults)" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        # The base plain-Function (no GPU/memory) doesn't allocate a
        # Resources struct — Modal defaults kick in server-side. Cls
        # is the exception (always sends Resources).
        assert fn_proto.resources == nil
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry"
               )
    end

    test "retries: N builds a FunctionRetryPolicy with Modal's default backoff" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert %Modal.Client.FunctionRetryPolicy{} = policy = fn_proto.retry_policy
        assert policy.retries == 3
        assert policy.initial_delay_ms == 1_000
        assert policy.max_delay_ms == 60_000
        assert policy.backoff_coefficient == 2.0
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 retries: 3
               )
    end

    test "omitting the new opts leaves the proto fields nil (no spurious defaults on the wire)" do
      mock_three_rpcs_inspect_function(fn fn_proto ->
        assert fn_proto.schedule == nil
        assert fn_proto.target_concurrent_inputs == 0
        assert fn_proto.max_concurrent_inputs == 0
        assert fn_proto.warm_pool_size == 0
        assert fn_proto.retry_policy == nil
      end)

      assert {:ok, _} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry"
               )
    end

    test "schedule: with malformed tuple returns validation error" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 schedule: {:every, 15}
               )
    end
  end

  # ── invoke / spawn / await ──────────────────────────────────────

  describe "spawn/4 + await/2" do
    @func %Modal.Function{
      id: "fu-compute",
      name: "compute",
      web_url: nil,
      app: %Modal.App{id: "ap-test", name: "test", client: :mock}
    }

    test "spawn/4 sets invocation_type ASYNC; invoke/5 sets SYNC" do
      # Modal differentiates spawn (fire-and-forget) from invoke
      # (the caller is waiting) via the invocation_type field. The
      # server uses it to optimize scheduling — wrong value can
      # surface as an opaque "module 'grpc' has no attribute
      # 'experimental'" error from the worker.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_ASYNC
        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-spawn"}}
      end)

      assert {:ok, %Modal.FunctionCall{id: "fc-spawn"}} =
               Modal.Function.spawn(@client, @func, [1])

      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_SYNC
        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-sync"}}
      end)
      |> expect(:rpc, fn _, :function_get_outputs, _, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data, Modal.Pickle.encode(0)}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      assert {:ok, 0} = Modal.Function.invoke(@client, @func, [1])
    end

    test "spawn/4 pickle-encodes (args_tuple, kwargs) and returns a FunctionCall" do
      # The wire shape Modal Python uses: pickle((args, kwargs)). We
      # must match opcode-for-opcode so the worker can `pickle.loads`
      # it and call `callable(*args, **kwargs)`.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        assert req.function_id == "fu-compute"
        assert req.function_call_type == :FUNCTION_CALL_TYPE_UNARY
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_ASYNC

        [%Modal.Client.FunctionPutInputsItem{idx: 0, input: input}] = req.pipelined_inputs
        assert input.final_input == true
        assert input.data_format == :DATA_FORMAT_PICKLE
        assert {:args, pickled} = input.args_oneof

        # The decoded args should be a tuple of positional args + a
        # kwargs dict. We pass kwargs as a map; Pickle round-trips
        # tuples to tuples.
        assert {{1, 2, 3}, %{"x" => 7}} = Modal.Pickle.decode!(pickled)

        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-123"}}
      end)

      assert {:ok, %Modal.FunctionCall{id: "fc-123", function: @func}} =
               Modal.Function.spawn(@client, @func, [1, 2, 3], %{"x" => 7})
    end

    test "await/2 long-polls FunctionGetOutputs and returns the decoded result" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_get_outputs, req, _ ->
        assert req.function_call_id == "fc-123"
        assert req.max_values == 1
        assert req.clear_on_success == true

        # Successful result: pickle(:hello) — we encode an Elixir
        # binary as a Python `str`.
        output = %Modal.Client.FunctionGetOutputsItem{
          idx: 0,
          input_id: "in-0",
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data, Modal.Pickle.encode("hello")}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      call = %Modal.FunctionCall{id: "fc-123", function: @func, client: @client}
      assert {:ok, "hello"} = Modal.Function.await(call)
    end

    test "await/2 surfaces remote exceptions as :function_failed" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_FAILURE,
            exception: "ZeroDivisionError: division by zero",
            traceback: "Traceback (most recent call last):\n  ..."
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      call = %Modal.FunctionCall{id: "fc-123", function: @func, client: @client}

      assert {:error, %Modal.Error{kind: :function_failed} = err} = Modal.Function.await(call)

      assert err.message == "ZeroDivisionError: division by zero"
      assert err.metadata.exception == "ZeroDivisionError: division by zero"
      assert err.metadata.traceback =~ "Traceback"
    end

    test "await/2 re-polls on empty outputs (server long-poll returned with no result)" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: []}}
      end)
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data, Modal.Pickle.encode(42)}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      call = %Modal.FunctionCall{id: "fc-123", function: @func, client: @client}
      assert {:ok, 42} = Modal.Function.await(call)
    end

    test "await/2 returns :output_expired when out of time with no result and no unfinished inputs" do
      # Empty result AND num_unfinished_inputs == 0 ⇒ the call's output is
      # gone (expired or its input was lost), not still running. We surface
      # :output_expired rather than masking it as a generic timeout — the
      # same distinction CPython's poll_function makes (OutputExpiredError).
      Modal.Client.Mock
      |> stub(:rpc, fn _c, :function_get_outputs, _req, _t ->
        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [], num_unfinished_inputs: 0}}
      end)

      call = %Modal.FunctionCall{id: "fc-expired", function: @func, client: @client}

      assert {:error, %Modal.Error{kind: :output_expired}} =
               Modal.Function.await(call, timeout_secs: 0.02)
    end

    test "await/2 returns :timeout (not :output_expired) when an input is still running" do
      # Empty result but num_unfinished_inputs > 0 ⇒ the call is still
      # running; we just ran out of patience. That stays a plain :timeout.
      Modal.Client.Mock
      |> stub(:rpc, fn _c, :function_get_outputs, _req, _t ->
        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [], num_unfinished_inputs: 1}}
      end)

      call = %Modal.FunctionCall{id: "fc-running", function: @func, client: @client}

      assert {:error, %Modal.Error{kind: :timeout}} =
               Modal.Function.await(call, timeout_secs: 0.02)
    end

    test "blob-stored outputs raise a clear error (not yet implemented)" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data_blob_id, "blob-abc"}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      call = %Modal.FunctionCall{id: "fc-123", function: @func, client: @client}

      assert {:error, %Modal.Error{kind: :function_failed, message: msg}} =
               Modal.Function.await(call)

      assert msg =~ "blob-abc"
      assert msg =~ "not yet implemented"
    end

    test "generator: true sets FUNCTION_TYPE_GENERATOR on Precreate + Create" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, req, _ ->
          assert req.function_type == :FUNCTION_TYPE_GENERATOR
          {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-gen"}}

        _, :function_create, req, _ ->
          assert req.function.function_type == :FUNCTION_TYPE_GENERATOR
          {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-gen"}}

        _, :app_publish, _, _ ->
          {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.Function.deploy_function(@client,
                 app: @app,
                 name: "gen",
                 image_id: "im",
                 module: "entry",
                 callable: "gen",
                 generator: true
               )
    end
  end

  describe "stream/2 + invoke_stream/5" do
    @gen_func %Modal.Function{
      id: "fu-gen",
      name: "chat",
      web_url: nil,
      app: %Modal.App{id: "ap-test", name: "test", client: :mock}
    }

    test "stream/2 server-streams DataChunks until GENERATOR_DONE" do
      # Generators use FunctionCallGetDataOut (server-streaming), NOT
      # FunctionGetOutputs polling. Each DataChunk carries one yielded
      # value; the terminator is a chunk with
      # `data_format: DATA_FORMAT_GENERATOR_DONE`.
      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _client,
                                       :function_call_get_data_out,
                                       req,
                                       acc,
                                       reducer,
                                       _timeout ->
        # Required call info — cursor begins at last_index 0.
        assert {:function_call_id, "fc-stream"} = req.call_info
        assert req.last_index == 0

        chunks = [
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data, Modal.Pickle.encode("hello ")},
            index: 1
          },
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data, Modal.Pickle.encode("world")},
            index: 2
          },
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data, Modal.Pickle.encode("!")},
            index: 3
          },
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_GENERATOR_DONE,
            index: 4
          }
        ]

        final =
          Enum.reduce_while(chunks, acc, fn chunk, a ->
            case reducer.(chunk, a) do
              {:cont, a2} -> {:cont, a2}
              {:halt, a2} -> {:halt, a2}
            end
          end)

        {:ok, final}
      end)

      call = %Modal.FunctionCall{id: "fc-stream", function: @gen_func, client: @client}
      assert ["hello ", "world", "!"] = Modal.Function.stream(call) |> Enum.to_list()
    end

    test "stream/2 raises on a blob-backed chunk instead of silently dropping it" do
      # Large yielded values are stored out-of-band and arrive as a
      # {:data_blob_id, _} chunk. Blob-fetch isn't implemented, so the
      # chunk must surface as a raised error (matching await/2's blob
      # error + stream/2's documented raise-on-error contract) rather
      # than vanishing and handing back a gappy result.
      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _client,
                                       :function_call_get_data_out,
                                       _req,
                                       acc,
                                       reducer,
                                       _timeout ->
        chunks = [
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data, Modal.Pickle.encode("first")},
            index: 1
          },
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data_blob_id, "blob-xyz"},
            index: 2
          }
        ]

        final =
          Enum.reduce_while(chunks, acc, fn chunk, a ->
            case reducer.(chunk, a) do
              {:cont, a2} -> {:cont, a2}
              {:halt, a2} -> {:halt, a2}
            end
          end)

        {:ok, final}
      end)

      call = %Modal.FunctionCall{id: "fc-stream", function: @gen_func, client: @client}

      err =
        assert_raise Modal.Error, fn ->
          Modal.Function.stream(call) |> Enum.to_list()
        end

      assert err.kind == :function_failed
      assert err.message =~ "blob-xyz"
      assert err.message =~ "not yet implemented"
    end

    test "invoke_stream/5 uses SYNC_LEGACY invocation type (load-bearing)" do
      # CPython's _functions.py:1678 — generators require SYNC_LEGACY,
      # not SYNC. Wrong invocation type → server returns 0 outputs.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_SYNC_LEGACY
        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-is"}}
      end)
      |> expect(:stream_rpc_reduce, fn _, :function_call_get_data_out, _, acc, reducer, _ ->
        chunks = [
          %Modal.Client.DataChunk{
            data_format: :DATA_FORMAT_PICKLE,
            data_oneof: {:data, Modal.Pickle.encode("hi")},
            index: 1
          },
          %Modal.Client.DataChunk{data_format: :DATA_FORMAT_GENERATOR_DONE, index: 2}
        ]

        final =
          Enum.reduce_while(chunks, acc, fn c, a ->
            case reducer.(c, a) do
              {:cont, a2} -> {:cont, a2}
              {:halt, a2} -> {:halt, a2}
            end
          end)

        {:ok, final}
      end)

      assert ["hi"] = Modal.Function.invoke_stream(@client, @gen_func, [1]) |> Enum.to_list()
    end

    test "invoke/5 is spawn + await" do
      # Single mock setup covering both RPCs; if either fires twice or
      # in the wrong order the mock will explode.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, _req, _ ->
        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-99"}}
      end)
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data, Modal.Pickle.encode([1, 2, 3])}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      assert {:ok, [1, 2, 3]} = Modal.Function.invoke(@client, @func, [40, 2])
    end
  end

  # ── deploy_many/2 — multi-function app with single AppPublish ───

  describe "deploy_many/2" do
    test "Precreate+Create each function, then ONE AppPublish with all IDs" do
      # The whole purpose: when an app has multiple Functions,
      # individual deploy_* calls would each fire AppPublish, and
      # AppPublish REPLACES the function registry — so the second
      # call silently de-registers the first. deploy_many/2 collects
      # all IDs and publishes once.

      precreate_count = :counters.new(1, [])
      create_count = :counters.new(1, [])
      publish_count = :counters.new(1, [])

      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _req, _ ->
          :counters.add(precreate_count, 1, 1)
          id = "fu-#{:counters.get(precreate_count, 1)}"

          {:ok,
           %Modal.Client.FunctionPrecreateResponse{
             function_id: id,
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://#{id}"}
           }}

        _, :function_create, _req, _ ->
          :counters.add(create_count, 1, 1)
          id = "fu-#{:counters.get(create_count, 1)}"

          {:ok,
           %Modal.Client.FunctionCreateResponse{
             function_id: id,
             handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://#{id}"}
           }}

        _, :app_publish, req, _ ->
          :counters.add(publish_count, 1, 1)

          # The load-bearing assertion: BOTH function_ids show up in
          # the single AppPublish.
          assert req.function_ids == %{"poll" => "fu-1", "web" => "fu-2"}

          {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, [poller, web]} =
               Modal.Function.deploy_many(@client, [
                 {:function,
                  app: @app,
                  name: "poll",
                  image_id: "im",
                  module: "entry",
                  callable: "poll",
                  schedule: {:period, seconds: 15}},
                 {:asgi,
                  app: @app,
                  name: "web",
                  image_id: "im",
                  module: "entry",
                  callable: "serve",
                  target_concurrent_inputs: 64}
               ])

      # Order preserved.
      assert poller.name == "poll"
      assert web.name == "web"

      # Exactly 2 Precreates, 2 Creates, 1 Publish.
      assert :counters.get(precreate_count, 1) == 2
      assert :counters.get(create_count, 1) == 2
      assert :counters.get(publish_count, 1) == 1
    end

    test "empty list returns {:ok, []} without hitting the wire" do
      # Permits programmatic deploy lists (e.g. when a feature flag
      # toggles a function off entirely).
      assert {:ok, []} = Modal.Function.deploy_many(@client, [])
    end

    test "rejects entries with mismatched :app" do
      other_app = %Modal.App{id: "ap-other", name: "other", client: @client}

      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_many(@client, [
                 {:function, app: @app, name: "a", image_id: "im", module: "entry"},
                 {:function, app: other_app, name: "b", image_id: "im", module: "entry"}
               ])
    end

    test "rejects unknown kind atoms" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_many(@client, [
                 {:not_a_kind, app: @app, name: "x", image_id: "im", module: "entry"}
               ])
    end

    test "first-function failure aborts before subsequent deploys" do
      precreate_count = :counters.new(1, [])

      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _req, _ ->
          :counters.add(precreate_count, 1, 1)
          {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{}} =
               Modal.Function.deploy_many(@client, [
                 {:function, app: @app, name: "a", image_id: "im", module: "entry"},
                 {:function, app: @app, name: "b", image_id: "im", module: "entry"}
               ])

      # Only the first deploy attempted — the loop short-circuited.
      assert :counters.get(precreate_count, 1) == 1
    end
  end

  # ── deploy_function/2 — non-webhook (scheduled poller / batch) ──

  describe "deploy_function/2 — non-webhook deploy" do
    test "sets webhook_config: nil + empty input/output formats (Modal defaults)" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, req, _ ->
          # The flag that toggles HTTP↔ASGI bridging must be ABSENT
          # for non-webhook deploys — otherwise Modal expects ASGI
          # payloads that a regular function-call producer doesn't
          # send.
          assert req.webhook_config == nil
          assert req.supported_input_formats == []
          assert req.supported_output_formats == []

          {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-poll"}}

        _, :function_create, req, _ ->
          assert req.function.webhook_config == nil
          assert req.function.supported_input_formats == []
          assert req.function.supported_output_formats == []

          # Schedule is the typical reason to use deploy_function/2 —
          # confirm it flows through.
          assert %Modal.Client.Schedule{schedule_oneof: {:period, p}} = req.function.schedule
          assert p.seconds == 15.0

          {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-poll"}}

        _, :app_publish, req, _ ->
          assert req.function_ids == %{"poll" => "fu-poll"}
          {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, %Modal.Function{web_url: nil}} =
               Modal.Function.deploy_function(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 callable: "poll",
                 schedule: {:period, seconds: 15}
               )
    end

    test "rejects webhook-only options like :requires_proxy_auth" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_function(@client,
                 app: @app,
                 name: "poll",
                 image_id: "im",
                 module: "entry",
                 requires_proxy_auth: true
               )
    end
  end

  # ── deploy_asgi/2 — error propagation ───────────────────────────

  describe "deploy_asgi/2 — error propagation" do
    test "Precreate failure aborts before Create / AppPublish" do
      Modal.Client.Mock
      # Only Precreate fires; verify_on_exit! enforces zero further calls.
      |> expect(:rpc, fn _, :function_precreate, _req, _ ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry"
               )
    end

    test "Create failure aborts before AppPublish" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_precreate, _req, _ ->
        {:ok,
         %Modal.Client.FunctionPrecreateResponse{
           function_id: "fu-x",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{}
         }}
      end)
      |> expect(:rpc, fn _, :function_create, _req, _ ->
        {:error, Modal.Error.grpc(3, "image_id not found")}
      end)

      # No :app_publish expectation — verify_on_exit! catches stray calls.
      assert {:error, %Modal.Error{kind: :grpc, code: 3}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im-missing",
                 module: "entry"
               )
    end

    test "AppPublish failure surfaces with the function technically created" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_precreate, _req, _ ->
        {:ok,
         %Modal.Client.FunctionPrecreateResponse{
           function_id: "fu-x",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{}
         }}
      end)
      |> expect(:rpc, fn _, :function_create, _req, _ ->
        {:ok,
         %Modal.Client.FunctionCreateResponse{
           function_id: "fu-x",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{}
         }}
      end)
      |> stub(:rpc, fn _, :app_publish, _req, _ ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 14}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry"
               )
    end
  end

  # ── Validation ──────────────────────────────────────────────────

  describe "deploy_asgi/2 — option validation" do
    test "missing :app returns :validation" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_asgi(@client,
                 name: "web",
                 image_id: "im",
                 module: "entry"
               )
    end

    test "missing :name returns :validation" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 image_id: "im",
                 module: "entry"
               )

      assert msg =~ ":name"
    end

    test "missing :image_id returns :validation" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 module: "entry"
               )
    end

    test "unknown option returns :validation" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Function.deploy_asgi(@client,
                 app: @app,
                 name: "web",
                 image_id: "im",
                 module: "entry",
                 not_a_real_option: true
               )
    end
  end

  # ── deploy_web_server/2 ─────────────────────────────────────────

  describe "deploy_web_server/2" do
    test "sets WEB_SERVER type + port + startup_timeout" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_precreate, req, _ ->
        assert req.webhook_config.type == :WEBHOOK_TYPE_WEB_SERVER

        {:ok,
         %Modal.Client.FunctionPrecreateResponse{
           function_id: "fu-w",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://ws"}
         }}
      end)
      |> expect(:rpc, fn _, :function_create, req, _ ->
        webhook = req.function.webhook_config
        assert webhook.type == :WEBHOOK_TYPE_WEB_SERVER
        assert webhook.web_server_port == 9000
        assert webhook.web_server_startup_timeout == 45.0

        {:ok,
         %Modal.Client.FunctionCreateResponse{
           function_id: "fu-w",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{web_url: "https://ws"}
         }}
      end)
      |> expect(:rpc, fn _, :app_publish, _req, _ ->
        {:ok, %Modal.Client.AppPublishResponse{url: "https://x", deployed_at: 0.0}}
      end)

      assert {:ok, %Modal.Function{name: "ws", web_url: "https://ws"}} =
               Modal.Function.deploy_web_server(@client,
                 app: @app,
                 name: "ws",
                 image_id: "im",
                 module: "entry",
                 web_server_port: 9000,
                 web_server_startup_timeout: 45
               )
    end
  end

  # ── get/4 ───────────────────────────────────────────────────────

  describe "get/4" do
    test "looks up by app + tag, populates struct" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_get, req, _ ->
        assert req.app_name == "my-svc"
        assert req.object_tag == "web"

        {:ok,
         %Modal.Client.FunctionGetResponse{
           function_id: "fu-found",
           handle_metadata: %Modal.Client.FunctionHandleMetadata{
             web_url: "https://x--my-svc-web.modal.run"
           }
         }}
      end)

      assert {:ok, fn_struct} = Modal.Function.get(@client, @app, "web")
      assert fn_struct.id == "fu-found"
      assert fn_struct.name == "web"
      assert fn_struct.web_url == "https://x--my-svc-web.modal.run"
      assert fn_struct.app == @app
    end
  end

  # ── Inspect ─────────────────────────────────────────────────────

  describe "Inspect" do
    test "shows id, name, url" do
      fn_struct = %Modal.Function{
        id: "fu-abc",
        name: "web",
        web_url: "https://x.modal.run",
        app: @app
      }

      str = inspect(fn_struct)
      assert str =~ "fu-abc"
      assert str =~ ~s|name: "web"|
      assert str =~ ~s|url: "https://x.modal.run"|
    end
  end
end
