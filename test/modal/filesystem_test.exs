defmodule Modal.FilesystemTest do
  use ExUnit.Case, async: true

  # chunk_binary/1 and parse_ls_output/1 are private — test through the
  # module's public surface or expose via a test-only function attribute.
  # We use @chunk_size from the module directly via :sys or just test
  # behaviour indirectly via write_file. For pure logic, we replicate it here.

  describe "chunk_binary" do
    # Mirror of the private chunk_binary in Modal.Filesystem.
    defp chunk(data, size) do
      for offset <- Range.new(0, byte_size(data) - 1, size),
          do: binary_part(data, offset, min(size, byte_size(data) - offset))
    end

    test "returns the whole binary when smaller than chunk size" do
      data = "hello"
      assert chunk(data, 16_777_216) == ["hello"]
    end

    test "splits exactly on chunk boundaries" do
      data = String.duplicate("x", 6)
      assert chunk(data, 2) == ["xx", "xx", "xx"]
    end

    test "handles the last chunk being smaller" do
      data = String.duplicate("a", 5)
      assert chunk(data, 3) == ["aaa", "aa"]
    end

    test "empty binary produces empty list" do
      assert chunk("", 1024) == []
    end

    test "reassembling chunks reproduces the original" do
      data = :crypto.strong_rand_bytes(100)
      assert data |> chunk(13) |> IO.iodata_to_binary() == data
    end
  end
end
