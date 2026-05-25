# Real LLM-driven coding agent: Python repo, Elixir orchestrator, Claude
# proposes the patches.
#
# The full coding-agent loop:
#
#   1. Boot a Python sandbox + write a deliberately-broken file + a
#      failing test
#   2. Show the human (you) what's broken
#   3. Ask Claude (via the messages API) for N candidate patches that
#      take diverse approaches to the fix
#   4. Run the speculative-repair pattern from
#      `scripts/speculative_repair.exs` against the LLM's actual output
#      — fan out N parallel sandboxes from a snapshot, race them on
#      `pytest`, first one passing wins, others get brutal_killed by
#      Task.async_stream and their watchdogs clean up Modal-side
#   5. Print the winning patch + the diff
#
# What this proves above and beyond `speculative_repair.exs`:
#
#   * The orchestration shape works with *real* LLM output, not
#     hand-picked patches. LLMs hallucinate; the loop has to be robust
#     to junk JSON, off-by-one code, more-than-N suggestions, etc.
#   * Diversity in Claude's responses naturally produces some patches
#     that fail and some that pass — same as a real agent run.
#   * The cost story: ~1 cent per repair cycle (1 Haiku call + ~3s
#     of compute across N small sandboxes).
#
# Setup:
#
#     export ANTHROPIC_API_KEY=sk-ant-...
#     elixir scripts/llm_repair.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:req, "~> 0.5"}
])

defmodule LLMRepair do
  @app_name "modal-elixir-llm-repair"
  @workdir "/work"
  @num_candidates 3
  @model "claude-haiku-4-5-20251001"
  @workdir_files [
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

  # ── Entry point ──────────────────────────────────────────────────

  def run do
    setup_telemetry()
    start_output_writer()
    :logger.set_application_level(:grpc, :warning)

    anthropic_key = anthropic_key!()
    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    # ── PHASE 1: show what's broken ─────────────────────────────
    log("\n── PHASE 1: the bug ─────────────")
    {orig_path, orig_code} = Enum.find(@workdir_files, fn {p, _} -> p =~ "palindrome.py" end)
    log("file:    #{orig_path}")
    log("test:    pytest tests/")
    log("symptom: test_punctuation_and_case fails (\"A man, a plan, a canal: Panama\" → False)")

    # ── PHASE 2: image + base sandbox + snapshot ────────────────
    snap_image_id = build_base_snapshot(client, app)

    # ── PHASE 3: ask Claude for N candidate patches ─────────────
    log("\n── PHASE 3: ask Claude for #{@num_candidates} candidate fixes ─────────────")
    t = now()
    patches = ask_claude_for_patches!(anthropic_key, orig_code, lookup_file("tests/test_palindrome.py"))
    log("got #{length(patches)} candidates in #{elapsed(t)}\n")

    for {p, i} <- Enum.with_index(patches, 1) do
      log("  #{i}. [#{p.label}] #{p.description}")
    end

    # ── PHASE 4: speculative repair against Claude's output ─────
    log("\n── PHASE 4: speculative repair — race in parallel sandboxes ─────────────")
    log("(streaming each candidate's pytest output, prefixed with its label)\n")
    t = now()

    result = race_candidates(client, app, snap_image_id, patches)

    log("\n── PHASE 5: verdict ─────────────")
    log("parallel phase: #{elapsed(t)}")

    case result do
      {:winner, w} ->
        log("\n  ✓ WINNER: [#{w.label}] #{w.description}")
        log("  pytest exit: #{w.exit_code} in #{w.duration_ms}ms")
        log("\n  winning patch (src/palindrome.py):")
        log("  ─────────────────────────────────────")
        for line <- String.split(w.code, "\n"), do: log("    " <> line)
        log("  ─────────────────────────────────────")

      :no_winner ->
        log("\n  ✗ all #{length(patches)} candidates failed pytest")
        log("  (an LLM iteration loop would now feed the failures back to the model)")
    end

    log("\n── PHASE 6: telemetry ─────────────")
    print_telemetry()
  end

  # ── Claude API ───────────────────────────────────────────────────

  defp ask_claude_for_patches!(api_key, src_code, test_code) do
    prompt = """
    You're a Python coding agent. Here's a file with a bug, plus a failing
    test. The test_punctuation_and_case test fails because the current
    implementation doesn't handle punctuation or case.

    --- src/palindrome.py ---
    #{src_code}

    --- tests/test_palindrome.py ---
    #{test_code}

    Generate exactly #{@num_candidates} candidate fixes for `src/palindrome.py`
    that take different approaches (e.g., different ways to clean the input,
    different control flow). At least one should genuinely fix all tests.
    Variety is good — it's OK if some candidates are subtly wrong.

    Return ONLY a JSON array, no markdown fence, no commentary. Exact shape:

    [
      {"description": "one-line summary", "code": "full updated palindrome.py source"},
      {"description": "...", "code": "..."},
      {"description": "...", "code": "..."}
    ]

    The "code" field must be the COMPLETE file contents, ready to write
    to disk — including the function signature and any imports needed.
    """

    body = %{
      model: @model,
      max_tokens: 4096,
      messages: [%{role: "user", content: prompt}]
    }

    log("  calling #{@model}...")

    response =
      Req.post!("https://api.anthropic.com/v1/messages",
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"},
          {"content-type", "application/json"}
        ],
        json: body,
        receive_timeout: 60_000
      )

    case response.status do
      200 -> parse_patches!(response.body)
      _ -> raise "Anthropic API returned #{response.status}: #{inspect(response.body)}"
    end
  end

  defp parse_patches!(%{"content" => [%{"text" => text} | _]}) do
    json = strip_markdown_fence(text)

    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.map(fn {%{"description" => desc, "code" => code}, i} ->
          %{
            label: <<?A + i>>,
            description: desc,
            code: code
          }
        end)

      {:ok, other} ->
        raise "Claude returned non-list JSON: #{inspect(other)}"

      {:error, err} ->
        raise "Claude returned non-JSON text:\n#{text}\n\nParse error: #{inspect(err)}"
    end
  end

  # Claude occasionally returns ```json ... ``` wrapping despite being
  # asked not to. Strip it so Jason.decode doesn't choke.
  defp strip_markdown_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\n?/, "")
    |> String.replace(~r/\n?```\z/, "")
    |> String.trim()
  end

  defp lookup_file(path) do
    {_, content} = Enum.find(@workdir_files, fn {p, _} -> p == path end)
    content
  end

  # ── Modal: base sandbox + snapshot (same shape as speculative_repair.exs) ──

  defp build_base_snapshot(client, app) do
    log("\n── PHASE 2: image + base sandbox + snapshot ─────────────")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        ["FROM python:3.14-slim", "RUN pip install --no-cache-dir pytest"],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image_id} [#{status}] (#{elapsed(t)})")

    t = now()

    base =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 300,
        terminate_on_caller_exit: :silent
      )

    for {path, content} <- @workdir_files do
      full = Path.join(@workdir, path)
      :ok = Modal.Filesystem.mkdir(base, Path.dirname(full), parents: true)
      :ok = Modal.Filesystem.write_file(base, full, content)
    end

    log("base sandbox: #{base.id} + files written (#{elapsed(t)})")

    log("  snapshotting filesystem")
    t = now()
    {:ok, snap_image_id} = Modal.Sandbox.snapshot_filesystem(base)
    log("    snapshot: #{snap_image_id} (#{elapsed(t)})")

    :ok = Modal.Sandbox.terminate(base)
    snap_image_id
  end

  # ── Speculative race (same shape as speculative_repair.exs) ─────

  defp race_candidates(client, app, snap_image_id, patches) do
    patches
    |> Task.async_stream(
      fn patch -> run_candidate(client, app, snap_image_id, patch) end,
      ordered: false,
      max_concurrency: length(patches),
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while(:no_winner, fn
      {:ok, %{passed?: true} = r}, _ ->
        write({:event, "winner: #{r.label} after #{r.duration_ms}ms"})
        {:halt, {:winner, r}}

      {:ok, %{passed?: false} = r}, acc ->
        write({:event, "#{r.label} exited #{r.exit_code} after #{r.duration_ms}ms — not a winner"})
        {:cont, acc}

      {:exit, reason}, acc ->
        write({:event, "task exited unexpectedly: #{inspect(reason)}"})
        {:cont, acc}
    end)
  end

  defp run_candidate(client, app, snap_image_id, patch) do
    started = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: snap_image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 60,
        terminate_on_caller_exit: :silent
      )

    write({:event, "#{patch.label} sandbox up: #{sandbox.id}"})

    :ok = Modal.Filesystem.write_file(sandbox, "/work/src/palindrome.py", patch.code)

    line_sink =
      Modal.ContainerProcess.line_buffered(fn line -> write({:line, patch.label, line}) end)

    result =
      Modal.Sandbox.exec_streaming(sandbox, ["pytest", "-v", "--color=yes", "/work/tests"],
        on_stdout: line_sink,
        timeout: 60_000
      )

    {exit_code, _err} =
      case result do
        {:ok, %{code: code}} -> {code, nil}
        {:error, err} -> {nil, err}
      end

    %{
      label: patch.label,
      description: patch.description,
      code: patch.code,
      exit_code: exit_code,
      passed?: exit_code == 0,
      duration_ms: now() - started,
      sandbox: sandbox
    }
  end

  # ── Output writer ────────────────────────────────────────────────

  defp start_output_writer do
    pid = spawn_link(fn -> output_loop() end)
    Process.register(pid, :llm_repair_out)
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
  defp color_for("D"), do: :magenta
  defp color_for("E"), do: :blue
  defp color_for(_), do: :white

  defp log(msg), do: write({:plain, msg})

  defp write(msg) do
    case Process.whereis(:llm_repair_out) do
      nil -> IO.puts(:stderr, inspect(msg))
      pid -> send(pid, msg)
    end
  end

  # ── Telemetry ────────────────────────────────────────────────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "llm-repair-telemetry",
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
  end

  defp print_section(events) do
    events
    |> Enum.sort()
    |> Enum.each(fn {{_, method, status, error_kind}, count} ->
      tag = if error_kind, do: " (#{error_kind})", else: ""
      log("    #{count |> to_string() |> String.pad_leading(3)} × #{method} #{status}#{tag}")
    end)
  end

  # ── Credentials ──────────────────────────────────────────────────

  defp anthropic_key! do
    System.get_env("ANTHROPIC_API_KEY") ||
      raise """
      Set ANTHROPIC_API_KEY in your environment.

      You can get a key at https://console.anthropic.com/. The script
      will spend roughly 1 cent per run (one Haiku call + a few
      seconds of Modal compute across the parallel sandboxes).
      """
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

LLMRepair.run()
