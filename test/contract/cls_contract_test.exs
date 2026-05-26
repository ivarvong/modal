defmodule Modal.Contract.ClsTest do
  @moduledoc """
  Validates the full `Modal.Cls` deploy + method-invoke lifecycle
  against live Modal. Pins the six CPython wire-shape conventions
  the unit tests assert (any drift on Modal's side surfaces here as
  an opaque `gRPC INTERNAL: please contact support` — the same way
  it surfaced during dev when our shape was wrong):

    1. `function_name` = `<Callable>.*` (literal wildcard) on
       Precreate + Create.
    2. `class_parameter_info.format` = `PICKLE` (CPython @app.cls
       default).
    3. `MethodDefinition` with all five fields populated, including
       `function_schema` and PICKLE+CBOR formats.
    4. `Function.resources` (with empty gpu_config),
       `autoscaler_settings`, `object_dependencies` all present.
    5. `ClassCreate` with ONLY `app_id` + `only_class_function:
       true`.
    6. `AppPublish` with `function_ids` keyed by `<Callable>.*` and
       `class_ids` keyed by `<Callable>`.

  Also validates the method-dispatch path:
    - `FunctionInput.method_name` flows to the worker; methods are
      called on the SAME class instance (state visible across method
      names within a container).
    - `Modal.Cls.get/4` retrieves a previously deployed class by
      `callable` (Modal's lookup tag for classes).
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 180_000

  # Toy class with @enter/@exit + state + two methods. The whole
  # spike content from scripts/_cls_spike.exs distilled into a test.
  @entry_py """
  import modal, os, time

  class ContractCounter:
      @modal.enter()
      def boot(self):
          self.boot_at = time.time()
          self.calls = 0

      @modal.exit()
      def shutdown(self):
          pass

      @modal.method()
      def hello(self):
          self.calls += 1
          return {
              "task":   os.environ.get("MODAL_TASK_ID", "?"),
              "calls":  self.calls,
              "uptime": round(time.time() - self.boot_at, 2),
          }

      @modal.method()
      def add(self, a, b):
          self.calls += 1
          return a + b

      @modal.method()
      def boom(self):
          raise RuntimeError("expected — Cls contract test")
  """

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, Support.app_name())

    {:ok, image_id, _} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM python:3.12-slim",
          "RUN pip install --no-cache-dir modal",
          "RUN cat > /root/entry.py <<'PYEOF'\n" <> @entry_py <> "PYEOF"
        ],
        app: app
      )

    {:ok, cls} =
      Modal.Cls.deploy(client,
        app: app,
        image_id: image_id,
        module: "entry",
        callable: "ContractCounter",
        method_names: ["hello", "add", "boom"]
      )

    %{client: client, app: app, cls: cls}
  end

  test "deploy returns a Cls struct with the documented ID prefixes", %{cls: cls} do
    assert %Modal.Cls{} = cls
    assert String.starts_with?(cls.id, "cs-")
    assert String.starts_with?(cls.function_id, "fu-")
    assert cls.name == "ContractCounter"
    assert cls.methods == ["hello", "add", "boom"]
  end

  test "method invoke with positional args", %{client: client, cls: cls} do
    assert {:ok, 5} = Modal.Cls.invoke(client, cls, "add", [2, 3])
  end

  test "method invoke with no args returns a structured dict", %{client: client, cls: cls} do
    assert {:ok, %{"task" => task, "calls" => calls, "uptime" => uptime}} =
             Modal.Cls.invoke(client, cls, "hello", [])

    assert String.starts_with?(task, "ta-")
    assert is_integer(calls) and calls >= 1
    assert is_float(uptime) and uptime >= 0.0
  end

  test "remote exception inside a method → :function_failed", %{client: client, cls: cls} do
    assert {:error, %Modal.Error{} = err} = Modal.Cls.invoke(client, cls, "boom", [])
    assert err.kind == :function_failed
    assert err.message =~ "RuntimeError"
  end

  test "spawn → await round-trip", %{client: client, cls: cls} do
    {:ok, call} = Modal.Cls.spawn(client, cls, "add", [40, 2])
    assert {:ok, 42} = Modal.Function.await(call)
  end

  test "unknown method rejected client-side (no wire call)", %{client: client, cls: cls} do
    assert_raise ArgumentError, ~r/unknown method "drop_database"/, fn ->
      Modal.Cls.invoke(client, cls, "drop_database", [])
    end
  end

  test "Modal.Cls.get/4 retrieves the deployed class by callable", %{
    client: client,
    app: app,
    cls: cls
  } do
    assert {:ok, fetched} = Modal.Cls.get(client, app, "ContractCounter")
    # class_id is stable across redeploys (function_id may rotate).
    assert fetched.id == cls.id
    assert %Modal.Cls{} = fetched
  end
end
