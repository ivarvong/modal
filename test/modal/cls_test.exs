defmodule Modal.ClsTest do
  @moduledoc """
  Tests for `Modal.Cls` — Modal Class deployment + method dispatch.
  The wire shape is a Function (is_class=true, method_definitions
  set) plus a separate ClassCreate registration; both go into
  AppPublish under the same tag.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @app %Modal.App{id: "ap-test", name: "my-svc", client: @client}

  # ── deploy/2 — Precreate → Create → ClassCreate → AppPublish ────

  describe "deploy/2" do
    test "fires all four RPCs in order with the right class shapes" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_precreate, req, _ ->
        # The class-function's name is `<ClassName>.*` (literal `.*`,
        # NOT just `<ClassName>`) — Modal uses this wildcard slot to
        # mean "single Function handling all method dispatches."
        # Sending plain `<ClassName>` returns opaque INTERNAL errors.
        assert req.function_name == "LlamaServer.*"
        assert req.function_type == :FUNCTION_TYPE_FUNCTION
        # Method defs are required on Precreate too — server uses
        # them to allocate typed slots before FunctionCreate lands.
        assert Map.has_key?(req.method_definitions, "predict")

        {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-class"}}
      end)
      |> expect(:rpc, fn _, :function_create, req, _ ->
        f = req.function
        # Class-function name is `<ClassName>.*` (wildcard).
        assert f.function_name == "LlamaServer.*"
        assert f.implementation_name == "LlamaServer.*"
        # The four flags that mark this Function as a class function.
        assert f.is_class == true
        assert f.method_definitions_set == true
        assert f.class_parameter_info.format == :PARAM_SERIALIZATION_FORMAT_PICKLE
        # method_definitions is a map keyed by method name.
        assert Map.has_key?(f.method_definitions, "predict")
        assert Map.has_key?(f.method_definitions, "embed")

        %Modal.Client.MethodDefinition{function_name: predict_fn} =
          f.method_definitions["predict"]

        # Modal's convention for fully-qualified method names.
        assert predict_fn == "LlamaServer.predict"

        {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-class"}}
      end)
      |> expect(:rpc, fn _, :class_create, req, _ ->
        # CPython sends ONLY app_id + only_class_function: true.
        # Method metadata is on the class-function's
        # method_definitions, not on ClassCreate.
        assert req.only_class_function == true
        assert req.app_id == "ap-test"
        assert req.methods == []

        {:ok, %Modal.Client.ClassCreateResponse{class_id: "cs-llama"}}
      end)
      |> expect(:rpc, fn _, :app_publish, req, _ ->
        # AppPublish for class deploys uses two key conventions:
        # function_ids keyed by `<Callable>.*` (wildcard), class_ids
        # keyed by `<Callable>` (no suffix). Mixing them up returns
        # opaque INTERNAL errors from the server.
        assert req.function_ids == %{"LlamaServer.*" => "fu-class"}
        assert req.class_ids == %{"LlamaServer" => "cs-llama"}

        {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, %Modal.Cls{} = cls} =
               Modal.Cls.deploy(@client,
                 app: @app,
                 image_id: "im",
                 module: "entry",
                 callable: "LlamaServer",
                 method_names: ["predict", "embed"]
               )

      assert cls.id == "cs-llama"
      assert cls.function_id == "fu-class"
      assert cls.methods == ["predict", "embed"]
      assert cls.name == "LlamaServer"
    end

    test "publish: false skips AppPublish (multi-deploy pattern)" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _, _ ->
          {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-class"}}

        _, :function_create, _, _ ->
          {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-class"}}

        _, :class_create, _, _ ->
          {:ok, %Modal.Client.ClassCreateResponse{class_id: "cs-x"}}

        _, :app_publish, _, _ ->
          flunk("AppPublish should not have fired with publish: false")
      end)

      assert {:ok, _} =
               Modal.Cls.deploy(@client,
                 app: @app,
                 image_id: "im",
                 module: "entry",
                 callable: "X",
                 method_names: ["m"],
                 publish: false
               )
    end

    test "gpu: \"A100\" propagates to the class-function's Resources" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _, _ ->
          {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-class"}}

        _, :function_create, req, _ ->
          assert %Modal.Client.Resources{
                   gpu_config: %Modal.Client.GPUConfig{gpu_type: "A100", count: 1}
                 } = req.function.resources

          {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-class"}}

        _, :class_create, _, _ ->
          {:ok, %Modal.Client.ClassCreateResponse{class_id: "cs-x"}}

        _, :app_publish, _, _ ->
          {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.Cls.deploy(@client,
                 app: @app,
                 image_id: "im",
                 module: "entry",
                 callable: "Inference",
                 method_names: ["predict"],
                 gpu: "A100"
               )
    end

    test "scaling/concurrency opts flow into the class-function proto" do
      Modal.Client.Mock
      |> stub(:rpc, fn
        _, :function_precreate, _, _ ->
          {:ok, %Modal.Client.FunctionPrecreateResponse{function_id: "fu-class"}}

        _, :function_create, req, _ ->
          assert req.function.target_concurrent_inputs == 32
          assert req.function.warm_pool_size == 2

          {:ok, %Modal.Client.FunctionCreateResponse{function_id: "fu-class"}}

        _, :class_create, _, _ ->
          {:ok, %Modal.Client.ClassCreateResponse{class_id: "cs-x"}}

        _, :app_publish, _, _ ->
          {:ok, %Modal.Client.AppPublishResponse{url: "ok", deployed_at: 0.0}}
      end)

      assert {:ok, _} =
               Modal.Cls.deploy(@client,
                 app: @app,
                 image_id: "im",
                 module: "entry",
                 callable: "X",
                 method_names: ["m"],
                 target_concurrent_inputs: 32,
                 min_containers: 2
               )
    end
  end

  # ── invoke/spawn — method dispatch via FunctionInput.method_name ─

  describe "invoke/6" do
    @cls %Modal.Cls{
      id: "cs-llama",
      name: "llama",
      function_id: "fu-class",
      app: @app,
      methods: ["predict", "embed"]
    }

    test "sets FunctionInput.method_name to the called method" do
      # The whole point of Cls's invoke: the method name has to land
      # on the wire so Modal's worker can dispatch to the right
      # method on the class instance.
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        [%Modal.Client.FunctionPutInputsItem{input: input}] = req.pipelined_inputs
        assert input.method_name == "predict"
        assert req.function_id == "fu-class"
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_SYNC

        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-1"}}
      end)
      |> expect(:rpc, fn _, :function_get_outputs, _req, _ ->
        output = %Modal.Client.FunctionGetOutputsItem{
          result: %Modal.Client.GenericResult{
            status: :GENERIC_STATUS_SUCCESS,
            data_oneof: {:data, Modal.Pickle.encode("the result")}
          }
        }

        {:ok, %Modal.Client.FunctionGetOutputsResponse{outputs: [output]}}
      end)

      assert {:ok, "the result"} = Modal.Cls.invoke(@client, @cls, "predict", ["prompt"])
    end

    test "spawn/5 uses ASYNC invocation type and threads method_name through" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :function_map, req, _ ->
        [%{input: input}] = req.pipelined_inputs
        assert input.method_name == "embed"
        assert req.function_call_invocation_type == :FUNCTION_CALL_INVOCATION_TYPE_ASYNC

        {:ok, %Modal.Client.FunctionMapResponse{function_call_id: "fc-embed"}}
      end)

      assert {:ok, %Modal.FunctionCall{id: "fc-embed"}} =
               Modal.Cls.spawn(@client, @cls, "embed", ["text"])
    end

    test "rejects calls to methods not in :method_names" do
      assert_raise ArgumentError, ~r/unknown method "shutdown"/, fn ->
        Modal.Cls.invoke(@client, @cls, "shutdown", [])
      end
    end

    test "Inspect surfaces id + name + methods" do
      assert inspect(@cls) =~ "id: cs-llama"
      assert inspect(@cls) =~ ~s|name: "llama"|
      assert inspect(@cls) =~ ~s|methods: ["predict", "embed"]|
    end
  end

  # ── get/4 ───────────────────────────────────────────────────────

  describe "get/4" do
    test "looks up by app + tag, populates struct from handle_metadata" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :class_get, req, _ ->
        assert req.app_name == "my-svc"
        assert req.object_tag == "llama"
        assert req.only_class_function == true

        {:ok,
         %Modal.Client.ClassGetResponse{
           class_id: "cs-llama",
           handle_metadata: %Modal.Client.ClassHandleMetadata{
             class_function_id: "fu-class",
             methods: [
               %Modal.Client.ClassMethod{function_name: "predict"},
               %Modal.Client.ClassMethod{function_name: "embed"}
             ]
           }
         }}
      end)

      assert {:ok, %Modal.Cls{} = cls} = Modal.Cls.get(@client, @app, "llama")
      assert cls.id == "cs-llama"
      assert cls.function_id == "fu-class"
      assert cls.methods == ["predict", "embed"]
    end
  end
end
