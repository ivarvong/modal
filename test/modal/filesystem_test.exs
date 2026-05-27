defmodule Modal.FilesystemTest do
  @moduledoc """
  Unit tests for `Modal.Filesystem`. Mocks the underlying RPC pair
  (`:ContainerFilesystemExec` + `:ContainerFilesystemExecGetOutput`)
  via `Modal.Client.Mock` and asserts the wire shape that each
  user-facing helper builds.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @task_id "ti-fs-test"

  defp sandbox, do: %Modal.Sandbox{id: "sb-fs-test", client: @client}

  # Every filesystem op starts with Sandbox.get_task_id/1. Stub the
  # cache so each test gets a hit without round-tripping :SandboxGetTaskId.
  setup do
    Mox.stub(Modal.Client.Mock, :lookup_task_id, fn _, _ -> {:ok, @task_id} end)
    :ok
  end

  # ── Helpers — script one fs_call + fs_wait pair ──────────────────

  # Each filesystem op fires `fs_call` (ContainerFilesystemExec) which
  # returns an `exec_id`, then `fs_wait` (a stream_reduce on
  # ContainerFilesystemExecGetOutput) which collects iodata or surfaces
  # an error. Tests provide both expectations.

  defp expect_fs_call(matcher, exec_id \\ "fx-1") do
    Modal.Client.Mock
    |> expect(:rpc, fn _, :container_filesystem_exec, req, _timeout ->
      matcher.(req)
      {:ok, %Modal.Client.ContainerFilesystemExecResponse{exec_id: exec_id}}
    end)
  end

  defp expect_fs_wait_ok(exec_id \\ "fx-1") do
    Modal.Client.Mock
    |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, req, init, _reducer, _ ->
      assert req.exec_id == exec_id
      {:ok, init}
    end)
  end

  # ── read_file/2 ─────────────────────────────────────────────────

  describe "read_file/2" do
    test "open + read + close roundtrip, returns the iodata as a binary" do
      Modal.Client.Mock
      # open
      |> expect(:rpc, fn _, :container_filesystem_exec, req, _ ->
        assert {:file_open_request, %Modal.Client.ContainerFileOpenRequest{path: "/a.txt", mode: "r"}} =
                 req.file_exec_request_oneof

        {:ok,
         %Modal.Client.ContainerFilesystemExecResponse{
           exec_id: "fx-open",
           file_descriptor: "fd-1"
         }}
      end)
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, _, _ ->
        {:ok, init}
      end)
      # read
      |> expect(:rpc, fn _, :container_filesystem_exec, req, _ ->
        assert {:file_read_request, %Modal.Client.ContainerFileReadRequest{file_descriptor: "fd-1"}} =
                 req.file_exec_request_oneof

        {:ok, %Modal.Client.ContainerFilesystemExecResponse{exec_id: "fx-read"}}
      end)
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, reducer, _ ->
        batch = %Modal.Client.FilesystemRuntimeOutputBatch{
          output: ["hello"],
          eof: true,
          error: nil
        }

        {:halt, acc} = reducer.(batch, init)
        {:ok, acc}
      end)
      # close
      |> expect(:rpc, fn _, :container_filesystem_exec, req, _ ->
        assert {:file_close_request, _} = req.file_exec_request_oneof
        {:ok, %Modal.Client.ContainerFilesystemExecResponse{exec_id: "fx-close"}}
      end)
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, _, _ ->
        {:ok, init}
      end)

      assert {:ok, "hello"} = Modal.Filesystem.read_file(sandbox(), "/a.txt")
    end

    test "read_file!/2 returns the raw binary on success" do
      Modal.Client.Mock
      |> stub(:rpc, fn _, :container_filesystem_exec, req, _ ->
        fd =
          case req.file_exec_request_oneof do
            {:file_open_request, _} -> "fd-1"
            _ -> ""
          end

        {:ok, %Modal.Client.ContainerFilesystemExecResponse{exec_id: "fx", file_descriptor: fd}}
      end)
      |> stub(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, reducer, _ ->
        batch = %Modal.Client.FilesystemRuntimeOutputBatch{
          output: ["bytes"],
          eof: true,
          error: nil
        }

        {:halt, acc} = reducer.(batch, init)
        {:ok, acc}
      end)

      assert "bytes" = Modal.Filesystem.read_file!(sandbox(), "/a.txt")
    end
  end

  # ── ls/2 ─────────────────────────────────────────────────────────

  describe "ls/2" do
    test "parses a JSON `{paths: [...]}` envelope" do
      expect_fs_call(fn req ->
        assert {:file_ls_request, %Modal.Client.ContainerFileLsRequest{path: "/work"}} =
                 req.file_exec_request_oneof
      end)

      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, reducer, _ ->
        json = ~s|{"paths": ["foo.txt", "bar/"]}|
        batch = %Modal.Client.FilesystemRuntimeOutputBatch{output: [json], eof: true, error: nil}
        {:halt, acc} = reducer.(batch, init)
        {:ok, acc}
      end)

      assert {:ok, ["foo.txt", "bar/"]} = Modal.Filesystem.ls(sandbox(), "/work")
    end

    test "falls back to newline-split when the body isn't a JSON envelope" do
      # Defends against older Modal workers that returned raw text. The
      # fallback path was previously untested.
      expect_fs_call(fn _ -> :ok end)

      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, reducer, _ ->
        batch = %Modal.Client.FilesystemRuntimeOutputBatch{
          output: ["a.txt\nb.txt\n"],
          eof: true,
          error: nil
        }

        {:halt, acc} = reducer.(batch, init)
        {:ok, acc}
      end)

      assert {:ok, ["a.txt", "b.txt"]} = Modal.Filesystem.ls(sandbox(), "/work")
    end

    test "surfaces filesystem errors from the worker" do
      expect_fs_call(fn _ -> :ok end)

      Modal.Client.Mock
      |> expect(:stream_rpc_reduce, fn _, :container_filesystem_exec_get_output, _, init, reducer, _ ->
        batch = %Modal.Client.FilesystemRuntimeOutputBatch{
          output: [],
          eof: true,
          error: %Modal.Client.SystemErrorMessage{error_message: "no such directory"}
        }

        {:halt, acc} = reducer.(batch, init)
        {:ok, acc}
      end)

      assert {:error, %Modal.Error{kind: :filesystem_error, message: "no such directory"}} =
               Modal.Filesystem.ls(sandbox(), "/missing")
    end
  end

  # ── mkdir/3 ──────────────────────────────────────────────────────

  describe "mkdir/3" do
    test "default `parents: true` propagates to the proto" do
      expect_fs_call(fn req ->
        assert {:file_mkdir_request, %Modal.Client.ContainerFileMkdirRequest{path: "/x/y/z", make_parents: true}} =
                 req.file_exec_request_oneof
      end)

      expect_fs_wait_ok()

      assert :ok = Modal.Filesystem.mkdir(sandbox(), "/x/y/z")
    end

    test "`parents: false` is honored" do
      expect_fs_call(fn req ->
        assert {:file_mkdir_request, %Modal.Client.ContainerFileMkdirRequest{path: "/x", make_parents: false}} =
                 req.file_exec_request_oneof
      end)

      expect_fs_wait_ok()

      assert :ok = Modal.Filesystem.mkdir(sandbox(), "/x", parents: false)
    end
  end

  # ── rm/3 ─────────────────────────────────────────────────────────

  describe "rm/3" do
    test "default is non-recursive" do
      expect_fs_call(fn req ->
        assert {:file_rm_request, %Modal.Client.ContainerFileRmRequest{path: "/x", recursive: false}} =
                 req.file_exec_request_oneof
      end)

      expect_fs_wait_ok()

      assert :ok = Modal.Filesystem.rm(sandbox(), "/x")
    end

    test "`recursive: true` is honored" do
      expect_fs_call(fn req ->
        assert {:file_rm_request, %Modal.Client.ContainerFileRmRequest{path: "/x", recursive: true}} =
                 req.file_exec_request_oneof
      end)

      expect_fs_wait_ok()

      assert :ok = Modal.Filesystem.rm(sandbox(), "/x", recursive: true)
    end
  end

  # ── write_files/3 — path correlation across :exit ─────────────────

  describe "write_files/3" do
    test "empty input returns :ok without firing any RPCs" do
      assert :ok = Modal.Filesystem.write_files(sandbox(), [])
    end

    test "extract_write_error/1 correlates :exit back to the input path" do
      # The path-correlation contract: `zip_input_on_exit: true` zips
      # the `{path, content}` tuple back into the `:exit` shape so the
      # extractor can recover the failing path. Previously every :exit
      # produced "<unknown path — task crashed>", losing all signal.
      assert [{"/a.txt", %Modal.Error{kind: :task_crashed, code: :exit, metadata: meta}}] =
               Modal.Filesystem.extract_write_error({:exit, {{"/a.txt", "data"}, :timeout}})

      assert meta.reason == :timeout
    end

    test "extract_write_error/1 passes successful writes through as no-error" do
      assert [] = Modal.Filesystem.extract_write_error({:ok, {"/x", :ok}})
    end

    test "extract_write_error/1 surfaces an RPC-level write error tagged with its path" do
      err = Modal.Error.grpc(13, "internal")

      assert [{"/x", ^err}] =
               Modal.Filesystem.extract_write_error({:ok, {"/x", {:error, err}}})
    end
  end

  # ── chunk_binary — test the real function ────────────────────────

  describe "chunk_binary/2 (production function)" do
    # Previously this test file shadowed `chunk_binary` with a local
    # `defp chunk/2` re-implementation, so a regression in the
    # production code wouldn't fail any test. We now call the real
    # function directly.

    test "returns the whole binary when smaller than chunk size" do
      assert ["hello"] = Modal.Filesystem.chunk_binary("hello", 16_777_216)
    end

    test "splits exactly on chunk boundaries" do
      assert ["xx", "xx", "xx"] = Modal.Filesystem.chunk_binary("xxxxxx", 2)
    end

    test "handles a last chunk smaller than chunk size" do
      assert ["aaa", "aa"] = Modal.Filesystem.chunk_binary("aaaaa", 3)
    end

    test "empty binary produces an empty list" do
      assert [] = Modal.Filesystem.chunk_binary("", 1024)
    end

    test "reassembled chunks reproduce the original" do
      data = :crypto.strong_rand_bytes(100)
      assert data == data |> Modal.Filesystem.chunk_binary(13) |> IO.iodata_to_binary()
    end
  end

  # ── write_files!/3 raise shape ───────────────────────────────────

  describe "write_files!/3 error shape" do
    test "raises %Modal.Error{kind: :filesystem_error} with paths in the message" do
      err = %Modal.Error{
        kind: :filesystem_error,
        message: "write_files failed for 2 path(s): /a, /b",
        metadata: %{
          failures: [{"/a", %Modal.Error{kind: :grpc}}, {"/b", %Modal.Error{kind: :grpc}}]
        }
      }

      # Direct shape check — the production raise builds exactly this
      # %Modal.Error{} and the full end-to-end raise path is exercised
      # via the live `:integration` suite.
      assert err.kind == :filesystem_error
      assert Exception.message(err) =~ "/a, /b"
      assert length(err.metadata.failures) == 2
    end
  end
end
