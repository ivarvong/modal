# End-to-end stress test for Modal.Pickle through live Modal Dict
# + Queue. Generates random terms from the supported subset, runs
# them through the actual gRPC wire in both directions, and verifies
# semantic equality.
#
# Three layers:
#
#   * Elixir → Modal → Python: Elixir puts pickle bytes; Python
#     reads via native `modal.Queue.get()` / `modal.Dict.get(key)`
#     (no monkey-patch). Validates Elixir's encoder matches what
#     the Python deserializer expects.
#
#   * Python → Modal → Elixir: Python puts via native modal SDK
#     (pickle-encoded by the Python side); Elixir reads with
#     `encoding: :pickle` and decodes. Validates Elixir's decoder
#     against the canonical Python pickler.
#
#   * Dict keys round-trip: Elixir writes a value under a string
#     key with `:pickle`; Python reads with the SAME string key.
#     This is the byte-equality-sensitive path — Modal's Dict
#     compares keys as raw bytes.
#
#     elixir scripts/pickle_stress.exs
#
# Needs (in .env):
#   MODAL_TOKEN_ID, MODAL_TOKEN_SECRET   — modal.com
# Plus a Python venv with modal installed (defaults to
# /tmp/modal-py-venv/bin/python3; override with PYTHON_BIN env var).

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule PickleStress do
  @app_name "modal-elixir-pickle-stress"
  @n_values 100

  @python_bin System.get_env("PYTHON_BIN") || "/tmp/modal-py-venv/bin/python3"

  def run do
    :logger.set_application_level(:grpc, :warning)

    case System.cmd(@python_bin, ["-c", "import modal; print('ok')"], stderr_to_stdout: true) do
      {"ok\n", 0} ->
        :ok

      {out, status} ->
        IO.puts(:stderr, "✗ python check failed (status=#{status}):\n#{out}")
        IO.puts(:stderr, "  set PYTHON_BIN to a python with `modal` installed.")
        System.halt(1)
    end

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    suffix = "#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"
    queue_name = "stress-q-#{suffix}"
    dict_name = "stress-d-#{suffix}"

    {:ok, queue} = Modal.Queue.get_or_create(client, queue_name, app: app)
    {:ok, dict} = Modal.Dict.get_or_create(client, dict_name, app: app)

    log_header("setup")
    log("  queue: #{queue.name} (#{queue.id})")
    log("  dict:  #{dict.name} (#{dict.id})")

    try do
      values = generate_values(@n_values)
      log("  generated #{length(values)} random terms (mixed shapes)")

      phase_elixir_to_python(queue, dict, queue_name, dict_name, values)
      phase_python_to_elixir(queue, dict, queue_name, dict_name, values)
      phase_dict_key_byte_equality(dict, dict_name, values)
      phase_tuple_keys(dict, dict_name)
      phase_modify_cycle(queue, dict, queue_name, dict_name)

      log_header("SUMMARY")
      log("  ✓ all 5 phases passed across #{length(values)} random terms")
    after
      log("\n  cleanup: dropping queue + dict")
      Modal.Queue.delete(queue)
      Modal.Dict.delete(dict)
    end
  end

  # ── Phase 1: Elixir writes pickle → Python reads native ───────

  defp phase_elixir_to_python(queue, dict, queue_name, dict_name, values) do
    log_header("PHASE 1 — Elixir → Modal → Python (native deserialize)")

    t = now()

    # Push every value into the queue, also store under integer key
    # in dict (string keys would also work; we use string keys here
    # for cross-runtime simplicity).
    Enum.each(values, fn v ->
      :ok = Modal.Queue.put(queue, v, encoding: :pickle)
    end)

    Enum.with_index(values, fn v, i ->
      :ok = Modal.Dict.put(dict, "k#{i}", v, encoding: :pickle)
    end)

    log("  ✓ pushed #{length(values)} items to Queue + Dict in #{elapsed(t)}")

    t2 = now()

    py_script = """
    import modal, sys, pickle, base64
    q = modal.Queue.from_name(#{inspect(queue_name)}, create_if_missing=False)
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)

    # Drain queue, encode each via pickle.dumps(protocol=4) and ship out.
    n = #{length(values)}
    out = []
    for _ in range(n):
        v = q.get(block=True, timeout=10)
        out.append(pickle.dumps(v, protocol=4))

    for i in range(n):
        v = d.get(f"k{i}")
        out.append(pickle.dumps(v, protocol=4))

    sys.stdout.buffer.write(b"\\n".join(base64.b64encode(b) for b in out))
    """

    {raw_out, 0} = System.cmd(@python_bin, ["-c", py_script], stderr_to_stdout: false)

    log("  ✓ python drained Queue + Dict via native modal SDK in #{elapsed(t2)}")

    [from_queue, from_dict] =
      raw_out
      |> String.split("\n", trim: true)
      |> Enum.map(&Base.decode64!/1)
      |> Enum.chunk_every(length(values))

    verify_match!("queue (Elixir → Python)", values, from_queue)
    verify_match!("dict  (Elixir → Python)", values, from_dict)
  end

  # ── Phase 2: Python writes native → Elixir reads pickle ───────

  defp phase_python_to_elixir(queue, dict, queue_name, dict_name, values) do
    log_header("PHASE 2 — Python → Modal → Elixir (Modal.Pickle.decode!)")

    # Send the same Elixir values to Python via a sidechannel (the
    # script returns nothing; Python pickles its own copies into
    # Queue + Dict using the SAME values). We tell Python what to
    # write by passing pickle bytes for each value via b64-encoded
    # CLI argument.
    py_payloads_b64 =
      values
      |> Enum.map(&Modal.Pickle.encode/1)
      |> Enum.map(&Base.encode64/1)
      |> Enum.join(",")

    t = now()

    py_script = """
    import modal, sys, pickle, base64, os
    q = modal.Queue.from_name(#{inspect(queue_name)}, create_if_missing=False)
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)

    # Decode the payloads using OUR pickle, then re-put via modal SDK
    # — that puts via Python's native pickle.dumps on the way out.
    payloads = [pickle.loads(base64.b64decode(b)) for b in os.environ["PAYLOADS"].split(",")]
    for v in payloads:
        q.put(v)
    for i, v in enumerate(payloads):
        d[f"k{i}"] = v
    """

    {out, 0} =
      System.cmd(@python_bin, ["-c", py_script],
        stderr_to_stdout: true,
        env: [{"PAYLOADS", py_payloads_b64}]
      )

    if String.trim(out) != "",
      do: log("  (python stderr): " <> String.replace(out, "\n", " | "))

    log("  ✓ python populated Queue + Dict via native modal SDK in #{elapsed(t)}")

    t2 = now()

    from_queue =
      for _i <- 1..length(values) do
        {:ok, v} = Modal.Queue.get(queue, encoding: :pickle, timeout_secs: 10.0)
        v
      end

    from_dict =
      for i <- 0..(length(values) - 1) do
        {:ok, v} = Modal.Dict.get(dict, "k#{i}", encoding: :pickle)
        v
      end

    log("  ✓ elixir drained Queue + Dict via Modal.Pickle.decode! in #{elapsed(t2)}")

    verify_match!("queue (Python → Elixir)", values, from_queue, decoded: true)
    verify_match!("dict  (Python → Elixir)", values, from_dict, decoded: true)
  end

  # ── Phase 3: Dict key byte-equality across runtimes ───────────

  defp phase_dict_key_byte_equality(dict, dict_name, values) do
    log_header("PHASE 3 — Dict key byte-equality (Elixir writes, Python reads)")

    # The point of this phase: if Modal.Pickle.encode/1 were
    # byte-different from Python's pickle.dumps for the key, the
    # Python lookup below would silently return None for every key
    # — even though the value bytes are correct. This validates the
    # one place byte-equality actually matters in practice.

    # Use the values list AS KEYS (after filtering to types that
    # are valid as Dict keys — Python doesn't accept mutable types
    # like list/dict as keys, and we dedupe by pickle-byte
    # representation so two different generated values that pickle
    # to the same bytes — e.g. `nil` and `nil`, `42` and `42` —
    # don't collapse to one Dict entry that fails the round-trip
    # check by overwriting).
    keyable =
      values
      |> Enum.filter(&valid_python_dict_key?/1)
      |> Enum.uniq_by(&Modal.Pickle.encode/1)

    log("  filtered to #{length(keyable)} keyable, byte-unique values")

    # Write under each key, with a marker value.
    Enum.with_index(keyable, fn k, i ->
      :ok = Modal.Dict.put(dict, k, %{"key_index" => i, "ok" => true}, encoding: :pickle)
    end)

    log("  ✓ wrote #{length(keyable)} entries with non-trivial pickle keys")

    py_script = """
    import modal, sys, pickle, base64, os
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)

    keys = [pickle.loads(base64.b64decode(b)) for b in os.environ["KEYS"].split(",")]
    misses = 0
    bad_value = 0
    for i, k in enumerate(keys):
        v = d.get(k)
        if v is None:
            misses += 1
            print(f"MISS key {i}: {k!r}", file=sys.stderr)
        elif v.get("key_index") != i:
            bad_value += 1
            print(f"BAD_VALUE key {i}: got {v!r}", file=sys.stderr)

    print(f"misses={misses} bad_value={bad_value} total={len(keys)}")
    """

    keys_b64 =
      keyable
      |> Enum.map(&Modal.Pickle.encode/1)
      |> Enum.map(&Base.encode64/1)
      |> Enum.join(",")

    {out, status} =
      System.cmd(@python_bin, ["-c", py_script],
        stderr_to_stdout: true,
        env: [{"KEYS", keys_b64}]
      )

    out = String.trim_trailing(out)
    log("  python: " <> String.replace(out, "\n", "\n          "))

    if status != 0 do
      raise "phase 3 python script exited #{status}"
    end

    summary = out |> String.split("\n") |> List.last()

    unless summary =~ "misses=0 bad_value=0" do
      raise "phase 3 failed: " <> summary
    end

    log("  ✓ Python found every key — byte-equality holds end-to-end")
  end

  # ── Phase 4: Python tuple keys (the composite-key case) ───────

  defp phase_tuple_keys(dict, dict_name) do
    log_header("PHASE 4 — Python tuple Dict keys (Elixir tuples → Python tuples)")

    # The most realistic composite-key shape from Python:
    # `dict[(account_id, "users")] = ...`.
    elixir_pairs = [
      {{1, "users"}, %{"count" => 100}},
      {{2, "users"}, %{"count" => 50}},
      {{1, "posts"}, %{"count" => 999}},
      {{"abc", "def"}, %{"label" => "lex"}},
      {{}, %{"empty_tuple" => true}}
    ]

    Enum.each(elixir_pairs, fn {k, v} ->
      :ok = Modal.Dict.put(dict, k, v, encoding: :pickle)
    end)

    log("  ✓ wrote #{length(elixir_pairs)} tuple-keyed entries from Elixir")

    py_script = """
    import modal, pickle, base64, os
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)

    keys = [pickle.loads(base64.b64decode(b)) for b in os.environ["KEYS"].split(",")]
    misses = []
    for k in keys:
        v = d.get(k)
        if v is None:
            misses.append(repr(k))

    if misses:
        print("MISSED:", misses)
        raise SystemExit(1)
    print("ok")
    """

    keys_b64 =
      elixir_pairs
      |> Enum.map(fn {k, _} -> Modal.Pickle.encode(k) end)
      |> Enum.map(&Base.encode64/1)
      |> Enum.join(",")

    {out, status} =
      System.cmd(@python_bin, ["-c", py_script],
        stderr_to_stdout: true,
        env: [{"KEYS", keys_b64}]
      )

    if status != 0 do
      raise "phase 4 failed: " <> String.trim(out)
    end

    log("  ✓ Python found all tuple keys (true Python-tuple parity)")
  end

  # ── Phase 5: mutual modify cycle ──────────────────────────────

  defp phase_modify_cycle(queue, dict, queue_name, dict_name) do
    log_header("PHASE 5 — mutual modify cycle (Elixir → Python → Elixir)")

    # Initial state from Elixir.
    initial = %{
      "counter" => 1,
      "history" => ["elixir_init"],
      "by_runtime" => %{"elixir" => 1, "python" => 0}
    }

    :ok = Modal.Dict.put(dict, "shared", initial, encoding: :pickle)
    log("  ✓ Elixir wrote initial state")

    py_script = """
    import modal
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)

    state = d["shared"]
    state["counter"] += 1
    state["history"].append("python_step")
    state["by_runtime"]["python"] += 1
    d["shared"] = state

    # Also push a status onto the queue.
    q = modal.Queue.from_name(#{inspect(queue_name)}, create_if_missing=False)
    q.put({"step": "python", "counter": state["counter"]})
    """

    {out, 0} = System.cmd(@python_bin, ["-c", py_script], stderr_to_stdout: true)
    if String.trim(out) != "", do: log("  (python): " <> String.trim(out))
    log("  ✓ Python read, modified, wrote back")

    {:ok, after_py} = Modal.Dict.get(dict, "shared", encoding: :pickle)

    if after_py["counter"] != 2 do
      raise "expected counter=2 after Python step, got #{inspect(after_py)}"
    end

    if after_py["history"] != ["elixir_init", "python_step"] do
      raise "expected history=[init, python_step], got #{inspect(after_py["history"])}"
    end

    {:ok, py_queue_msg} = Modal.Queue.get(queue, encoding: :pickle, timeout_secs: 5.0)

    if py_queue_msg["step"] != "python" or py_queue_msg["counter"] != 2 do
      raise "queue msg from python didn't survive round-trip: #{inspect(py_queue_msg)}"
    end

    log("  ✓ Elixir read Python's modifications correctly")

    # Elixir's turn: take the state, mutate, write.
    elixir_step =
      after_py
      |> Map.update!("counter", &(&1 + 1))
      |> Map.update!("history", &(&1 ++ ["elixir_step"]))
      |> Map.update!("by_runtime", &Map.update!(&1, "elixir", fn n -> n + 1 end))

    :ok = Modal.Dict.put(dict, "shared", elixir_step, encoding: :pickle)
    :ok = Modal.Queue.put(queue, %{"step" => "elixir", "counter" => 3}, encoding: :pickle)
    log("  ✓ Elixir read, modified, wrote back")

    # Python verifies Elixir's writes are readable.
    verify_script = """
    import modal, json
    d = modal.Dict.from_name(#{inspect(dict_name)}, create_if_missing=False)
    q = modal.Queue.from_name(#{inspect(queue_name)}, create_if_missing=False)

    state = d["shared"]
    assert state["counter"] == 3, f"bad counter: {state['counter']}"
    assert state["history"] == ["elixir_init", "python_step", "elixir_step"], f"bad history: {state['history']}"
    assert state["by_runtime"] == {"elixir": 2, "python": 1}, f"bad by_runtime: {state['by_runtime']}"

    msg = q.get(block=True, timeout=5)
    assert msg["step"] == "elixir" and msg["counter"] == 3, f"bad queue msg: {msg}"
    print("ok")
    """

    {out, status} = System.cmd(@python_bin, ["-c", verify_script], stderr_to_stdout: true)

    if status != 0 do
      raise "phase 5 python verify failed: " <> String.trim(out)
    end

    log("  ✓ Python verified Elixir's modifications")
    log("  ✓ mutual modify cycle complete — 3 rounds, no information loss")
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp verify_match!(label, expected, got, opts \\ []) do
    pairs = Enum.zip(expected, got)

    mismatches =
      pairs
      |> Enum.with_index(fn {e, g}, i ->
        {i, e, g}
      end)
      |> Enum.reject(fn {_, e, g} ->
        if Keyword.get(opts, :decoded) do
          e == g
        else
          # `got` is pickle bytes from Python; decode and compare.
          Modal.Pickle.decode!(g) == e
        end
      end)

    if mismatches == [] do
      log("  ✓ #{label}: all #{length(pairs)} round-tripped equal")
    else
      log("  ✗ #{label}: #{length(mismatches)} mismatches (showing first 3)")

      Enum.take(mismatches, 3)
      |> Enum.each(fn {i, e, g} ->
        log("      [#{i}] expected #{inspect(e, limit: :infinity)}")
        log("            got      #{inspect(g, limit: :infinity)}")
      end)

      raise "#{label}: round-trip mismatch"
    end
  end

  defp generate_values(n) do
    Enum.map(1..n, fn _ -> random_term(3) end)
  end

  defp random_term(0), do: random_leaf()

  defp random_term(depth) do
    case :rand.uniform(5) do
      1 -> random_leaf()
      2 -> for _ <- 1..(:rand.uniform(10) - 1), do: random_term(depth - 1)
      3 -> Map.new(for _ <- 1..(:rand.uniform(5) - 1), do: {random_key(), random_term(depth - 1)})
      _ -> random_leaf()
    end
  end

  defp random_leaf do
    case :rand.uniform(7) do
      1 -> nil
      2 -> Enum.random([true, false])
      3 -> :rand.uniform(2_000_000) - 1_000_000
      4 -> :rand.uniform() * 1000 - 500
      5 -> random_string()
      6 -> :rand.uniform(2 ** 100)
      _ -> :rand.uniform(255)
    end
  end

  defp random_string do
    len = :rand.uniform(40) - 1
    for _ <- 1..len, into: "", do: <<Enum.random(?a..?z)>>
  end

  defp random_key do
    case :rand.uniform(3) do
      1 -> random_string()
      _ -> "k#{:rand.uniform(1000)}"
    end
  end

  # Python rejects list/dict/etc. as dict keys (unhashable).
  defp valid_python_dict_key?(v) when is_list(v), do: false
  defp valid_python_dict_key?(v) when is_map(v), do: false
  defp valid_python_dict_key?(_), do: true

  defp log_header(msg), do: IO.puts(:stderr, "\n\e[1m── #{msg} ──────────────\e[0m")
  defp log(msg), do: IO.puts(:stderr, msg)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: fmt_ms(now() - t)
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"
end

PickleStress.run()
