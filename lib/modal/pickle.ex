defmodule Modal.Pickle do
  @moduledoc """
  Minimal Python pickle codec — encode + decode the JSON-equivalent
  subset of values to/from Python's pickle protocol 4 wire format.

  ## Why this exists

  Modal's Python SDK auto-(de)serializes `Queue` and `Dict` values
  with cloudpickle. If you want Elixir to push values that a Python
  worker can `modal.Queue.get()` and have them arrive as native
  Python objects (no monkey-patching, no `json.loads`), the values
  on the wire have to be pickle bytes.

  ## What's supported

  | Elixir              | Python                   |
  |---------------------|--------------------------|
  | `nil`               | `None`                   |
  | `true` / `false`    | `True` / `False`         |
  | integers            | `int` (any width)        |
  | floats              | `float`                  |
  | binary (valid utf8) | `str`                    |
  | binary (other)      | `bytes`                  |
  | list                | `list`                   |
  | tuple               | `tuple`                  |
  | map                 | `dict`                   |

  Type fidelity matters for cross-runtime Dict keys: a Python
  `("user_id", 42)` tuple key pickle-encodes differently than the
  list `["user_id", 42]`, so writing the wrong shape from Elixir
  would silently miss the lookup. Use Elixir tuples (`{}`) for
  Python tuples, Elixir lists (`[]`) for Python lists.

  ## What's not supported (intentional)

  * `REDUCE` / `OBJ` / `INST` / `BUILD` — the opcodes that call
    arbitrary Python classes. These are pickle's headline security
    hole and we naturally can't execute Python anyway.
  * Custom classes, datetime, Decimal, sets, frozensets — out of
    scope; pass `encoding: :raw` and encode yourself if you need
    them.

  On decode, encountering an unsupported opcode raises
  `ArgumentError` with the opcode byte.

  ## Wire format

  Output is **byte-equivalent** to CPython's
  `pickle.dumps(value, protocol=4)`. That matters because Modal's
  `Dict` server treats keys as raw bytes — if we emitted a
  semantically equivalent but byte-different pickle, a Python
  worker's `dict.get(key)` would silently miss our writes.

  This means we emit `FRAME` + `MEMOIZE` opcodes the way CPython
  does (`FRAME` wraps any non-trivial body; `MEMOIZE` follows each
  memoizable value — strings, bytes, lists, dicts). Memo IDs match
  CPython's allocation order.
  """

  # ── Protocol opcodes (alphabetical within group) ──────────────

  # Header / footer
  @proto 0x80
  @stop ?.

  # Constants
  @none ?N
  @newtrue 0x88
  @newfalse 0x89

  # Ints
  @binint ?J
  @binint1 ?K
  @binint2 ?M
  @long1 0x8A
  @long4 0x8B

  # Floats
  @binfloat ?G

  # Strings / bytes
  @short_binunicode 0x8C
  @binunicode ?X
  @binunicode8 0x8D
  @short_binbytes ?C
  @binbytes ?B
  @binbytes8 0x8E

  # Collections
  @empty_list ?]
  @empty_dict ?}
  @empty_tuple ?)
  @empty_set 0x8F
  @additems 0x90
  @frozenset 0x91
  @tuple ?t
  @tuple1 0x85
  @tuple2 0x86
  @tuple3 0x87
  @mark ?(
  @append ?a
  @appends ?e
  @setitem ?s
  @setitems ?u

  # Memo
  @memoize 0x94
  @binget ?h
  @long_binget ?j
  @binput ?q
  @long_binput ?r
  @put ?p
  @get ?g

  # Frame (skipped on encode; parsed and ignored on decode)
  @frame 0x95

  # ── Encode ────────────────────────────────────────────────────

  @doc """
  Encode an Elixir term as Python pickle protocol 4 bytes. Returns
  bytes that `pickle.loads()` in Python 3 will deserialize into the
  equivalent Python object.

  Raises `ArgumentError` for unsupported terms.
  """
  @spec encode(term()) :: binary()
  def encode(value) do
    {body, _memo} = encode_body(value, fresh_memo())

    if needs_frame?(body) do
      # FRAME length covers everything from after the FRAME header
      # through (and including) the trailing STOP.
      frame_len = byte_size(body) + 1
      <<@proto, 4, @frame, frame_len::little-64, body::binary, @stop>>
    else
      <<@proto, 4, body::binary, @stop>>
    end
  end

  defp fresh_memo, do: %{next_id: 0, strings: %{}, bytes: %{}}

  # `encode_body/2` emits the value's opcodes followed by MEMOIZE
  # where CPython memoizes (strings/bytes via value equality,
  # collections always-fresh), and tracks the memo counter so a
  # repeated string within the same pickle emits BINGET instead.
  # Returns `{bytes, updated_memo}`.

  # ── Scalars (no MEMOIZE, no counter bump) ────────────────────
  defp encode_body(nil, memo), do: {<<@none>>, memo}
  defp encode_body(true, memo), do: {<<@newtrue>>, memo}
  defp encode_body(false, memo), do: {<<@newfalse>>, memo}

  defp encode_body(n, memo) when is_integer(n) and n >= 0 and n <= 0xFF do
    {<<@binint1, n>>, memo}
  end

  defp encode_body(n, memo) when is_integer(n) and n >= 0 and n <= 0xFFFF do
    {<<@binint2, n::little-16>>, memo}
  end

  defp encode_body(n, memo) when is_integer(n) and n >= -0x80000000 and n <= 0x7FFFFFFF do
    {<<@binint, n::little-signed-32>>, memo}
  end

  defp encode_body(n, memo) when is_integer(n) do
    bytes = encode_long_bytes(n)
    size = byte_size(bytes)

    payload =
      if size <= 0xFF do
        <<@long1, size, bytes::binary>>
      else
        <<@long4, size::little-32, bytes::binary>>
      end

    {payload, memo}
  end

  defp encode_body(f, memo) when is_float(f) do
    {<<@binfloat, f::big-float-64>>, memo}
  end

  # ── Strings / bytes (value-memoized — CPython does the same via
  #    string interning + id()-keyed memo) ─────────────────────
  defp encode_body(b, memo) when is_binary(b) do
    pool_key = if String.valid?(b), do: :strings, else: :bytes

    case Map.fetch(Map.fetch!(memo, pool_key), b) do
      {:ok, id} ->
        {binget(id), memo}

      :error ->
        payload =
          if pool_key == :strings, do: encode_str(b), else: encode_bytes(b)

        bytes = payload <> <<@memoize>>
        memo = remember(memo, pool_key, b)
        {bytes, memo}
    end
  end

  # ── Collections (always emit MEMOIZE; never deduped — Elixir
  #    terms don't carry identity, so we can't tell two equal
  #    lists apart from "the same list referenced twice") ────────
  defp encode_body([], memo) do
    {<<@empty_list, @memoize>>, bump(memo)}
  end

  defp encode_body([item], memo) do
    prefix = <<@empty_list, @memoize>>
    memo = bump(memo)
    {item_bytes, memo} = encode_body(item, memo)
    {prefix <> item_bytes <> <<@append>>, memo}
  end

  defp encode_body(list, memo) when is_list(list) do
    prefix = <<@empty_list, @memoize>>
    memo = bump(memo)
    {batched, memo} = encode_batches(list, memo, &encode_body/2, @appends)
    {prefix <> batched, memo}
  end

  defp encode_body(map, memo) when is_map(map) and map_size(map) == 0 do
    {<<@empty_dict, @memoize>>, bump(memo)}
  end

  defp encode_body(map, memo) when is_map(map) and map_size(map) == 1 do
    [{k, v}] = Enum.to_list(map)
    prefix = <<@empty_dict, @memoize>>
    memo = bump(memo)
    {k_bytes, memo} = encode_body(k, memo)
    {v_bytes, memo} = encode_body(v, memo)
    {prefix <> k_bytes <> v_bytes <> <<@setitem>>, memo}
  end

  defp encode_body(map, memo) when is_map(map) do
    prefix = <<@empty_dict, @memoize>>
    memo = bump(memo)
    {batched, memo} = encode_batches(Enum.to_list(map), memo, &encode_pair/2, @setitems)
    {prefix <> batched, memo}
  end

  # ── Tuples ────────────────────────────────────────────────────
  # CPython uses dedicated TUPLE1/2/3 opcodes for small tuples and
  # MARK + TUPLE for larger. Empty tuple is the only memoize-skipping
  # case (it's a singleton in CPython).
  defp encode_body({}, memo), do: {<<@empty_tuple>>, memo}

  defp encode_body({a}, memo) do
    {a_bytes, memo} = encode_body(a, memo)
    {a_bytes <> <<@tuple1, @memoize>>, bump(memo)}
  end

  defp encode_body({a, b}, memo) do
    {a_bytes, memo} = encode_body(a, memo)
    {b_bytes, memo} = encode_body(b, memo)
    {a_bytes <> b_bytes <> <<@tuple2, @memoize>>, bump(memo)}
  end

  defp encode_body({a, b, c}, memo) do
    {a_bytes, memo} = encode_body(a, memo)
    {b_bytes, memo} = encode_body(b, memo)
    {c_bytes, memo} = encode_body(c, memo)
    {a_bytes <> b_bytes <> c_bytes <> <<@tuple3, @memoize>>, bump(memo)}
  end

  defp encode_body(tuple, memo) when is_tuple(tuple) do
    items = Tuple.to_list(tuple)

    {items_bytes, memo} =
      Enum.reduce(items, {<<>>, memo}, fn item, {acc, m} ->
        {b, m} = encode_body(item, m)
        {acc <> b, m}
      end)

    {<<@mark, items_bytes::binary, @tuple, @memoize>>, bump(memo)}
  end

  defp encode_body(other, _memo) do
    raise ArgumentError,
          "Modal.Pickle.encode/1 doesn't support #{inspect(other)} " <>
            "— supported: nil, bool, integer, float, binary, list, tuple, map"
  end

  defp encode_pair({k, v}, memo) do
    {k_bytes, memo} = encode_body(k, memo)
    {v_bytes, memo} = encode_body(v, memo)
    {k_bytes <> v_bytes, memo}
  end

  # CPython's C pickler (`_pickle.c`, the default) batches
  # APPENDS/SETITEMS at 1000-item chunks. Once chunking has started
  # (i.e. we're not at the special top-level n=1 case), every chunk
  # — including a trailing 1-item chunk — is emitted as
  # MARK + items + APPENDS. The pure-Python `pickle.py` version
  # differs (uses bare APPEND for trailing 1-item), but `pickle.dumps`
  # uses the C impl by default and so does Modal.
  @batchsize 1000

  defp encode_batches(items, memo, item_encoder, batch_op) do
    items
    |> Enum.chunk_every(@batchsize)
    |> Enum.reduce({<<>>, memo}, fn batch, {acc_bytes, m} ->
      {batch_body, m} =
        Enum.reduce(batch, {<<>>, m}, fn item, {ab, mm} ->
          {item_bytes, mm} = item_encoder.(item, mm)
          {ab <> item_bytes, mm}
        end)

      {acc_bytes <> <<@mark, batch_body::binary, batch_op>>, m}
    end)
  end

  defp binget(id) when id <= 0xFF, do: <<@binget, id>>
  defp binget(id), do: <<@long_binget, id::little-32>>

  defp remember(memo, pool_key, value) do
    pool = Map.fetch!(memo, pool_key) |> Map.put(value, memo.next_id)
    %{memo | pool_key => pool, next_id: memo.next_id + 1}
  end

  defp bump(memo), do: %{memo | next_id: memo.next_id + 1}

  # Matches CPython's framing heuristic: skip FRAME when the body is
  # a single trivial opcode (no payload longer than 1 byte).
  defp needs_frame?(<<@none>>), do: false
  defp needs_frame?(<<@newtrue>>), do: false
  defp needs_frame?(<<@newfalse>>), do: false
  defp needs_frame?(<<@binint1, _>>), do: false
  defp needs_frame?(<<@empty_list, @memoize>>), do: false
  defp needs_frame?(<<@empty_dict, @memoize>>), do: false
  defp needs_frame?(<<@empty_tuple>>), do: false
  defp needs_frame?(_), do: true

  # str: SHORT_BINUNICODE (≤255 bytes) / BINUNICODE (≤4 GiB) / BINUNICODE8
  defp encode_str(b) do
    size = byte_size(b)

    cond do
      size <= 0xFF -> <<@short_binunicode, size, b::binary>>
      size <= 0xFFFFFFFF -> <<@binunicode, size::little-32, b::binary>>
      true -> <<@binunicode8, size::little-64, b::binary>>
    end
  end

  # bytes: SHORT_BINBYTES (≤255) / BINBYTES (≤4 GiB) / BINBYTES8
  defp encode_bytes(b) do
    size = byte_size(b)

    cond do
      size <= 0xFF -> <<@short_binbytes, size, b::binary>>
      size <= 0xFFFFFFFF -> <<@binbytes, size::little-32, b::binary>>
      true -> <<@binbytes8, size::little-64, b::binary>>
    end
  end

  # Two's complement little-endian, minimum bytes (matches Python's
  # int.to_bytes(signed=True) with shortest length that round-trips).
  defp encode_long_bytes(0), do: <<>>

  defp encode_long_bytes(n) when n > 0 do
    bytes = :binary.encode_unsigned(n, :little)
    # If high bit is set, prepend 0x00 so it's not read as negative.
    <<last, _::binary>> = :binary.part(bytes, byte_size(bytes) - 1, 1)
    if last >= 0x80, do: bytes <> <<0x00>>, else: bytes
  end

  defp encode_long_bytes(n) when n < 0 do
    # Smallest k such that -(2^(8k-1)) <= n. Equivalently:
    # k = ceil((bit_length(|n+1|) + 1) / 8) — handles the
    # -2^m boundary cleanly (where bit_length(|n|) over-counts).
    bits = bit_length(abs(n + 1)) + 1
    byte_count = div(bits + 7, 8) |> max(1)
    <<n::little-signed-size(byte_count * 8)>>
  end

  defp bit_length(0), do: 0
  defp bit_length(n) when n > 0, do: length(Integer.digits(n, 2))

  # ── Decode ────────────────────────────────────────────────────

  @doc """
  Decode pickle bytes into an Elixir term. Accepts protocol 0-5
  pickles emitted by Python — but understands only the opcodes
  needed for the JSON-equivalent value subset (see moduledoc).

  Raises `ArgumentError` on unsupported opcodes.
  """
  @spec decode!(binary()) :: term()
  def decode!(bytes) when is_binary(bytes) do
    {value, _rest} = parse(bytes, [], %{})
    value
  end

  # The pickle VM:
  #   stack: list of values (and :mark sentinels)
  #   memo:  map of memo_id => value
  #
  # We pattern-match the next opcode, push/pop the stack, recurse.

  defp parse(<<@stop, rest::binary>>, [val | _], _memo), do: {val, rest}

  defp parse(<<@proto, _proto_byte, rest::binary>>, stack, memo) do
    parse(rest, stack, memo)
  end

  defp parse(<<@frame, _size::little-64, rest::binary>>, stack, memo) do
    # Frames are length hints for streaming readers — semantically a no-op.
    parse(rest, stack, memo)
  end

  # Constants
  defp parse(<<@none, rest::binary>>, stack, memo), do: parse(rest, [nil | stack], memo)
  defp parse(<<@newtrue, rest::binary>>, stack, memo), do: parse(rest, [true | stack], memo)
  defp parse(<<@newfalse, rest::binary>>, stack, memo), do: parse(rest, [false | stack], memo)

  # Ints
  defp parse(<<@binint1, n, rest::binary>>, stack, memo),
    do: parse(rest, [n | stack], memo)

  defp parse(<<@binint2, n::little-16, rest::binary>>, stack, memo),
    do: parse(rest, [n | stack], memo)

  defp parse(<<@binint, n::little-signed-32, rest::binary>>, stack, memo),
    do: parse(rest, [n | stack], memo)

  defp parse(<<@long1, size, payload::binary-size(size), rest::binary>>, stack, memo) do
    parse(rest, [decode_long(payload) | stack], memo)
  end

  defp parse(<<@long4, size::little-32, payload::binary-size(size), rest::binary>>, stack, memo) do
    parse(rest, [decode_long(payload) | stack], memo)
  end

  # Float
  defp parse(<<@binfloat, f::big-float-64, rest::binary>>, stack, memo),
    do: parse(rest, [f | stack], memo)

  # str
  defp parse(<<@short_binunicode, size, s::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [s | stack], memo)

  defp parse(<<@binunicode, size::little-32, s::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [s | stack], memo)

  defp parse(<<@binunicode8, size::little-64, s::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [s | stack], memo)

  # bytes — round-tripped as Elixir binaries (no separate "bytes" type)
  defp parse(<<@short_binbytes, size, b::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [b | stack], memo)

  defp parse(<<@binbytes, size::little-32, b::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [b | stack], memo)

  defp parse(<<@binbytes8, size::little-64, b::binary-size(size), rest::binary>>, stack, memo),
    do: parse(rest, [b | stack], memo)

  # Collections — MARK-based
  defp parse(<<@mark, rest::binary>>, stack, memo), do: parse(rest, [:mark | stack], memo)

  defp parse(<<@empty_list, rest::binary>>, stack, memo), do: parse(rest, [[] | stack], memo)
  defp parse(<<@empty_dict, rest::binary>>, stack, memo), do: parse(rest, [%{} | stack], memo)
  defp parse(<<@empty_tuple, rest::binary>>, stack, memo), do: parse(rest, [{} | stack], memo)
  defp parse(<<@empty_set, rest::binary>>, stack, memo), do: parse(rest, [[] | stack], memo)

  defp parse(<<@tuple1, rest::binary>>, [a | stack], memo),
    do: parse(rest, [{a} | stack], memo)

  defp parse(<<@tuple2, rest::binary>>, [b, a | stack], memo),
    do: parse(rest, [{a, b} | stack], memo)

  defp parse(<<@tuple3, rest::binary>>, [c, b, a | stack], memo),
    do: parse(rest, [{a, b, c} | stack], memo)

  defp parse(<<@tuple, rest::binary>>, stack, memo) do
    {items, rest_stack} = pop_to_mark(stack)
    parse(rest, [List.to_tuple(items) | rest_stack], memo)
  end

  defp parse(<<@append, rest::binary>>, [item, list | stack], memo) when is_list(list) do
    parse(rest, [list ++ [item] | stack], memo)
  end

  defp parse(<<@appends, rest::binary>>, stack, memo) do
    {items, [list | rest_stack]} = pop_to_mark(stack)
    parse(rest, [list ++ items | rest_stack], memo)
  end

  defp parse(<<@additems, rest::binary>>, stack, memo) do
    # Treat sets as lists.
    {items, [set | rest_stack]} = pop_to_mark(stack)
    parse(rest, [set ++ items | rest_stack], memo)
  end

  defp parse(<<@frozenset, rest::binary>>, stack, memo) do
    {items, rest_stack} = pop_to_mark(stack)
    parse(rest, [items | rest_stack], memo)
  end

  defp parse(<<@setitem, rest::binary>>, [v, k, dict | stack], memo) when is_map(dict) do
    parse(rest, [Map.put(dict, k, v) | stack], memo)
  end

  defp parse(<<@setitems, rest::binary>>, stack, memo) do
    {flat, [dict | rest_stack]} = pop_to_mark(stack)
    pairs = Enum.chunk_every(flat, 2)
    updated = Enum.reduce(pairs, dict, fn [k, v], acc -> Map.put(acc, k, v) end)
    parse(rest, [updated | rest_stack], memo)
  end

  # Memo
  defp parse(<<@memoize, rest::binary>>, [top | _] = stack, memo) do
    next_id = map_size(memo)
    parse(rest, stack, Map.put(memo, next_id, top))
  end

  defp parse(<<@binput, id, rest::binary>>, [top | _] = stack, memo),
    do: parse(rest, stack, Map.put(memo, id, top))

  defp parse(<<@long_binput, id::little-32, rest::binary>>, [top | _] = stack, memo),
    do: parse(rest, stack, Map.put(memo, id, top))

  defp parse(<<@binget, id, rest::binary>>, stack, memo),
    do: parse(rest, [Map.fetch!(memo, id) | stack], memo)

  defp parse(<<@long_binget, id::little-32, rest::binary>>, stack, memo),
    do: parse(rest, [Map.fetch!(memo, id) | stack], memo)

  # Text-protocol memo ops (PUT/GET use ASCII-decimal IDs terminated by \n)
  defp parse(<<@put, rest::binary>>, [top | _] = stack, memo) do
    {id, rest2} = read_decimal_line(rest)
    parse(rest2, stack, Map.put(memo, id, top))
  end

  defp parse(<<@get, rest::binary>>, stack, memo) do
    {id, rest2} = read_decimal_line(rest)
    parse(rest2, [Map.fetch!(memo, id) | stack], memo)
  end

  # Unknown opcode — explicit error rather than silent corruption.
  defp parse(<<op, _rest::binary>>, _stack, _memo) do
    raise ArgumentError,
          "Modal.Pickle.decode!/1: unsupported opcode 0x#{Integer.to_string(op, 16)} " <>
            "(#{inspect(<<op>>)}). Likely a custom-class pickle (REDUCE/OBJ/BUILD) " <>
            "or an opcode outside the JSON-equivalent subset."
  end

  defp parse(<<>>, _stack, _memo) do
    raise ArgumentError, "Modal.Pickle.decode!/1: unexpected end of input (no STOP opcode)"
  end

  # ── Decode helpers ────────────────────────────────────────────

  defp decode_long(<<>>), do: 0

  defp decode_long(bytes) do
    size = byte_size(bytes)
    <<n::little-signed-size(size * 8)>> = bytes
    n
  end

  defp pop_to_mark(stack), do: pop_to_mark(stack, [])
  defp pop_to_mark([:mark | rest], acc), do: {acc, rest}
  defp pop_to_mark([item | rest], acc), do: pop_to_mark(rest, [item | acc])
  defp pop_to_mark([], _acc), do: raise(ArgumentError, "MARK not found on stack")

  defp read_decimal_line(bin) do
    [digits, rest] = :binary.split(bin, "\n")
    {String.to_integer(digits), rest}
  end
end
