defmodule Modal.Contract.FunctionTest do
  @moduledoc """
  Validates that Modal.FunctionTest mocks match the real API for the
  full deploy + invoke / spawn / await lifecycle.

  Asserted contracts:
    - `FunctionPrecreate` + `FunctionCreate` + `AppPublish` for a
      non-webhook function (the `deploy_function/2` path) returns IDs
      matching the documented prefixes.
    - `Modal.Function.invoke/5` round-trips positional args + kwargs;
      atom kwarg keys auto-stringify.
    - Remote Python exceptions surface as `:function_failed`.
    - `Modal.Function.spawn/4` returns a handle that
      `Modal.Function.await/2` resolves correctly — even when await
      runs from a different process.
    - The `FunctionGetOutputs` polling loop with `last_entry_id: "0-0"`
      survives a spawn → drain round-trip (the gotcha caught in v0.3
      that surfaced as `INVALID_ARGUMENT: No last_entry_id provided`).
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  import Modal.Contract.Support, only: [assert_struct_shape: 2]
  @moduletag :contract
  @moduletag timeout: 180_000

  # A trivial Python module: enough callables to exercise sync /
  # kwargs / exception / spawn / generator paths.
  @entry_py """
  def square(n):
      return n * n

  def add(a, b, c=0):
      return a + b + c

  def boom():
      raise ValueError("expected — contract test for :function_failed")

  def echo(*args, **kwargs):
      return {"args": list(args), "kwargs": kwargs}

  def count_to(n):
      for i in range(n):
          yield i

  def boom_gen(n):
      raise RuntimeError("expected — generator contract test")
      yield n  # unreachable; the yield just makes boom_gen a generator
  """

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, Support.app_name())

    # Image cached after first run by Modal's image cache (content
    # hash); subsequent runs of this test suite reuse instantly.
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

    {:ok, [square, add, boom, echo, count_to, boom_gen]} =
      Modal.Function.deploy_many(client, [
        {:function,
         app: app,
         name: "contract-square",
         image_id: image_id,
         module: "entry",
         callable: "square"},
        {:function,
         app: app, name: "contract-add", image_id: image_id, module: "entry", callable: "add"},
        {:function,
         app: app, name: "contract-boom", image_id: image_id, module: "entry", callable: "boom"},
        {:function,
         app: app, name: "contract-echo", image_id: image_id, module: "entry", callable: "echo"},
        {:function,
         app: app,
         name: "contract-count-to",
         image_id: image_id,
         module: "entry",
         callable: "count_to",
         generator: true},
        {:function,
         app: app,
         name: "contract-boom-gen",
         image_id: image_id,
         module: "entry",
         callable: "boom_gen",
         generator: true}
      ])

    %{
      client: client,
      app: app,
      square: square,
      add: add,
      boom: boom,
      echo: echo,
      count_to: count_to,
      boom_gen: boom_gen
    }
  end

  test "deploy_function returns a Modal.Function struct with the documented shape", %{
    square: f
  } do
    assert %Modal.Function{} = f

    assert_struct_shape(f, %{
      id: {:string_prefix, "fu-"},
      name: "contract-square",
      web_url: {:nil_or, :string},
      app: {:struct, Modal.App}
    })
  end

  test "FunctionMapResponse shape", %{client: client, square: f} do
    {:ok, resp} =
      Modal.Client.rpc(
        client,
        :function_map,
        %Modal.Client.FunctionMapRequest{
          function_id: f.id,
          function_call_type: :FUNCTION_CALL_TYPE_UNARY,
          function_call_invocation_type: :FUNCTION_CALL_INVOCATION_TYPE_SYNC,
          pipelined_inputs: [
            %Modal.Client.FunctionPutInputsItem{
              idx: 0,
              input: %Modal.Client.FunctionInput{
                args_oneof: {:args, Modal.Pickle.encode({{7}, %{}})},
                data_format: :DATA_FORMAT_PICKLE,
                final_input: true
              }
            }
          ]
        }
      )

    assert_struct_shape(resp, %{function_call_id: {:string_prefix, "fc-"}})
  end

  test "invoke/5 with positional args", %{client: client, square: f} do
    assert {:ok, 49} = Modal.Function.invoke(client, f, [7])
  end

  test "invoke/5 with kwargs (atom keys auto-stringify)", %{client: client, add: f} do
    assert {:ok, 15} = Modal.Function.invoke(client, f, [10, 2], %{c: 3})
  end

  test "invoke/5 with kwargs only", %{client: client, add: f} do
    assert {:ok, 5} = Modal.Function.invoke(client, f, [], %{a: 2, b: 3})
  end

  test "remote exception → {:error, %Modal.Error{kind: :function_failed}}", %{
    client: client,
    boom: f
  } do
    assert {:error, %Modal.Error{} = err} = Modal.Function.invoke(client, f, [])
    assert err.kind == :function_failed
    assert err.message =~ "ValueError"
    assert err.metadata.exception =~ "expected"
    assert is_binary(err.metadata.traceback) and err.metadata.traceback != ""
  end

  test "spawn → await round-trip (the last_entry_id: \"0-0\" path)", %{
    client: client,
    square: f
  } do
    {:ok, %Modal.FunctionCall{id: call_id}} = Modal.Function.spawn(client, f, [9])
    assert String.starts_with?(call_id, "fc-")

    call = %Modal.FunctionCall{id: call_id, function: f, client: client}
    assert {:ok, 81} = Modal.Function.await(call)
  end

  test "spawn fan-out: 8 parallel spawns, await all in order", %{client: client, square: f} do
    calls =
      for n <- 1..8 do
        {:ok, call} = Modal.Function.spawn(client, f, [n])
        call
      end

    results = Enum.map(calls, &Modal.Function.await!/1)
    assert results == Enum.map(1..8, &(&1 * &1))
  end

  test "invoke_stream/5 collects every yielded value from a generator function",
       %{client: client, count_to: f} do
    # Pure-streaming sanity: Python `def count_to(n): for i in range(n): yield i`
    # → Elixir [0, 1, 2, 3, 4].
    assert [0, 1, 2, 3, 4] = Modal.Function.invoke_stream(client, f, [5]) |> Enum.to_list()
  end

  test "stream/2 from a spawn'd generator (uses generator: true at spawn)", %{
    client: client,
    count_to: f
  } do
    # Generators require SYNC_LEGACY at spawn time — Modal's worker
    # routes yields through FunctionCallGetDataOut only for that
    # invocation type. Plain spawn (ASYNC) silently returns []
    # for generator functions.
    {:ok, call} = Modal.Function.spawn(client, f, [3], %{}, generator: true)
    assert [0, 1, 2] = Modal.Function.stream(call) |> Enum.to_list()
  end

  test "invoke_stream/5 surfaces a failed generator as :function_failed (not a silent [])", %{
    client: client,
    boom_gen: f
  } do
    # A generator that raises sends no GENERATOR_DONE; its failure lives in
    # FunctionGetOutputs. stream/2 must poll it and raise — the regression
    # behind the gen_dump.py incident, where a failed generator came back as
    # an empty list and the failure was only visible in the Modal dashboard.
    err =
      assert_raise Modal.Error, fn ->
        Modal.Function.invoke_stream(client, f, [3]) |> Enum.to_list()
      end

    assert err.kind == :function_failed
    assert err.message =~ "RuntimeError"
  end

  test "echo verifies the (args_tuple, kwargs_dict) pickle wire shape", %{
    client: client,
    echo: f
  } do
    # The worker unpacks pickle.loads(input.args) → (args, kwargs) →
    # callable(*args, **kwargs). Echo returns what it received; we
    # assert the unpack happened correctly.
    assert {:ok, %{"args" => [1, "two", 3.0], "kwargs" => %{"flag" => true}}} =
             Modal.Function.invoke(client, f, [1, "two", 3.0], %{flag: true})
  end
end
