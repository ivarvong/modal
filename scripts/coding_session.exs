# Multi-turn coding session in ONE long-lived sandbox.
#
# A real coding agent doesn't fan-out N candidates in parallel for every
# task — most of the time it's running a sequence of commands in a
# single sandbox while it thinks: install deps, read a file, write a
# file, run a test, observe the failure, write a different file, run
# the test again. The sandbox holds state (filesystem, installed
# packages) between turns; the agent observes streamed output and
# decides what to do next.
#
# This script scripts one such session — a deterministic stand-in for
# what an LLM-driven loop would do — to prove the library handles
# the long-lived shape cleanly:
#
#   * Single `Modal.Sandbox.create` for the whole session
#   * Many `Modal.Sandbox.exec_streaming!/3` calls reusing the same
#     sandbox, with output streamed live per turn
#   * `Modal.Filesystem.write_file` / `read_file` between exec turns
#     (state persists in the container fs across execs)
#   * Final `Modal.Sandbox.terminate` — telemetry should show a clean
#     1:1 create:terminate ratio
#
# Run:
#
#     elixir scripts/coding_session.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule CodingSession do
  @app_name "modal-elixir-coding-session"

  # The "buggy" initial code the agent inherits.
  @initial_code """
  def sum_csv_column(path: str, column: str) -> int:
      import csv

      total = 0
      with open(path) as f:
          reader = csv.DictReader(f)
          for row in reader:
              # BUG: doesn't cast to int — concatenates strings.
              total = total + row[column]
      return total
  """

  # The test the agent is trying to make pass.
  @test_code """
  import sys
  sys.path.insert(0, "/work")

  from solution import sum_csv_column


  def test_sum_known_csv():
      assert sum_csv_column("/work/data.csv", "value") == 100
  """

  # Sample input data.
  @csv_data """
  id,value
  1,20
  2,30
  3,50
  """

  # The agent's "fix" — applied after observing the test failure.
  @fixed_code """
  def sum_csv_column(path: str, column: str) -> int:
      import csv

      total = 0
      with open(path) as f:
          reader = csv.DictReader(f)
          for row in reader:
              total += int(row[column])
      return total
  """

  # A second feature the agent adds after the first test passes:
  # support for an optional `default` for missing columns. New test
  # to drive it, then the impl that satisfies both.
  @additional_test """


  def test_default_for_missing_column():
      # New row with an empty `value` field — should be skipped /
      # treated as 0, not raise.
      assert sum_csv_column("/work/data_with_blanks.csv", "value") == 80
  """

  @csv_with_blanks """
  id,value
  1,30
  2,
  3,50
  """

  @extended_code """
  def sum_csv_column(path: str, column: str) -> int:
      import csv

      total = 0
      with open(path) as f:
          reader = csv.DictReader(f)
          for row in reader:
              raw = (row.get(column) or "").strip()
              if raw == "":
                  continue
              total += int(raw)
      return total
  """

  # ── Entry point ──────────────────────────────────────────────────

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}\n")

    {:ok, image_id, image_status} =
      Modal.Image.get_or_create(
        client,
        ["FROM python:3.14-slim", "RUN pip install --no-cache-dir pytest"],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image_id} [#{image_status}]\n")

    # One sandbox for the whole session. `with_sandbox/3` gives us
    # guaranteed cleanup whether we exit normally, raise, or get
    # killed mid-session (the watchdog handles that one).
    Modal.Sandbox.with_sandbox(client,
      [
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 300
      ],
      &session/1
    )

    log("\n── telemetry ─────────────")
    print_telemetry()
  end

  # ── The scripted session ────────────────────────────────────────

  defp session(sandbox) do
    log("sandbox: #{sandbox.id} (long-lived for the whole session)\n")

    # ── Turn 1: lay down the working set ──────────────────────
    # `write_files/2` fans the writes out in parallel through
    # `Task.async_stream/3`, so 3 files cost roughly one slow write
    # of wall-clock instead of three sequential round-trips.
    turn("Turn 1: scaffold the workspace", fn ->
      :ok = Modal.Filesystem.mkdir(sandbox, "/work/tests", parents: true)

      :ok =
        Modal.Filesystem.write_files(sandbox, [
          {"/work/solution.py", @initial_code},
          {"/work/tests/test_solution.py", @test_code},
          {"/work/data.csv", @csv_data}
        ])

      log("  scaffolded 3 files via write_files/2 (parallel writes)")
    end)

    # ── Turn 2: run the test — expected to fail ────────────────
    {:ok, first_result} =
      turn("Turn 2: run pytest (expecting failure on the buggy initial code)", fn ->
        run_pytest(sandbox, "first")
      end)

    assert!(first_result.code != 0, "expected initial test run to fail, got code 0")
    log("  ✓ pytest exited #{first_result.code} as expected — agent now knows what to fix")

    # ── Turn 3: read the file to verify the agent has the
    # current contents (a real LLM agent would do this before
    # patching, both as a sanity check and to inform the patch).
    turn("Turn 3: read the current solution.py via Filesystem", fn ->
      {:ok, contents} = Modal.Filesystem.read_file(sandbox, "/work/solution.py")
      log("  current solution.py: #{byte_size(contents)} bytes")
      preview = contents |> String.split("\n") |> Enum.take(5) |> Enum.join("\n")
      for line <- String.split(preview, "\n"), do: log("    | #{line}")
      log("    | ...")
    end)

    # ── Turn 4: apply the fix ──────────────────────────────────
    turn("Turn 4: apply the fix (int() conversion)", fn ->
      :ok = Modal.Filesystem.write_file(sandbox, "/work/solution.py", @fixed_code)
      log("  wrote new solution.py (#{byte_size(@fixed_code)} bytes)")
    end)

    # ── Turn 5: re-run pytest — expected to pass ───────────────
    {:ok, second_result} =
      turn("Turn 5: re-run pytest (expecting success)", fn -> run_pytest(sandbox, "second") end)

    assert!(second_result.code == 0, "expected fix to make the test pass, got code #{second_result.code}")
    log("  ✓ pytest exited 0 — original bug fixed")

    # ── Turn 6: add a feature (new test + extended impl) ───────
    turn("Turn 6: add a feature — handle blank fields", fn ->
      :ok = Modal.Filesystem.write_file(sandbox, "/work/data_with_blanks.csv", @csv_with_blanks)

      :ok =
        Modal.Filesystem.write_file(
          sandbox,
          "/work/tests/test_solution.py",
          @test_code <> @additional_test
        )

      :ok = Modal.Filesystem.write_file(sandbox, "/work/solution.py", @extended_code)
      log("  wrote data_with_blanks.csv, updated tests + solution")
    end)

    # ── Turn 7: final pytest run — both tests must pass ────────
    {:ok, final_result} =
      turn("Turn 7: final pytest (both tests should pass)", fn ->
        run_pytest(sandbox, "final")
      end)

    assert!(final_result.code == 0, "expected extended fix to pass both tests, got code #{final_result.code}")
    log("  ✓ all tests pass")

    log("\n  session summary: 7 turns, 1 sandbox, state persisted throughout")
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp turn(label, fun) do
    log("\n→ #{label}")
    t = now()
    result = fun.()
    log("  (#{now() - t}ms)")
    {:ok, result}
  rescue
    e ->
      log("  ✗ raised: #{Exception.message(e)}")
      reraise e, __STACKTRACE__
  end

  defp run_pytest(sandbox, label) do
    Modal.Sandbox.exec_streaming(sandbox, ["pytest", "-v", "--color=yes", "/work/tests"],
      on_stdout:
        Modal.ContainerProcess.line_buffered(fn line ->
          IO.puts(:stderr, IO.ANSI.format([:faint, "  [#{label}] ", :reset, line]))
        end),
      timeout: 60_000
    )
    |> case do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  defp assert!(true, _msg), do: :ok
  defp assert!(false, msg), do: raise("assertion failed: #{msg}")

  # ── Telemetry ────────────────────────────────────────────────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "coding-session-telemetry",
      [[:modal, :rpc, :stop], [:modal, :worker_rpc, :stop]],
      &__MODULE__.on_telemetry/4,
      nil
    )
  end

  @doc false
  def on_telemetry(event, _measurements, meta, _config) do
    [_, family, _] = event
    key = {family, meta.method, Map.get(meta, :status), Map.get(meta, :error_kind)}
    Agent.update(__MODULE__.Metrics, fn m -> Map.update(m, key, 1, &(&1 + 1)) end)
  end

  defp print_telemetry do
    metrics = Agent.get(__MODULE__.Metrics, & &1)
    {control, worker} = Enum.split_with(metrics, fn {{family, _, _, _}, _} -> family == :rpc end)

    log("  control-plane:")
    print_section(control)

    if worker != [] do
      log("\n  worker-channel:")
      print_section(worker)
    end

    # Sanity check the claim in the script's preamble: ONE sandbox
    # for the whole session means exactly one SandboxCreate and one
    # SandboxTerminate in the control-plane counters.
    sandbox_creates = Map.get(metrics, {:rpc, :SandboxCreate, :ok, nil}, 0)
    sandbox_terminates = Map.get(metrics, {:rpc, :SandboxTerminate, :ok, nil}, 0)

    log("")

    if sandbox_creates == 1 and sandbox_terminates == 1 do
      log("  ✓ 1 SandboxCreate + 1 SandboxTerminate — one sandbox, cleanly reused all session")
    else
      log("  ! expected 1 create + 1 terminate, got #{sandbox_creates} + #{sandbox_terminates}")
    end
  end

  defp print_section(events) do
    events
    |> Enum.sort()
    |> Enum.each(fn {{_, method, status, error_kind}, count} ->
      tag = if error_kind, do: " (#{error_kind})", else: ""
      log("    #{count |> to_string() |> String.pad_leading(3)} × #{method} #{status}#{tag}")
    end)
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp log(msg), do: IO.puts(:stderr, msg)
end

CodingSession.run()
