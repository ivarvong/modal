defmodule Modal.Contract.VolumeTest do
  @moduledoc """
  Validates `Modal.Volume`'s read APIs against live Modal Volume v2.

  Asserts:
    - put_file → list_files round-trip surfaces the written file
    - put_file → get_file round-trip returns the exact bytes
    - reload + commit are no-ops at the RPC level (server returns
      Empty / VolumeCommitResponse) without erroring
    - non-existent file → :grpc 5 (NOT_FOUND), not a corrupt empty
      blob — the load-bearing contract of `get_file/4`'s error path
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 60_000

  setup_all do
    client = Support.client!()
    %{client: client}
  end

  setup %{client: client} do
    name = "contract-vol-#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"
    {:ok, vol_id} = Modal.Volume.get_or_create(client, name)

    on_exit(fn ->
      Application.put_env(:modal, :client_impl, Modal.Client)
      Modal.Volume.delete(client, vol_id)
    end)

    %{vol_id: vol_id}
  end

  test "put_file → list_files reflects the write", %{client: client, vol_id: vol_id} do
    :ok = Modal.Volume.put_file(client, vol_id, "/hello.txt", "world")

    assert {:ok, entries} = Modal.Volume.list_files(client, vol_id, path: "/")
    # v2 VolumeListFiles2 returns paths without leading slash for
    # root-level entries (caught live).
    paths = Enum.map(entries, & &1.path) |> Enum.sort()
    assert "hello.txt" in paths

    [entry] = Enum.filter(entries, &(&1.path == "hello.txt"))
    assert entry.type == :file
    assert entry.size == 5
    assert is_integer(entry.mtime)
  end

  test "put_file → get_file round-trips the exact bytes", %{client: client, vol_id: vol_id} do
    body = String.duplicate("modal-volume-read-contract\n", 100)
    :ok = Modal.Volume.put_file(client, vol_id, "/payload.txt", body)

    assert {:ok, ^body} = Modal.Volume.get_file(client, vol_id, "/payload.txt")
  end

  test "get_file/4 on a missing path returns :grpc 5 (NOT_FOUND)", %{
    client: client,
    vol_id: vol_id
  } do
    assert {:error, %Modal.Error{kind: :grpc, code: 5}} =
             Modal.Volume.get_file(client, vol_id, "/does-not-exist.txt")
  end

  test "reload/commit from orchestrator return FAILED_PRECONDITION (worker-only ops)",
       %{client: client, vol_id: vol_id} do
    # Both reload and commit are documented as worker-only by Modal:
    # they're called from inside a function container that has
    # mounted the volume. The orchestrator side gets FAILED_PRECONDITION.
    # Pinning the exact errors so a future Modal API change surfaces here.
    assert {:error, %Modal.Error{kind: :grpc, code: 9, message: reload_msg}} =
             Modal.Volume.reload(client, vol_id)

    assert reload_msg =~ "running function"

    assert {:error, %Modal.Error{kind: :grpc, code: 9, message: commit_msg}} =
             Modal.Volume.commit(client, vol_id)

    assert commit_msg =~ "mounted volume"
  end

  test "list_files on empty volume returns []", %{client: client, vol_id: vol_id} do
    assert {:ok, []} = Modal.Volume.list_files(client, vol_id)
  end

  test "list/2 surfaces a freshly created volume with its name + id", %{
    client: client,
    vol_id: vol_id
  } do
    # Proves the live wire shape behind list/2: that Modal populates
    # VolumeListItem.metadata.{name, creation_info.created_at} (the fields
    # we page on and return), not just the bare volume_id.
    assert {:ok, vols} = Modal.Volume.list(client)

    mine = Enum.find(vols, &(&1.volume_id == vol_id))
    assert mine, "expected freshly created volume #{vol_id} in Volume.list/2"
    assert String.starts_with?(mine.name, "contract-vol-")
    assert is_float(mine.created_at) and mine.created_at > 0
  end
end
