defmodule Modal.Contract.PickleTest do
  @moduledoc """
  End-to-end validation that `Modal.Pickle` produces bytes Modal's
  Python SDK can `pickle.loads()` natively — and vice versa.

  Three phases against live Modal Dict + Queue:

    1. Elixir → Modal → Python: write 50 random values from Elixir
       with `encoding: :pickle`; a Python subprocess uses native
       `modal.Queue.get()` / `modal.Dict.get(key)` (no monkey-patch)
       and pickle-encodes the values it sees; we decode + compare.

    2. Python → Modal → Elixir: Python writes via native modal SDK
       (auto-pickled); Elixir reads with `encoding: :pickle`.

    3. Dict key byte-equality: Elixir writes 30 unique pickle-encoded
       keys; Python finds every one via `d[key]` lookup. The load-
       bearing test for `Modal.Pickle.encode/1`'s CPython-canonical
       byte output.

  Requires `PYTHON_BIN` env var pointing at a Python with `modal`
  installed (defaults to `/tmp/modal-py-venv/bin/python3`).
  Skips with a clear message if the binary or `modal` package is
  missing.
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 180_000

  @python_bin System.get_env("PYTHON_BIN") || "/tmp/modal-py-venv/bin/python3"

  setup_all do
    case System.cmd(@python_bin, ["-c", "import modal; print('ok')"], stderr_to_stdout: true) do
      {"ok\n", 0} ->
        client = Support.client!()
        {:ok, app} = Modal.App.lookup(client, "elixir-contract-test")
        %{client: client, app: app}

      _ ->
        # Skip the whole module if Python+modal isn't available — the
        # contract is still validated locally by the property tests in
        # test/modal/properties/pickle_property_test.exs.
        {:skip, "needs `modal` in PYTHON_BIN (#{@python_bin}); set PYTHON_BIN or skip"}
    end
  end

  setup %{client: client, app: app} do
    suffix = "#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"
    {:ok, queue} = Modal.Queue.get_or_create(client, "contract-pickle-q-#{suffix}", app: app)
    {:ok, dict} = Modal.Dict.get_or_create(client, "contract-pickle-d-#{suffix}", app: app)

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Queue.delete(queue)
      Modal.Dict.delete(dict)
    end)

    %{queue: queue, dict: dict, queue_name: queue.name, dict_name: dict.name}
  end

  test "Elixir → Modal → Python: 50 values round-trip via native modal SDK",
       %{queue: queue, dict: dict, queue_name: q_name, dict_name: d_name} do
    values = Enum.map(1..50, fn _ -> random_term() end)

    for v <- values, do: :ok = Modal.Queue.put(queue, v, encoding: :pickle)

    Enum.with_index(values, fn v, i ->
      :ok = Modal.Dict.put(dict, "k#{i}", v, encoding: :pickle)
    end)

    py_script = """
    import modal, sys, pickle, base64
    q = modal.Queue.from_name(#{inspect(q_name)}, create_if_missing=False)
    d = modal.Dict.from_name(#{inspect(d_name)}, create_if_missing=False)
    n = #{length(values)}
    out = []
    for _ in range(n):
        out.append(pickle.dumps(q.get(block=True, timeout=10), protocol=4))
    for i in range(n):
        out.append(pickle.dumps(d.get(f"k{i}"), protocol=4))
    sys.stdout.buffer.write(b"\\n".join(base64.b64encode(b) for b in out))
    """

    {raw_out, 0} = System.cmd(@python_bin, ["-c", py_script])

    [from_queue, from_dict] =
      raw_out
      |> String.split("\n", trim: true)
      |> Enum.map(&Base.decode64!/1)
      |> Enum.chunk_every(length(values))

    for {expected, pickled} <- Enum.zip(values, from_queue),
        do: assert(Modal.Pickle.decode!(pickled) == expected)

    for {expected, pickled} <- Enum.zip(values, from_dict),
        do: assert(Modal.Pickle.decode!(pickled) == expected)
  end

  test "Python → Modal → Elixir: native pickle round-trips through Modal.Pickle.decode!",
       %{queue: queue, dict: dict, queue_name: q_name, dict_name: d_name} do
    values = Enum.map(1..30, fn _ -> random_term() end)

    payloads_b64 =
      values |> Enum.map(&Modal.Pickle.encode/1) |> Enum.map_join(",", &Base.encode64/1)

    py_script = """
    import modal, sys, pickle, base64, os
    q = modal.Queue.from_name(#{inspect(q_name)}, create_if_missing=False)
    d = modal.Dict.from_name(#{inspect(d_name)}, create_if_missing=False)
    payloads = [pickle.loads(base64.b64decode(b)) for b in os.environ["PAYLOADS"].split(",")]
    for v in payloads:
        q.put(v)
    for i, v in enumerate(payloads):
        d[f"k{i}"] = v
    """

    {_, 0} = System.cmd(@python_bin, ["-c", py_script], env: [{"PAYLOADS", payloads_b64}])

    for expected <- values do
      assert {:ok, ^expected} = Modal.Queue.get(queue, encoding: :pickle, timeout_secs: 10.0)
    end

    for {expected, i} <- Enum.with_index(values) do
      assert {:ok, ^expected} = Modal.Dict.get(dict, "k#{i}", encoding: :pickle)
    end
  end

  test "Dict key byte-equality: Python finds every Elixir-written pickle key",
       %{dict: dict, dict_name: d_name} do
    # Modal's Dict server compares keys as raw bytes. A semantically-
    # equal but byte-different pickle silently misses. This test
    # validates Modal.Pickle.encode/1's CPython-canonical output
    # end-to-end through Modal's actual storage layer — caught the
    # missing BINGET-for-repeated-strings memo in dev.
    keys =
      Enum.map(1..30, fn _ -> random_term() end)
      |> Enum.filter(&keyable?/1)
      |> Enum.uniq_by(&Modal.Pickle.encode/1)

    Enum.with_index(keys, fn k, i ->
      :ok = Modal.Dict.put(dict, k, %{"i" => i}, encoding: :pickle)
    end)

    keys_b64 = keys |> Enum.map(&Modal.Pickle.encode/1) |> Enum.map_join(",", &Base.encode64/1)

    py_script = """
    import modal, sys, pickle, base64, os
    d = modal.Dict.from_name(#{inspect(d_name)}, create_if_missing=False)
    keys = [pickle.loads(base64.b64decode(b)) for b in os.environ["KEYS"].split(",")]
    misses = sum(1 for k in keys if d.get(k) is None)
    print(misses)
    """

    {out, 0} = System.cmd(@python_bin, ["-c", py_script], env: [{"KEYS", keys_b64}])
    misses = out |> String.trim() |> String.to_integer()

    assert misses == 0,
           "Python missed #{misses}/#{length(keys)} pickle-encoded Dict keys — " <>
             "byte-equality with CPython's pickle.dumps is broken"
  end

  # ── Random-term generator (matches pickle_property_test's gen) ──

  defp random_term do
    case :rand.uniform(7) do
      1 -> nil
      2 -> Enum.random([true, false])
      3 -> :rand.uniform(2_000_000) - 1_000_000
      4 -> :rand.uniform() * 1000 - 500
      5 -> random_string()
      6 -> Enum.map(1..:rand.uniform(5)//1, fn _ -> random_string() end)
      _ -> :rand.uniform(255)
    end
  end

  defp random_string do
    for _ <- 1..:rand.uniform(20)//1, into: "", do: <<Enum.random(?a..?z)>>
  end

  defp keyable?(v) when is_list(v) or is_map(v), do: false
  defp keyable?(_), do: true
end
