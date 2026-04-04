defmodule ModalTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 120_000

  setup_all do
    Application.put_env(:modal, :client_impl, Modal.Client)
    on_exit(fn -> Application.put_env(:modal, :client_impl, Modal.Client.Mock) end)

    token_id = System.get_env("MODAL_TOKEN_ID")
    token_secret = System.get_env("MODAL_TOKEN_SECRET")

    unless token_id && token_secret do
      raise "MODAL_TOKEN_ID and MODAL_TOKEN_SECRET must be set (source .env)"
    end

    {:ok, client} =
      start_supervised({Modal.Client, token_id: token_id, token_secret: token_secret})

    {:ok, app_id} = Modal.App.lookup(client, "elixir-test")

    # get_or_create returns a 3-tuple: {:ok, image_id, :cached | :built}
    {:ok, image_id, _status} =
      Modal.Image.get_or_create(client, ["FROM python:3.12-slim-bookworm"], app_id: app_id)

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout: 300,
        idle_timeout: 120
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)

    on_exit(fn ->
      try do
        Modal.Sandbox.terminate(sandbox)
      catch
        _, _ -> :ok
      end
    end)

    %{client: client, sandbox: sandbox, app_id: app_id, image_id: image_id}
  end

  describe "App" do
    test "lookup creates or finds an app", %{client: client} do
      assert {:ok, app_id} = Modal.App.lookup(client, "elixir-test-lookup")
      assert String.starts_with?(app_id, "ap-")
    end
  end

  describe "Sandbox" do
    test "list returns sandboxes", %{client: client} do
      assert {:ok, sandboxes} = Modal.Sandbox.list(client)
      assert is_list(sandboxes)
    end

    test "poll returns nil for running sandbox", %{sandbox: sb} do
      assert {:ok, nil} = Modal.Sandbox.poll(sb)
    end
  end

  describe "ContainerProcess" do
    test "await collects stdout and exit code", %{sandbox: sb} do
      {:ok, proc} = Modal.Sandbox.exec(sb, ["echo", "hello modal"])
      assert {:ok, result} = Modal.ContainerProcess.await(proc)
      Modal.ContainerProcess.close(proc)

      assert result.code == 0
      assert String.contains?(result.stdout, "hello modal")
    end

    test "stream/1 yields stdout chunks", %{sandbox: sb} do
      {:ok, proc} = Modal.Sandbox.exec(sb, ["bash", "-c", "for i in 1 2 3; do echo line$i; done"])

      chunks = proc |> Modal.ContainerProcess.stream() |> Enum.to_list()
      {:ok, code} = Modal.ContainerProcess.exit_code(proc)
      Modal.ContainerProcess.close(proc)

      output = Enum.join(chunks)
      assert code == 0
      assert String.contains?(output, "line1")
      assert String.contains?(output, "line3")
    end

    test "returns non-zero exit code", %{sandbox: sb} do
      {:ok, proc} = Modal.Sandbox.exec(sb, ["bash", "-c", "exit 42"])
      {:ok, result} = Modal.ContainerProcess.await(proc)
      Modal.ContainerProcess.close(proc)

      assert result.code == 42
    end

    test "writes to stdin", %{sandbox: sb} do
      {:ok, proc} = Modal.Sandbox.exec(sb, ["cat"])
      :ok = Modal.ContainerProcess.write(proc, "from stdin\n", eof: true)
      {:ok, result} = Modal.ContainerProcess.await(proc)
      Modal.ContainerProcess.close(proc)

      assert result.code == 0
      assert String.contains?(result.stdout, "from stdin")
    end

    test "runs python and captures output", %{sandbox: sb} do
      {:ok, proc} =
        Modal.Sandbox.exec(sb, ["python3", "-c", "import math; print(math.sqrt(144))"])

      {:ok, result} = Modal.ContainerProcess.await(proc)
      Modal.ContainerProcess.close(proc)

      assert result.code == 0
      assert String.contains?(result.stdout, "12.0")
    end
  end

  describe "filesystem" do
    test "writes and reads a file", %{sandbox: sb} do
      path = "/tmp/test_#{System.unique_integer([:positive])}.txt"
      content = "written at #{DateTime.utc_now()}\n"

      assert :ok = Modal.Sandbox.write_file(sb, path, content)
      assert {:ok, ^content} = Modal.Sandbox.read_file(sb, path)
    end

    test "lists directory contents", %{sandbox: sb} do
      path = "/tmp/lsdir_#{System.unique_integer([:positive])}"
      :ok = Modal.Sandbox.mkdir(sb, path)

      assert {:ok, files} = Modal.Sandbox.ls(sb, "/tmp")
      assert is_list(files)
      assert Path.basename(path) in files
    end

    test "creates and removes a directory", %{sandbox: sb} do
      path = "/tmp/rmdir_#{System.unique_integer([:positive])}"
      assert :ok = Modal.Sandbox.mkdir(sb, path)
      assert {:ok, []} = Modal.Sandbox.ls(sb, path)
      assert :ok = Modal.Sandbox.rm(sb, path, recursive: true)
    end
  end

  describe "snapshot" do
    @tag timeout: 180_000
    test "snapshot_filesystem and restore", ctx do
      {:ok, snap_image_id} = Modal.Sandbox.snapshot_filesystem(ctx.sandbox)
      assert String.starts_with?(snap_image_id, "im-")

      sandbox2 =
        Modal.Sandbox.create!(ctx.client,
          app_id: ctx.app_id,
          image_id: snap_image_id,
          cmd: ["sleep", "infinity"],
          timeout: 120,
          idle_timeout: 60
        )

      {:ok, _, sandbox2} = Modal.Sandbox.get_task_id(sandbox2)

      {:ok, proc} = Modal.Sandbox.exec(sandbox2, ["python3", "-c", "print('from snapshot')"])
      {:ok, result} = Modal.ContainerProcess.await(proc)
      Modal.ContainerProcess.close(proc)

      assert result.code == 0
      assert String.contains?(result.stdout, "from snapshot")

      Modal.Sandbox.terminate(sandbox2)
    end
  end
end
