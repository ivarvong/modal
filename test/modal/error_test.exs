defmodule Modal.ErrorTest do
  use ExUnit.Case, async: true

  describe "transient?/1" do
    test ":network is always transient" do
      assert Modal.Error.transient?(Modal.Error.network(:econnrefused))
      assert Modal.Error.transient?(Modal.Error.network(:closed))
      assert Modal.Error.transient?(Modal.Error.network({:tls, :handshake_failed}))
    end

    test ":open_failed is always transient" do
      assert Modal.Error.transient?(Modal.Error.open_failed(:some_reason))
    end

    test ":grpc with DEADLINE_EXCEEDED (4) is transient" do
      assert Modal.Error.transient?(Modal.Error.grpc(4, "context deadline exceeded"))
    end

    test ":grpc with RESOURCE_EXHAUSTED (8) is transient" do
      assert Modal.Error.transient?(Modal.Error.grpc(8, "resource exhausted"))
    end

    test ":grpc with ABORTED (10) is transient" do
      assert Modal.Error.transient?(Modal.Error.grpc(10, "aborted"))
    end

    test ":grpc with UNAVAILABLE (14) is transient" do
      assert Modal.Error.transient?(Modal.Error.grpc(14, "unavailable"))
    end

    test ":grpc with INVALID_ARGUMENT (3) is NOT transient" do
      # 3 is INVALID_ARGUMENT — the request is bad. Retrying spams logs
      # and never succeeds.
      refute Modal.Error.transient?(Modal.Error.grpc(3, "invalid argument"))
    end

    test ":grpc with NOT_FOUND (5) is NOT transient" do
      refute Modal.Error.transient?(Modal.Error.grpc(5, "not found"))
    end

    test ":grpc with PERMISSION_DENIED (7) is NOT transient" do
      refute Modal.Error.transient?(Modal.Error.grpc(7, "permission denied"))
    end

    test ":grpc with INTERNAL (13) is NOT transient" do
      # INTERNAL is excluded deliberately — it usually masks a real bug.
      refute Modal.Error.transient?(Modal.Error.grpc(13, "internal"))
    end

    test ":grpc with UNKNOWN (2) is NOT transient" do
      refute Modal.Error.transient?(Modal.Error.grpc(2, "unknown"))
    end

    test ":timeout, :validation, :jwt_expired are NOT transient" do
      refute Modal.Error.transient?(Modal.Error.timeout())
      refute Modal.Error.transient?(Modal.Error.jwt_expired())
      refute Modal.Error.transient?(%Modal.Error{kind: :validation})
    end

    test ":task_crashed is NOT transient" do
      # A crash inside the dispatch task is a bug, not a retryable condition.
      refute Modal.Error.transient?(Modal.Error.task_crashed(:error, %RuntimeError{}))
    end
  end

  describe "message/1 (Exception protocol)" do
    test "renders kind-only errors" do
      assert Exception.message(Modal.Error.timeout()) == "Modal error: timeout"
    end

    test "renders kind+code errors" do
      assert Exception.message(Modal.Error.image_build_failed(:GENERIC_STATUS_FAILURE)) =~
               "image_build_failed"
    end

    test "renders kind+message errors" do
      err = Modal.Error.filesystem_error("EACCES /etc/passwd")
      msg = Exception.message(err)
      assert msg =~ "filesystem_error"
      assert msg =~ "EACCES"
    end

    test "renders kind+code+message errors" do
      msg = Exception.message(Modal.Error.grpc(7, "permission denied"))
      assert msg =~ "grpc"
      assert msg =~ "7"
      assert msg =~ "permission denied"
    end
  end

  describe "exec_failed/3" do
    test "a plain non-zero exit surfaces the stderr tail" do
      err = Modal.Error.exec_failed(17, "out", "boom\nfatal: nope\n")
      msg = Exception.message(err)
      assert err.kind == :exec_failed and err.code == 17
      assert msg =~ "fatal: nope"
      refute msg =~ "signal"
    end

    test "a signal exit (128 + signal) explains it was killed, not just non-zero" do
      # 137 = 128 + SIGKILL(9) — the bare exit code that the exec :timeout_secs
      # / OOM kills produce. The message should name the signal + the culprits.
      msg = Exception.message(Modal.Error.exec_failed(137, "", ""))
      assert msg =~ "killed by signal 9"
      assert msg =~ "timeout_secs"
      assert msg =~ "out-of-memory"
    end

    test "a signal exit still appends the stderr tail when present" do
      msg = Exception.message(Modal.Error.exec_failed(143, "", "shutting down\n"))
      assert msg =~ "killed by signal 15"
      assert msg =~ "shutting down"
    end
  end

  describe "raise/rescue interop" do
    test "is an Exception and can be raised + rescued" do
      err = Modal.Error.grpc(14, "unavailable")

      raised =
        try do
          raise err
        rescue
          e in Modal.Error -> e
        end

      assert raised == err
      assert raised.kind == :grpc
      assert raised.code == 14
    end
  end
end
