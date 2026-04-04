defmodule Modal.Properties.FilesystemTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Modal.Filesystem

  describe "chunk_binary/2" do
    # The fundamental invariant: chunking is lossless. For any binary and any
    # positive chunk size, concatenating the chunks reproduces the original
    # exactly. This proves both correctness of splitting AND correctness of
    # the reversal (the O(n) accumulation pattern).
    property "chunking is lossless: join(chunks) == original" do
      check all(
              data <- binary(),
              size <- positive_integer()
            ) do
        chunks = Filesystem.chunk_binary(data, size)
        assert IO.iodata_to_binary(chunks) == data
      end
    end

    # Every chunk except the last must have exactly `size` bytes.
    # This ensures no chunk is prematurely terminated.
    property "all chunks except the last have exactly chunk_size bytes" do
      check all(
              data <- binary(min_length: 1),
              size <- positive_integer()
            ) do
        chunks = Filesystem.chunk_binary(data, size)
        leading = Enum.drop(chunks, -1)
        assert Enum.all?(leading, &(byte_size(&1) == size))
      end
    end

    # The last chunk contains the remainder — between 1 and `size` bytes.
    property "last chunk is between 1 and chunk_size bytes" do
      check all(
              data <- binary(min_length: 1),
              size <- positive_integer()
            ) do
        chunks = Filesystem.chunk_binary(data, size)
        last = List.last(chunks)
        assert byte_size(last) >= 1
        assert byte_size(last) <= size
      end
    end

    # The number of chunks is exactly ceil(byte_size(data) / size).
    property "produces the correct number of chunks" do
      check all(
              data <- binary(min_length: 1),
              size <- positive_integer()
            ) do
        expected = ceil(byte_size(data) / size)
        assert length(Filesystem.chunk_binary(data, size)) == expected
      end
    end

    # When the chunk size is at least as large as the data, there is exactly
    # one chunk equal to the original binary. (Only for non-empty data —
    # empty binary always produces [] regardless of chunk size.)
    property "single chunk when size >= byte_size(data)" do
      check all(data <- binary(min_length: 1)) do
        size = byte_size(data) + 1
        assert Filesystem.chunk_binary(data, size) == [data]
      end
    end

    # Empty binary produces an empty list — no empty chunks are emitted.
    property "empty binary always produces empty list" do
      check all(size <- positive_integer()) do
        assert Filesystem.chunk_binary("", size) == []
      end
    end

    # Chunking is deterministic: calling it twice with the same arguments
    # gives the same result.
    property "chunking is deterministic" do
      check all(
              data <- binary(),
              size <- positive_integer()
            ) do
        assert Filesystem.chunk_binary(data, size) == Filesystem.chunk_binary(data, size)
      end
    end
  end
end
