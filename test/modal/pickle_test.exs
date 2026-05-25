defmodule Modal.PickleTest do
  @moduledoc """
  Tests for `Modal.Pickle` — the Python pickle codec.

  Two layers:
    1. Round-trip in Elixir (`decode!(encode(v)) == v`) — fast, pure.
    2. Cross-runtime via Python (`python3 -c ...`) — proves wire-format
       compatibility with CPython's `pickle.loads` / `pickle.dumps`.
       Skipped (with a tagged message) if `python3` isn't on PATH.
  """
  use ExUnit.Case, async: true

  alias Modal.Pickle

  @python_available? match?({_, 0}, System.cmd("python3", ["--version"], stderr_to_stdout: true))

  # ── Layer 1: Elixir round-trip ────────────────────────────────

  describe "encode/1 + decode!/1 round-trip" do
    test "nil, booleans" do
      assert nil == roundtrip(nil)
      assert true == roundtrip(true)
      assert false == roundtrip(false)
    end

    test "small ints (BININT1 path, 0–255)" do
      for n <- [0, 1, 42, 255], do: assert(n == roundtrip(n))
    end

    test "medium ints (BININT2 path, 256–65535)" do
      for n <- [256, 1000, 65_535], do: assert(n == roundtrip(n))
    end

    test "int32 ints (BININT path, negative + positive)" do
      for n <- [-1, -1000, -2_147_483_648, 2_147_483_647], do: assert(n == roundtrip(n))
    end

    test "bignums (LONG1/LONG4 path)" do
      for n <- [2 ** 40, -(2 ** 40), 2 ** 100, -(2 ** 100), 2 ** 1000] do
        assert n == roundtrip(n)
      end
    end

    test "floats" do
      for f <- [0.0, 1.5, -3.14, 1.0e10, -1.0e-10] do
        assert f == roundtrip(f)
      end
    end

    test "strings (utf8 → str)" do
      assert "" == roundtrip("")
      assert "hello" == roundtrip("hello")
      assert "héllo 🎉" == roundtrip("héllo 🎉")
      # 256+ bytes goes to BINUNICODE
      long = String.duplicate("x", 300)
      assert long == roundtrip(long)
    end

    test "non-utf8 binary → bytes (round-trips as binary)" do
      raw = <<0xFF, 0xFE, 0x00, 0x01>>
      assert raw == roundtrip(raw)
    end

    test "lists" do
      assert [] == roundtrip([])
      assert [1, "two", 3.0, nil, true] == roundtrip([1, "two", 3.0, nil, true])
    end

    test "nested lists" do
      assert [[1, 2], [3, [4, 5]]] == roundtrip([[1, 2], [3, [4, 5]]])
    end

    test "maps" do
      assert %{} == roundtrip(%{})
      assert %{"a" => 1, "b" => 2} == roundtrip(%{"a" => 1, "b" => 2})
    end

    test "tuples — preserve tuple type for Python Dict-key parity" do
      for v <- [{}, {1}, {1, 2}, {1, 2, 3}, {1, 2, 3, 4}, {1, 2, 3, 4, 5, 6, 7, 8}] do
        assert v == roundtrip(v)
      end
    end

    test "repeated-string memoization round-trips" do
      # The memo stage emits BINGET for the 2nd "hello"; the decoder
      # must resolve it back to the same string.
      assert ["hello", "hello", "hello"] == roundtrip(["hello", "hello", "hello"])
      assert {"k", "k"} == roundtrip({"k", "k"})
    end

    test "special floats: ±0.0 sign bit preserved" do
      # BINFLOAT is raw IEEE 754 big-endian — the sign bit on -0.0
      # must survive verbatim.
      pos_zero_bits = <<roundtrip(0.0)::big-float-64>>
      assert <<0::1, _::63>> = pos_zero_bits

      <<neg_zero::big-float-64>> = <<1::1, 0::63>>
      neg_zero_bits = <<roundtrip(neg_zero)::big-float-64>>
      assert <<1::1, _::63>> = neg_zero_bits
    end

    test "nested maps + lists (the realistic mixed shape)" do
      v = %{
        "jobs" => [
          %{"id" => 1, "samples" => 100_000, "tags" => ["a", "b"]},
          %{"id" => 2, "samples" => 250_000, "tags" => []}
        ],
        "meta" => %{"created_at" => 1_700_000_000, "ok" => true, "err" => nil}
      }

      assert v == roundtrip(v)
    end

    test "encode/1 raises for unsupported terms" do
      assert_raise ArgumentError, ~r/doesn't support/, fn ->
        Pickle.encode({:a, :tuple, :of, :atoms})
      end

      assert_raise ArgumentError, ~r/doesn't support/, fn ->
        Pickle.encode(:an_atom)
      end
    end

    test "decode!/1 raises on unknown opcode" do
      # Valid PROTO header followed by a made-up opcode.
      bytes = <<0x80, 4, 0x01, ?.>>

      assert_raise ArgumentError, ~r/unsupported opcode/, fn ->
        Pickle.decode!(bytes)
      end
    end

    test "decode!/1 raises on REDUCE (the headline pickle security hole)" do
      # REDUCE = 'R' (0x52). Pickle would call the function at TOS-1
      # with arguments at TOS. We refuse — won't ever call arbitrary
      # Python functions from BEAM.
      reduce_bytes = <<0x80, 4, ?R, ?.>>

      assert_raise ArgumentError, ~r/unsupported opcode 0x52/, fn ->
        Pickle.decode!(reduce_bytes)
      end
    end

    test "decode!/1 raises a clean error on truncated input" do
      # PROTO + SHORT_BINUNICODE(5) + "hel" (only 3 of 5 promised bytes).
      # Pattern doesn't match → falls through to the catch-all
      # unsupported-opcode clause rather than dumping a cryptic stack
      # from deep in the VM.
      truncated = <<0x80, 4, 0x8C, 0x05, "hel">>

      assert_raise ArgumentError, ~r/unsupported opcode/, fn ->
        Pickle.decode!(truncated)
      end
    end

    test "decode!/1 raises with a helpful message on missing STOP" do
      # PROTO + NONE but no STOP — pickle VM never terminates.
      no_stop = <<0x80, 4, ?N>>

      assert_raise ArgumentError, ~r/no STOP opcode/, fn ->
        Pickle.decode!(no_stop)
      end
    end

    test "decode!/1 of an Elixir-encoded tuple inside Python pickles" do
      # Sanity: encode a tuple, ship round-trip.
      v = {1, "two", 3.0, nil}
      assert v == roundtrip(v)
    end
  end

  # ── Layer 2: cross-runtime with CPython ───────────────────────

  describe "cross-runtime with python3" do
    @describetag :pickle_cross_runtime

    @tag skip: not @python_available?
    test "Elixir → Python: pickle.loads(encoded) == expected" do
      values = [
        nil,
        true,
        false,
        0,
        42,
        -1,
        2 ** 40,
        3.14,
        "hello",
        "héllo 🎉",
        [1, 2, 3],
        %{"a" => 1, "b" => [2, 3], "c" => nil}
      ]

      for v <- values do
        bytes = Pickle.encode(v)
        py_repr = python_loads_then_repr(bytes)

        assert py_repr == elixir_to_python_repr(v),
               "round-trip mismatch for #{inspect(v)}: python saw #{py_repr}"
      end
    end

    @tag skip: not @python_available?
    test "BYTE EQUALITY with pickle.dumps(value, protocol=4) — matters for Modal Dict keys" do
      # Modal.Dict treats keys as raw bytes; a semantically-equal but
      # byte-different pickle would silently miss a Python worker's
      # `dict.get(key)`. So `Modal.Pickle.encode/1` must produce
      # CPython-canonical output, opcode-for-opcode.
      values = [
        nil,
        true,
        false,
        0,
        42,
        255,
        256,
        65_535,
        -1,
        2 ** 40,
        3.14,
        "",
        "key",
        "héllo",
        [],
        [1],
        [1, 2, 3],
        %{},
        %{"a" => 1},
        %{"a" => 1, "b" => 2}
      ]

      for v <- values do
        elixir_bytes = Pickle.encode(v)
        python_bytes = python_dumps_proto4(v)

        assert elixir_bytes == python_bytes,
               "byte mismatch for #{inspect(v)}:\n" <>
                 "  elixir: #{Base.encode16(elixir_bytes, case: :lower)}\n" <>
                 "  python: #{Base.encode16(python_bytes, case: :lower)}"
      end
    end

    @tag skip: not @python_available?
    test "Python → Elixir: decode!(pickle.dumps(value)) == expected" do
      cases = [
        {"None", nil},
        {"True", true},
        {"False", false},
        {"0", 0},
        {"42", 42},
        {"-1", -1},
        {"2**40", 2 ** 40},
        {"3.14", 3.14},
        {"'hello'", "hello"},
        {"'héllo 🎉'", "héllo 🎉"},
        # Python tuple decodes to Elixir tuple — preserves type for
        # round-trip with Python tuple Dict keys.
        {"(1, 2, 3)", {1, 2, 3}},
        {"()", {}},
        {"[1, 2, 3]", [1, 2, 3]},
        {"{'a': 1, 'b': [2, 3], 'c': None}", %{"a" => 1, "b" => [2, 3], "c" => nil}}
      ]

      for {py_expr, expected} <- cases do
        bytes = python_dumps(py_expr)
        decoded = Pickle.decode!(bytes)

        assert decoded == expected,
               "decode mismatch for python expr #{py_expr}: got #{inspect(decoded)}"
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp roundtrip(v), do: v |> Pickle.encode() |> Pickle.decode!()

  defp python_loads_then_repr(bytes) do
    # Use base64 to safely shuttle binary through the shell.
    b64 = Base.encode64(bytes)
    script = "import pickle, base64; print(repr(pickle.loads(base64.b64decode('#{b64}'))))"
    {out, 0} = System.cmd("python3", ["-c", script], stderr_to_stdout: true)
    String.trim(out)
  end

  defp python_dumps(py_expr) do
    script = "import pickle, sys; sys.stdout.buffer.write(pickle.dumps(#{py_expr}))"
    {out, 0} = System.cmd("python3", ["-c", script], stderr_to_stdout: false)
    out
  end

  # Render an Elixir term as a Python literal that pickle.dumps()
  # can serialize, then call pickle.dumps(..., protocol=4) and
  # return the raw bytes. Used for byte-equality assertions.
  defp python_dumps_proto4(v) do
    py_literal = elixir_to_python_repr(v)

    script =
      "import pickle, sys; sys.stdout.buffer.write(pickle.dumps(#{py_literal}, protocol=4))"

    {out, 0} = System.cmd("python3", ["-c", script], stderr_to_stdout: false)
    out
  end

  # Render an Elixir term as the Python `repr()` string it should
  # become after `pickle.loads`. Used to compare round-trips without
  # parsing Python on the Elixir side.
  defp elixir_to_python_repr(nil), do: "None"
  defp elixir_to_python_repr(true), do: "True"
  defp elixir_to_python_repr(false), do: "False"
  defp elixir_to_python_repr(n) when is_integer(n), do: Integer.to_string(n)
  defp elixir_to_python_repr(f) when is_float(f), do: Float.to_string(f)

  defp elixir_to_python_repr(s) when is_binary(s) do
    # Match Python's repr: '...' with single quotes, escaping as needed.
    # Python uses '...' for strings without single quotes, "..." if it
    # contains a single quote. We avoid the edge case by not using
    # apostrophes in the test fixtures.
    "'" <> s <> "'"
  end

  defp elixir_to_python_repr(list) when is_list(list) do
    "[" <> Enum.map_join(list, ", ", &elixir_to_python_repr/1) <> "]"
  end

  defp elixir_to_python_repr(map) when is_map(map) do
    pairs =
      Enum.map_join(map, ", ", fn {k, v} ->
        "#{elixir_to_python_repr(k)}: #{elixir_to_python_repr(v)}"
      end)

    "{" <> pairs <> "}"
  end
end
