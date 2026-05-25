# Speculative test-driven repair: Python repo, Elixir orchestrator.
#
# Demonstrates the coding-agent pattern Modal is uniquely good at:
# fan out N candidate patches into N ephemeral sandboxes from a
# snapshot, run the test suite in each in parallel, ship the first
# patch whose tests pass, cancel the still-running losers mid-flight.
#
# What this proves about the library:
#
#   * Elixir orchestrates Python cleanly — App lookup, image build,
#     base sandbox, filesystem write, snapshot, parallel restore.
#   * `Task.async_stream` over `run_candidate/4` + `Enum.reduce_while`
#     short-circuits on the first winner.
#   * `:terminate_on_caller_exit: true` on each fanned-out sandbox
#     means when async_stream cancels in-flight tasks (BEAM-side
#     brutal_kill), the watchdog fires `Sandbox.terminate` Modal-side.
#     Resource cleanup follows process-lifecycle automatically.
#   * `Modal.ContainerProcess.stream/2` from N sandboxes, interleaved
#     through one labeled output writer, with each chunk prefixed by
#     the candidate's label. Line-buffered so prefixes don't mangle.
#   * `Modal.Sandbox.snapshot_filesystem/2` + restore — the warm-boot
#     primitive that makes the speculative pattern fast in steady state.
#
# Run:
#
#     elixir scripts/speculative_repair.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule SpeculativeRepair do
  @app_name "modal-elixir-speculative-repair"
  @workdir "/work"

  # ── The repo under repair ────────────────────────────────────────
  #
  # A tiny Python project with a function under test. The initial
  # `palindrome.py` passes basic tests but fails the punctuation
  # case. The agent is asked to fix it.

  @repo_files [
    {"src/palindrome.py",
     """
     def is_palindrome(s: str) -> bool:
         # Initial — passes basic cases, fails on punctuation/case.
         return s == s[::-1]
     """},
    {"tests/test_palindrome.py",
     """
     import sys
     sys.path.insert(0, "/work/src")

     from palindrome import is_palindrome


     def test_basic_palindromes():
         assert is_palindrome("racecar")
         assert is_palindrome("a")
         assert is_palindrome("")


     def test_basic_non_palindromes():
         assert not is_palindrome("hello")
         assert not is_palindrome("ab")


     def test_punctuation_and_case():
         assert is_palindrome("A man, a plan, a canal: Panama")
         assert is_palindrome("No 'x' in Nixon")
     """}
  ]

  # ── The three candidate patches ──────────────────────────────────
  #
  # Simulating what an LLM coding agent would propose. One has a
  # syntax error (fails fast at collection time), one is slow + still
  # subtly wrong, one is correct. We don't need a real LLM here —
  # this script is about orchestration, not generation. Replace
  # @patches with `Anthropic.complete(...)` outputs for the real thing.

  @patches [
    %{
      label: "A",
      description: "missing colon — syntax error",
      file: "src/palindrome.py",
      content: """
      def is_palindrome(s: str) -> bool
          return s == s[::-1]
      """
    },
    %{
      label: "B",
      description: "fixes case, misses punctuation — also subtly slow",
      file: "src/palindrome.py",
      content: """
      import time


      def is_palindrome(s: str) -> bool:
          # Subtle perf regression — 1.5s per call. Punctuation still wrong.
          time.sleep(1.5)
          return s.lower() == s.lower()[::-1]
      """
    },
    %{
      label: "C",
      description: "strips punctuation + case-folds — correct",
      file: "src/palindrome.py",
      content: """
      def is_palindrome(s: str) -> bool:
          cleaned = "".join(c.lower() for c in s if c.isalnum())
          return cleaned == cleaned[::-1]
      """
    }
  ]

  # ── Entry point ──────────────────────────────────────────────────

  def run do
    setup_telemetry()
    start_output_writer()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    snap_image_id = build_base_snapshot(client, app)

    log("\n── PHASE 3: speculative repair — #{length(@patches)} candidates in parallel ─────────────")
    log("(streaming each candidate's pytest output, prefixed with its label)\n")

    t = now()
    result = race_candidates(client, app, snap_image_id)
    total_ms = now() - t

    log("\n── PHASE 4: verdict ─────────────")
    log("parallel phase: #{total_ms}ms wall-clock")
    print_verdict(result)

    log("\n── PHASE 5: telemetry ─────────────")
    print_telemetry()
  end

  # ── PHASE 1+2: image, base sandbox, write repo, snapshot ─────────

  defp build_base_snapshot(client, app) do
    log("\n── PHASE 1: image (python + pytest, cached after first run) ─────────────")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM python:3.14-slim",
          "RUN pip install --no-cache-dir pytest"
        ],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image_id} [#{status}] (#{elapsed(t)})")

    log("\n── PHASE 2: base sandbox — write repo + snapshot filesystem ─────────────")
    t = now()

    base =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 300,
        terminate_on_caller_exit: true
      )

    log("base sandbox: #{base.id} (#{elapsed(t)})")

    log("  writing #{length(@repo_files)} files into #{@workdir}/")

    for {path, content} <- @repo_files do
      full = Path.join(@workdir, path)
      :ok = Modal.Filesystem.mkdir(base, Path.dirname(full), parents: true)
      :ok = Modal.Filesystem.write_file(base, full, content)
      log("    #{full}  (#{byte_size(content)} bytes)")
    end

    # Sanity check: the base repo's tests fail (proving we need a patch).
    # We deliberately use `await/2` (not `await!/2`) here because a
    # non-zero exit is what we want; await!/2 would raise.
    log("  sanity: pytest on the unpatched code (must fail)")
    {:ok, proc} = Modal.Sandbox.exec(base, pytest_cmd())
    {:ok, sanity} = Modal.ContainerProcess.await(proc, timeout: 30_000)
    Modal.ContainerProcess.close(proc)

    if sanity.code == 0 do
      raise "expected unpatched code to fail pytest, but it passed — adjust the demo"
    end

    log("    ✓ failed as expected (exit #{sanity.code})")

    log("  snapshotting filesystem")
    t = now()
    {:ok, snap_image_id} = Modal.Sandbox.snapshot_filesystem(base)
    log("    snapshot: #{snap_image_id} (#{elapsed(t)})")

    :ok = Modal.Sandbox.terminate(base)
    log("  base sandbox terminated (snapshot survives)")

    snap_image_id
  end

  # ── PHASE 3: race the candidates ────────────────────────────────
  #
  # `Task.async_stream` runs `run_candidate/4` for each patch in
  # parallel. `Enum.reduce_while` halts on the first `:passed`
  # result — which causes async_stream to cancel the still-running
  # tasks. Each task created its sandbox with
  # `:terminate_on_caller_exit: true`, so the cancellation
  # propagates Modal-side: the watchdogs fire `Sandbox.terminate`
  # for the losers automatically.

  defp race_candidates(client, app, snap_image_id) do
    @patches
    |> Task.async_stream(
      fn patch -> run_candidate(client, app, snap_image_id, patch) end,
      ordered: false,
      max_concurrency: length(@patches),
      timeout: 120_000,
      # When the consumer halts, in-flight tasks get :brutal_kill
      # (the default `on_timeout: :kill_task`). Their sandboxes are
      # cleaned up by the per-sandbox watchdog.
      on_timeout: :kill_task
    )
    |> Enum.reduce_while(%{losers: [], winner: nil}, fn
      {:ok, %{passed?: true} = result}, acc ->
        write({:event, "winner: #{result.label} after #{result.duration_ms}ms"})
        {:halt, %{acc | winner: result}}

      {:ok, %{passed?: false} = result}, acc ->
        write({:event, "#{result.label} exited #{result.exit_code} after #{result.duration_ms}ms — not a winner"})
        {:cont, %{acc | losers: [result | acc.losers]}}

      {:exit, reason}, acc ->
        write({:event, "task exited unexpectedly: #{inspect(reason)}"})
        {:cont, acc}
    end)
  end

  # ── Per-candidate execution ──────────────────────────────────────
  #
  # Runs in its own Task. Owns one sandbox + one ContainerProcess.
  # Streams stdout (line-buffered, prefixed) through the shared
  # output writer, then collects the exit code. If the parent's
  # async_stream halts and brutal_kills us, our sandbox's watchdog
  # observes the :DOWN and terminates Modal-side — no leak.

  defp run_candidate(client, app, snap_image_id, %{label: label} = patch) do
    started = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: snap_image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 60,
        # If we get brutal_killed by async_stream halting, the
        # watchdog fires terminate on the sandbox. `:silent` keeps
        # the script log clean — cancellation IS the design here,
        # not an unexpected caller exit worth warning about.
        terminate_on_caller_exit: :silent
      )

    write({:event, "#{label} sandbox up: #{sandbox.id}"})

    # Apply the candidate patch.
    :ok = Modal.Filesystem.write_file(sandbox, Path.join(@workdir, patch.file), patch.content)

    # Exec + stream + await + close in one call. Each stdout chunk
    # is line-buffered then dispatched through the shared output
    # writer with this candidate's label prefix.
    line_sink =
      Modal.ContainerProcess.line_buffered(fn line ->
        write({:line, label, line})
      end)

    result =
      Modal.Sandbox.exec_streaming(sandbox, pytest_cmd(),
        on_stdout: line_sink,
        timeout: 60_000
      )

    # Note: we DON'T terminate the sandbox explicitly. If we're the
    # winner, the parent decides what to do; if we're a loser the
    # parent halts async_stream which brutal_kills us; either way
    # the :silent watchdog handles Modal-side cleanup.

    {exit_code, error} =
      case result do
        {:ok, %{code: code}} -> {code, nil}
        {:error, err} -> {nil, err}
      end

    %{
      label: label,
      description: patch.description,
      exit_code: exit_code,
      passed?: exit_code == 0,
      duration_ms: now() - started,
      sandbox: sandbox,
      error: error
    }
  end

  defp pytest_cmd, do: ["pytest", "-v", "--color=yes", "/work/tests"]

  # ── Output writer (one BEAM process, serialised) ────────────────
  #
  # All log lines, all per-label stream chunks, all events go through
  # this one process. The BEAM mailbox serialises us — no half-lines,
  # no interleaved characters.

  defp start_output_writer do
    pid = spawn_link(fn -> output_loop() end)
    Process.register(pid, :spec_repair_out)
  end

  defp output_loop do
    receive do
      {:line, label, line} ->
        IO.puts(:stderr, IO.ANSI.format([color_for(label), "[#{label}] ", :reset, line]))
        output_loop()

      {:event, msg} ->
        IO.puts(:stderr, IO.ANSI.format([:cyan, "      ", msg, :reset]))
        output_loop()

      {:plain, msg} ->
        IO.puts(:stderr, msg)
        output_loop()
    end
  end

  defp color_for("A"), do: :red
  defp color_for("B"), do: :yellow
  defp color_for("C"), do: :green
  defp color_for(_), do: :white

  defp log(msg), do: write({:plain, msg})

  defp write(msg) do
    case Process.whereis(:spec_repair_out) do
      nil -> IO.puts(:stderr, inspect(msg))
      pid -> send(pid, msg)
    end
  end

  # ── Verdict + telemetry ──────────────────────────────────────────

  defp print_verdict(%{winner: nil, losers: losers}) do
    log("\n  ✗ no candidate passed all tests")

    for l <- Enum.reverse(losers) do
      log("    [#{l.label}] #{l.description} → exit #{l.exit_code} (#{l.duration_ms}ms)")
    end
  end

  defp print_verdict(%{winner: w, losers: losers}) do
    log("")
    log("  ✓ WINNER: #{w.label}")
    log("  description: #{w.description}")
    log("  pytest:      exit #{w.exit_code} in #{w.duration_ms}ms")
    log("  sandbox:     #{w.sandbox.id}")

    if losers != [] do
      log("\n  losers (finished before the winner emerged):")

      for l <- Enum.reverse(losers) do
        log("    [#{l.label}] #{l.description} → exit #{l.exit_code} (#{l.duration_ms}ms)")
      end
    end

    log("\n  any other in-flight candidates were brutal_killed by Task.async_stream;")
    log("  their sandboxes are being terminated Modal-side by their watchdogs.")
  end

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "spec-repair-telemetry",
      [
        [:modal, :rpc, :stop],
        [:modal, :worker_rpc, :stop]
      ],
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
  defp elapsed(t), do: "#{now() - t}ms"
end

SpeculativeRepair.run()
