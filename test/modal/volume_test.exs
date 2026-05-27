defmodule Modal.VolumeTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock

  describe "get_or_create/3" do
    test "returns the volume_id on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, req, _timeout ->
        assert req.deployment_name == "my-cache"
        assert req.environment_name == ""
        assert req.object_creation_type == :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
        {:ok, %Modal.Client.VolumeGetOrCreateResponse{volume_id: "vo-abc"}}
      end)

      assert {:ok, "vo-abc"} = Modal.Volume.get_or_create(@client, "my-cache")
    end

    test "passes through :environment_name when supplied" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, req, _timeout ->
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.VolumeGetOrCreateResponse{volume_id: "vo-staging"}}
      end)

      assert {:ok, "vo-staging"} =
               Modal.Volume.get_or_create(@client, "my-cache", environment_name: "staging")
    end

    test "defaults to :v2 (the modern content-addressed filesystem)" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, req, _timeout ->
        assert req.version == :VOLUME_FS_VERSION_V2
        {:ok, %Modal.Client.VolumeGetOrCreateResponse{volume_id: "vo-default"}}
      end)

      assert {:ok, "vo-default"} = Modal.Volume.get_or_create(@client, "x")
    end

    test "version: :v1 still works for interop with existing v1 volumes" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, req, _timeout ->
        assert req.version == :VOLUME_FS_VERSION_V1
        {:ok, %Modal.Client.VolumeGetOrCreateResponse{volume_id: "vo-v1"}}
      end)

      assert {:ok, "vo-v1"} = Modal.Volume.get_or_create(@client, "x", version: :v1)
    end

    test "raises ArgumentError on an unsupported version" do
      assert_raise ArgumentError, ~r/:v1 or :v2/, fn ->
        Modal.Volume.get_or_create(@client, "x", version: :v99)
      end
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Volume.get_or_create(@client, "my-cache")
    end
  end

  describe "get_or_create!/3" do
    test "returns bare id on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_or_create, _req, _timeout ->
        {:ok, %Modal.Client.VolumeGetOrCreateResponse{volume_id: "vo-bang"}}
      end)

      assert "vo-bang" = Modal.Volume.get_or_create!(@client, "x")
    end

    test "raises on RPC error" do
      Modal.Client.Mock
      |> stub(:rpc, fn @client, :volume_get_or_create, _req, _timeout ->
        {:error, Modal.Error.grpc(14, "unavailable")}
      end)

      assert_raise Modal.Error, ~r/unavailable/, fn ->
        Modal.Volume.get_or_create!(@client, "x")
      end
    end
  end

  describe "delete/2" do
    test "sends the delete RPC with the right volume_id and returns :ok" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_delete, req, _timeout ->
        assert req.volume_id == "vo-bye"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Volume.delete(@client, "vo-bye")
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_delete, _req, _timeout ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} = Modal.Volume.delete(@client, "vo-x")
    end
  end

  describe "list/2" do
    defp item(id, name, created_at) do
      %Modal.Client.VolumeListItem{
        volume_id: id,
        label: name,
        metadata: %Modal.Client.VolumeMetadata{
          name: name,
          creation_info: %Modal.Client.CreationInfo{created_at: created_at}
        }
      }
    end

    test "returns one map per volume with volume_id/name/created_at; defaults env + cursor" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_list, req, _timeout ->
        assert req.environment_name == ""
        # Default cursor is ~now (Unix seconds); pages newest-first.
        assert_in_delta req.pagination.created_before, System.os_time(:second), 5

        {:ok,
         %Modal.Client.VolumeListResponse{
           items: [item("vo-2", "beta", 200.0), item("vo-1", "alpha", 100.0)]
         }}
      end)

      assert {:ok, vols} = Modal.Volume.list(@client)

      assert vols == [
               %{volume_id: "vo-2", name: "beta", created_at: 200.0},
               %{volume_id: "vo-1", name: "alpha", created_at: 100.0}
             ]
    end

    test "walks every page, resuming the cursor from the oldest item seen" do
      full_page = for n <- 100..1//-1, do: item("vo-#{n}", "v#{n}", n * 1.0)

      Modal.Client.Mock
      # First page: a full 100, so list/2 must fetch again.
      |> expect(:rpc, fn @client, :volume_list, _req, _timeout ->
        {:ok, %Modal.Client.VolumeListResponse{items: full_page}}
      end)
      # Second page: cursor resumes from the previous page's oldest created_at,
      # and a short page ends the walk.
      |> expect(:rpc, fn @client, :volume_list, req, _timeout ->
        assert req.pagination.created_before == 1.0
        {:ok, %Modal.Client.VolumeListResponse{items: [item("vo-0", "v0", 0.5)]}}
      end)

      assert {:ok, vols} = Modal.Volume.list(@client)
      assert length(vols) == 101
      assert List.last(vols) == %{volume_id: "vo-0", name: "v0", created_at: 0.5}
    end

    test ":max_objects caps the result and the page size" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_list, req, _timeout ->
        assert req.pagination.max_objects == 2

        {:ok,
         %Modal.Client.VolumeListResponse{items: [item("vo-2", "b", 2.0), item("vo-1", "a", 1.0)]}}
      end)

      assert {:ok, [%{volume_id: "vo-2"}, %{volume_id: "vo-1"}]} =
               Modal.Volume.list(@client, max_objects: 2)
    end

    test ":environment_name flows through" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_list, req, _timeout ->
        assert req.environment_name == "staging"
        {:ok, %Modal.Client.VolumeListResponse{items: []}}
      end)

      assert {:ok, []} = Modal.Volume.list(@client, environment_name: "staging")
    end

    test "rejects a negative :max_objects without an RPC" do
      assert {:error, %Modal.Error{kind: :validation}} =
               Modal.Volume.list(@client, max_objects: -1)
    end

    test "propagates RPC errors" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_list, _req, _timeout ->
        {:error, Modal.Error.grpc(13, "internal")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 13}} = Modal.Volume.list(@client)
    end
  end

  # ── put_file/5 ──────────────────────────────────────────────────
  #
  # Full put_file/5 coverage needs an HTTPS server stand-in for the
  # presigned PUT — the typical test seam doesn't reach into :httpc.
  # We test:
  #
  #   * argument validation (path shape, size cap)
  #   * the "already-have-the-block" short-circuit (one RPC, no PUT)
  #   * proto wiring is sane (the request the Modal-side sees)
  #
  # End-to-end PUT-roundtrip behaviour is exercised live by
  # `scripts/volume_roundtrip.exs` when that script gains a put_file
  # demo; for now the live cover is implicit via the contract tests.

  describe "put_file/5 — validation" do
    test "rejects an empty remote_path" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Volume.put_file(@client, "vo-x", "", "data")

      assert msg =~ "refer to a file"
    end

    test "rejects a remote_path ending in /" do
      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Volume.put_file(@client, "vo-x", "/data/", "data")

      assert msg =~ "refer to a file"
    end

    test "rejects files larger than 8 MiB (v1 limit)" do
      too_big = :crypto.strong_rand_bytes(8 * 1024 * 1024 + 1)

      assert {:error, %Modal.Error{kind: :validation, message: msg}} =
               Modal.Volume.put_file(@client, "vo-x", "big.bin", too_big)

      assert msg =~ "≤"
      assert msg =~ "Multi-block"
    end
  end

  describe "put_file/5 — single-RPC short-circuit when block already exists" do
    test "no HTTP PUT fires when server returns empty missing_blocks" do
      # Server reports the block is already in the store → no PUT,
      # no second RPC, just :ok. The mock verifies exactly ONE
      # VolumePutFiles2 call.
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_put_files2, req, _timeout ->
        assert req.volume_id == "vo-x"
        assert [file] = req.files
        assert file.path == "remote.json"
        assert file.size == 5
        assert file.mode == 0o644
        assert [block] = file.blocks
        assert byte_size(block.contents_sha256) == 32
        assert block.contents_sha256 == :crypto.hash(:sha256, "hello")
        assert block.put_response == nil

        {:ok, %Modal.Client.VolumePutFiles2Response{missing_blocks: []}}
      end)

      assert :ok = Modal.Volume.put_file(@client, "vo-x", "remote.json", "hello")
    end

    test ":mode option flows into the request" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_put_files2, req, _timeout ->
        [file] = req.files
        assert file.mode == 0o755
        {:ok, %Modal.Client.VolumePutFiles2Response{missing_blocks: []}}
      end)

      assert :ok = Modal.Volume.put_file(@client, "vo-x", "script.sh", "#!/bin/sh\n", mode: 0o755)
    end

    test ":overwrite: false flips disallow_overwrite_existing_files" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_put_files2, req, _timeout ->
        assert req.disallow_overwrite_existing_files == true
        {:ok, %Modal.Client.VolumePutFiles2Response{missing_blocks: []}}
      end)

      assert :ok = Modal.Volume.put_file(@client, "vo-x", "x.txt", "data", overwrite: false)
    end

    test "propagates an RPC failure" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_put_files2, _req, _timeout ->
        {:error, Modal.Error.grpc(7, "permission denied")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 7}} =
               Modal.Volume.put_file(@client, "vo-x", "x.txt", "data")
    end
  end

  describe "put_file!/5" do
    test "returns :ok on success" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_put_files2, _req, _timeout ->
        {:ok, %Modal.Client.VolumePutFiles2Response{missing_blocks: []}}
      end)

      assert :ok = Modal.Volume.put_file!(@client, "vo-x", "x.txt", "data")
    end

    test "raises on a validation error" do
      assert_raise Modal.Error, ~r/refer to a file/, fn ->
        Modal.Volume.put_file!(@client, "vo-x", "/dir/", "data")
      end
    end
  end

  # ── %Modal.Volume{} struct ──────────────────────────────────────

  describe "the mount struct" do
    test "requires :id and :path; defaults :read_only to false" do
      vol = %Modal.Volume{id: "vo-a", path: "/data"}
      assert vol.read_only == false

      vol_ro = %Modal.Volume{id: "vo-b", path: "/cache", read_only: true}
      assert vol_ro.read_only == true
    end

    test "raises on missing :id or :path (enforce_keys)" do
      assert_raise ArgumentError, fn ->
        # Compile-time enforce_keys check — eval'd to bypass the
        # compiler's static analysis.
        Code.eval_string("%Modal.Volume{path: \"/data\"}")
      end
    end
  end

  # ── Read APIs (list / get_file / reload / commit) ──────────────

  describe "list_files/3" do
    test "uses streaming VolumeListFiles2; flattens batches into a list of maps" do
      Modal.Client.Mock
      |> expect(:stream_rpc, fn @client, :volume_list_files2, req, _ ->
        assert req.volume_id == "vo-test"
        assert req.path == "/"
        assert req.recursive == false

        # Server streams responses in batches — flatten.
        {:ok,
         [
           %Modal.Client.VolumeListFiles2Response{
             entries: [
               %Modal.Client.FileEntry{
                 path: "/foo.txt",
                 type: :FILE,
                 size: 12,
                 mtime: 1_700_000_000
               }
             ]
           },
           %Modal.Client.VolumeListFiles2Response{
             entries: [
               %Modal.Client.FileEntry{
                 path: "/sub",
                 type: :DIRECTORY,
                 size: 0,
                 mtime: 1_700_000_000
               }
             ]
           }
         ]}
      end)

      assert {:ok, entries} = Modal.Volume.list_files(@client, "vo-test")

      assert [
               %{path: "/foo.txt", type: :file, size: 12, mtime: 1_700_000_000},
               %{path: "/sub", type: :directory, size: 0, mtime: 1_700_000_000}
             ] = entries
    end

    test ":recursive + :path flow through to the request" do
      Modal.Client.Mock
      |> expect(:stream_rpc, fn @client, :volume_list_files2, req, _ ->
        assert req.path == "/models"
        assert req.recursive == true
        assert req.max_entries == 100
        {:ok, [%Modal.Client.VolumeListFiles2Response{entries: []}]}
      end)

      assert {:ok, []} =
               Modal.Volume.list_files(@client, "vo-test",
                 path: "/models",
                 recursive: true,
                 max_entries: 100
               )
    end
  end

  describe "reload/2" do
    test "fires VolumeReload and returns :ok" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_reload, req, _ ->
        assert req.volume_id == "vo-test"
        {:ok, %Google.Protobuf.Empty{}}
      end)

      assert :ok = Modal.Volume.reload(@client, "vo-test")
    end
  end

  describe "commit/2" do
    test "fires VolumeCommit and returns :ok" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_commit, req, _ ->
        assert req.volume_id == "vo-test"
        {:ok, %Modal.Client.VolumeCommitResponse{}}
      end)

      assert :ok = Modal.Volume.commit(@client, "vo-test")
    end
  end

  describe "get_file/4" do
    # The HTTP block-download path goes through Req — covered live in
    # test/contract/volume_contract_test.exs. Here we cover the RPC
    # half and the error propagation surface.
    test "validates the path is a string" do
      assert_raise FunctionClauseError, fn ->
        Modal.Volume.get_file(@client, "vo-x", :not_a_string)
      end
    end

    test "RPC failure propagates as {:error, %Modal.Error{}}" do
      Modal.Client.Mock
      |> expect(:rpc, fn @client, :volume_get_file2, _req, _ ->
        {:error, Modal.Error.grpc(5, "not found")}
      end)

      assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
               Modal.Volume.get_file(@client, "vo-test", "/missing.txt")
    end
  end
end
