defmodule Modal.Properties.PickleTest do
  @moduledoc """
  Property-based tests for `Modal.Pickle` — generates random terms
  from the supported subset and asserts the two invariants that
  matter:

    1. **Round-trip**: `decode!(encode(v)) == v` for any supported v.
    2. **Cross-runtime byte-equality**: `encode(v) ==
       pickle.dumps(v, protocol=4)` byte-for-byte. Sampled only for
       shapes that don't depend on Elixir map iteration order (which
       doesn't match Python's dict insertion order — a documented
       limitation; not a problem for Modal Dict where keys are
       usually strings).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Modal.Pickle

  @python_available? match?({_, 0}, System.cmd("python3", ["--version"], stderr_to_stdout: true))

  # ── Generators ────────────────────────────────────────────────

  defp leaf_gen do
    one_of([
      constant(nil),
      boolean(),
      # Small positive ints (BININT1 path) get extra weight — they're
      # the common case.
      integer(0..255),
      integer(-(2 ** 200)..(2 ** 200)),
      float(),
      string(:ascii, min_length: 0, max_length: 300),
      string(:utf8, min_length: 0, max_length: 20)
    ])
  end

  defp term_gen(depth \\ 3)
  defp term_gen(0), do: leaf_gen()

  defp term_gen(depth) do
    one_of([
      leaf_gen(),
      list_of(term_gen(depth - 1), max_length: 8),
      tuple_gen(depth - 1),
      map_of(string(:ascii, min_length: 0, max_length: 8), term_gen(depth - 1), max_length: 8)
    ])
  end

  defp tuple_gen(depth) do
    bind(integer(0..5), fn arity ->
      bind(list_of(term_gen(depth), length: arity), fn items ->
        constant(List.to_tuple(items))
      end)
    end)
  end

  # Restricted generator for byte-equality: no maps (Elixir's
  # iteration order doesn't match Python's dict insertion order;
  # makes byte-equality flaky) and no floats (Python's repr() for
  # floats has precision quirks).
  defp byte_eq_leaf_gen do
    one_of([
      constant(nil),
      boolean(),
      integer(-(2 ** 200)..(2 ** 200)),
      string(:ascii, min_length: 0, max_length: 100)
    ])
  end

  defp byte_eq_term_gen do
    one_of([
      byte_eq_leaf_gen(),
      list_of(byte_eq_leaf_gen(), max_length: 20),
      # Tuples need byte-equality too — they're the realistic Dict-key
      # shape (e.g., `("user_id", account_id)`).
      bind(integer(0..5), fn n ->
        bind(list_of(byte_eq_leaf_gen(), length: n), fn items ->
          constant(List.to_tuple(items))
        end)
      end)
    ])
  end

  # ── Round-trip property (always runs) ─────────────────────────

  describe "round-trip invariant" do
    property "decode!(encode(v)) == v for any supported term" do
      check all(v <- term_gen(), max_runs: 500) do
        assert v == v |> Pickle.encode() |> Pickle.decode!()
      end
    end

    property "round-trip survives extreme integer ranges" do
      check all(
              sign <- one_of([constant(1), constant(-1)]),
              n <- integer(0..(2 ** 4000)),
              max_runs: 200
            ) do
        v = sign * n
        assert v == v |> Pickle.encode() |> Pickle.decode!()
      end
    end

    property "round-trip survives strings of any length & content" do
      check all(s <- string(:utf8, min_length: 0, max_length: 600), max_runs: 200) do
        assert s == s |> Pickle.encode() |> Pickle.decode!()
      end
    end

    property "round-trip survives lists across the 1000-element batching boundary" do
      check all(n <- integer(995..1010), max_runs: 30) do
        v = Enum.to_list(0..(n - 1))
        assert v == v |> Pickle.encode() |> Pickle.decode!()
      end
    end

    property "round-trip survives deeply nested terms" do
      check all(v <- term_gen(5), max_runs: 100) do
        assert v == v |> Pickle.encode() |> Pickle.decode!()
      end
    end
  end

  # ── Cross-runtime byte-equality (needs python3) ───────────────

  describe "byte-equality with CPython pickle.dumps(value, protocol=4)" do
    @describetag :pickle_cross_runtime

    @tag skip: not @python_available?
    property "encode(v) byte-equals pickle.dumps(v, protocol=4) for scalars + lists" do
      # max_runs kept modest because each iteration shells out to python3.
      check all(v <- byte_eq_term_gen(), max_runs: 80) do
        elixir = Pickle.encode(v)
        python = python_dumps_proto4(v)

        assert elixir == python,
               "byte mismatch for #{inspect(v)}:\n" <>
                 "  elixir: #{Base.encode16(elixir, case: :lower)}\n" <>
                 "  python: #{Base.encode16(python, case: :lower)}"
      end
    end
  end

  # ── Cross-runtime decode (needs python3) ──────────────────────

  describe "decode(pickle.dumps(v)) == v" do
    @describetag :pickle_cross_runtime

    @tag skip: not @python_available?
    property "scalars + lists pickled by Python round-trip through Elixir decoder" do
      check all(v <- byte_eq_term_gen(), max_runs: 80) do
        python = python_dumps_proto4(v)
        decoded = Pickle.decode!(python)

        assert v == decoded,
               "round-trip via Python emitted bytes failed:\n" <>
                 "  v:       #{inspect(v)}\n" <>
                 "  decoded: #{inspect(decoded)}"
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────

  # Render an Elixir term via base64-shuttled Python expression to
  # avoid quoting hazards, then call pickle.dumps(..., protocol=4)
  # and return the raw bytes.
  defp python_dumps_proto4(v) do
    py_literal = to_python_literal(v)

    script = """
    import pickle, sys, base64
    b64 = base64.b64decode
    sys.stdout.buffer.write(pickle.dumps(#{py_literal}, protocol=4))
    """

    {out, 0} = System.cmd("python3", ["-c", script], stderr_to_stdout: false)
    out
  end

  defp to_python_literal(nil), do: "None"
  defp to_python_literal(true), do: "True"
  defp to_python_literal(false), do: "False"
  defp to_python_literal(n) when is_integer(n), do: Integer.to_string(n)
  defp to_python_literal(f) when is_float(f), do: Float.to_string(f)

  defp to_python_literal(s) when is_binary(s) do
    # base64 → bytes → utf-8 sidesteps quote/escape hazards.
    "b64('" <> Base.encode64(s) <> "').decode('utf-8')"
  end

  defp to_python_literal(list) when is_list(list) do
    "[" <> Enum.map_join(list, ", ", &to_python_literal/1) <> "]"
  end

  defp to_python_literal({}), do: "()"

  defp to_python_literal(tuple) when is_tuple(tuple) do
    items = Tuple.to_list(tuple)
    "(" <> Enum.map_join(items, ", ", &to_python_literal/1) <> tuple_close(items)
  end

  # 1-element tuple needs trailing comma: `(a,)`. 2+ doesn't.
  defp tuple_close([_]), do: ",)"
  defp tuple_close(_), do: ")"
end
