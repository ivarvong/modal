# Full circle: Elixir scaffolds a uv Python project → Cloudflare
# Artifacts holds it → Modal sandbox clones it → Claude Code adds a
# feature inside the sandbox → pushes back to CF → Elixir clones the
# post-Claude repo via exgit, computes the diff against the baseline,
# and prints what Claude changed line-by-line.
#
# The whole loop is BEAM-orchestrated: nothing shells out to `git`
# locally, nothing manages temp checkouts, nothing depends on a
# CI runner. Just Elixir, exgit, CF Artifacts, Modal, and Claude.
#
#     elixir scripts/uv_roundtrip.exs                          # default ticket
#     elixir scripts/uv_roundtrip.exs "Add a fizzbuzz function"
#
# Needs (all in .env):
#   MODAL_TOKEN_ID, MODAL_TOKEN_SECRET   — modal.com
#   CF_ACCOUNT_ID,  CF_API_TOKEN         — cloudflare.com
#   ANTHROPIC_API_KEY                    — console.anthropic.com

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:exgit, github: "ivarvong/exgit", ref: "main"}
])

defmodule UvRoundtrip do
  alias Exgit.{Diff, ObjectStore, RefStore}
  alias Exgit.Object.{Blob, Commit, Tree}

  @app_name "modal-elixir-uv-roundtrip"

  # The uv project we scaffold and push at the start. Six files.
  @initial_files [
    {"pyproject.toml",
     """
     [project]
     name = "widget"
     version = "0.1.0"
     description = "A small widget package built via the Elixir→Modal→Claude loop."
     requires-python = ">=3.10"

     [project.optional-dependencies]
     dev = ["pytest"]

     [build-system]
     requires = ["hatchling"]
     build-backend = "hatchling.build"

     [tool.hatch.build.targets.wheel]
     packages = ["src/widget"]
     """},
    {"src/widget/__init__.py",
     """
     __version__ = "0.1.0"
     """},
    {"src/widget/main.py",
     """
     def hello(name: str = "world") -> str:
         \"\"\"Return a friendly greeting.\"\"\"
         return f"Hello, {name}!"
     """},
    {"tests/test_main.py",
     """
     from widget.main import hello


     def test_hello_default():
         assert hello() == "Hello, world!"


     def test_hello_named():
         assert hello("Modal") == "Hello, Modal!"
     """},
    {"README.md",
     """
     # widget

     A tiny Python package scaffolded by Elixir via
     [exgit](https://github.com/ivarvong/exgit), pushed to Cloudflare
     Artifacts, edited by [Claude Code](https://claude.ai/code) inside
     a [Modal](https://modal.com) sandbox, then read back by Elixir.

     The whole loop is orchestrated from the BEAM — no `git` binary,
     no temp directories, no CI runner.
     """},
    {".gitignore",
     """
     __pycache__/
     *.pyc
     .venv/
     .pytest_cache/
     """}
  ]

  @default_ticket """
  Add a recursive `factorial(n: int) -> int` function to `src/widget/main.py`.
  Add tests in `tests/test_main.py` covering:
    * `factorial(0) == 1`
    * `factorial(5) == 120`
    * `factorial(-1)` raises `ValueError`
  Keep the existing `hello` function and its tests untouched.
  After editing, run `pytest -v` to confirm everything passes.
  """

  def run(args) do
    :logger.set_application_level(:grpc, :warning)
    setup_telemetry()
    setup_phases()
    setup_costs()

    ticket =
      case args do
        [t | _] when is_binary(t) and t != "" -> t
        _ -> @default_ticket
      end

    anthropic_key =
      System.get_env("ANTHROPIC_API_KEY") || raise "set ANTHROPIC_API_KEY"

    cf_account = System.get_env("CF_ACCOUNT_ID") || raise "set CF_ACCOUNT_ID"
    cf_token = System.get_env("CF_API_TOKEN") || raise "set CF_API_TOKEN"

    cf = Exgit.CloudflareArtifacts.new(account_id: cf_account, api_token: cf_token)

    # Unique enough for back-to-back re-runs (epoch second + small
    # random tail). A bare epoch second collided when two runs landed
    # in the same wall-clock second.
    repo_name =
      "uv-roundtrip-#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"

    log("repo:    #{repo_name}")
    if ticket != @default_ticket, do: log("ticket:  (custom from argv)")

    try do
      do_run(cf, repo_name, anthropic_key, ticket)
    after
      phase("cleanup", fn ->
        case Exgit.CloudflareArtifacts.delete_repo(cf, repo_name) do
          {:ok, _} -> log("  ✓ deleted CF repo #{repo_name}")
          other -> log("  ! could not delete CF repo (#{inspect(other)}); TTLs will reap it")
        end
      end)

      log("\n── timings ─────────────")
      print_phase_summary()

      log("\n── cost ─────────────")
      print_cost_summary()

      log("\n── telemetry ─────────────")
      print_telemetry()
    end
  end

  # ── The loop ─────────────────────────────────────────────────────

  defp do_run(cf, repo_name, anthropic_key, ticket) do
    {:ok, repo} =
      phase("CF repo create", fn ->
        {:ok, r} =
          Exgit.CloudflareArtifacts.create_repo(cf, name: repo_name, default_branch: "main")

        log("  ✓ remote: #{r.remote}")
        {:ok, r}
      end)

    {parent_commit_sha, parent_tree_sha} =
      phase("exgit: scaffold uv project + push", fn ->
        result = push_initial_commit!(repo.remote, repo.token)
        log("  ✓ pushed #{length(@initial_files)} files in a single commit")
        result
      end)

    {:ok, rw_token} =
      Exgit.CloudflareArtifacts.create_token(cf,
        repo: repo_name,
        scope: :write,
        ttl: 600
      )

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    image_id =
      phase("Modal image (build or cache)", fn ->
        {:ok, image_id, image_status} =
          Modal.Image.get_or_create(
            client,
            [
              "FROM python:3.14-slim",
              "RUN apt-get update && apt-get install -y --no-install-recommends " <>
                "git curl ca-certificates && rm -rf /var/lib/apt/lists/*",
              # Official Claude Code installer. Download first so a failed
              # curl actually fails the layer.
              ~S{RUN bash -c 'set -eo pipefail; curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && bash /tmp/install.sh'},
              "ENV PATH=/root/.local/bin:$PATH",
              "RUN claude --version",
              "RUN pip install --no-cache-dir pytest"
            ],
            app: app,
            on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
          )

        log("  ✓ image: #{image_id} [#{image_status}]")
        image_id
      end)

    secret_name = "uv-roundtrip-secrets-#{System.os_time(:second)}"

    {:ok, secret_id} =
      Modal.Secret.create(client,
        app: app,
        name: secret_name,
        env: %{
          "REMOTE" => repo.remote,
          "TOKEN" => rw_token.plaintext,
          "ANTHROPIC_API_KEY" => anthropic_key
        }
      )

    sandbox_create_ms = now()

    sandbox =
      phase("Modal sandbox boot", fn ->
        sb =
          Modal.Sandbox.create!(client,
            app: app,
            image_id: image_id,
            cmd: ["sleep", "infinity"],
            secret_ids: [secret_id],
            timeout_secs: 600,
            idle_timeout_secs: 60,
            terminate_on_caller_exit: :silent
          )

        log("  ✓ sandbox: #{sb.id}")
        sb
      end)

    try do
      phase("sandbox: clone + Claude + push", fn -> run_in_sandbox!(sandbox, ticket) end)
    after
      :ok = Modal.Sandbox.terminate(sandbox)
      sandbox_terminate_ms = now()
      sandbox_lifetime_s = (sandbox_terminate_ms - sandbox_create_ms) / 1000

      # Record for the cost summary at the end. Default Modal sandbox
      # resources (no :cpu / :memory_mb specified above): 0.125 vCPU,
      # 128 MiB. If you change the sandbox config, update these too.
      Agent.update(__MODULE__.Costs, fn s ->
        Map.merge(s, %{
          sandbox_lifetime_s: sandbox_lifetime_s,
          sandbox_cpu_cores: 0.125,
          sandbox_memory_mb: 128
        })
      end)
    end

    {:ok, read_token} =
      Exgit.CloudflareArtifacts.create_token(cf,
        repo: repo_name,
        scope: :read,
        ttl: 300
      )

    post_repo =
      phase("exgit: clone post-Claude repo", fn ->
        {:ok, r} =
          Exgit.clone(repo.remote,
            auth: Exgit.Credentials.Artifacts.auth(read_token.plaintext)
          )

        {:ok, head_sha} = RefStore.resolve(r.ref_store, "refs/heads/main")
        log("  ✓ cloned, HEAD = #{hex(head_sha)}")
        r
      end)

    phase("diff: what Claude changed", fn ->
      render_diff(post_repo, parent_commit_sha, parent_tree_sha)
    end)
  end

  # ── exgit: build + push the initial commit ───────────────────────
  #
  # Returns `{parent_commit_sha, parent_tree_sha}` so the post-Claude
  # diff phase can target the trees directly without re-resolving any
  # refs.

  defp push_initial_commit!(remote, token) do
    {:ok, r} = Exgit.init([])

    {tree_sha, store} = build_tree(r.object_store, @initial_files)

    me = "elixir <demo@modal.local> #{System.os_time(:second)} +0000"

    {:ok, commit_sha, store} =
      ObjectStore.put(
        store,
        Commit.new(
          tree: tree_sha,
          parents: [],
          author: me,
          committer: me,
          message: "Scaffold uv project via exgit\n"
        )
      )

    {:ok, refs} = RefStore.write(r.ref_store, "refs/heads/main", commit_sha, [])
    r = %{r | object_store: store, ref_store: refs}

    {:ok, _} =
      Exgit.push(r, remote,
        auth: Exgit.Credentials.Artifacts.auth(token),
        refspecs: ["refs/heads/main"]
      )

    {commit_sha, tree_sha}
  end

  # Recursive tree builder for a flat path-to-content list.
  #
  # Strategy: group entries by their top-level path segment. Entries
  # at the root (no `/`) become blob entries directly. Entries under
  # a directory get grouped under that directory's name, the path is
  # peeled, and `build_tree/2` recurses on the inner list. Each
  # subtree's SHA bubbles up as a `40000`-mode entry on the parent.
  #
  # Result: one Tree object per directory, blobs written along the
  # way, root tree's SHA returned. Single-pass; for thousands of
  # files you'd want a real tree builder that handles disk-backed
  # stores.
  defp build_tree(store, files) do
    by_top =
      Enum.group_by(
        files,
        fn {path, _} ->
          case String.split(path, "/", parts: 2) do
            [single] -> {:file, single}
            [dir, _rest] -> {:dir, dir}
          end
        end,
        fn {path, content} ->
          case String.split(path, "/", parts: 2) do
            [single] -> {:file, single, content}
            [_dir, rest] -> {:nested, rest, content}
          end
        end
      )

    {entries, store} =
      Enum.reduce(by_top, {[], store}, fn
        {{:file, name}, [{:file, _name, content}]}, {acc, store} ->
          {:ok, blob_sha, store} = ObjectStore.put(store, Blob.new(content))
          {[{"100644", name, blob_sha} | acc], store}

        {{:dir, dirname}, nested}, {acc, store} ->
          inner = Enum.map(nested, fn {:nested, rest, content} -> {rest, content} end)
          {sub_sha, store} = build_tree(store, inner)
          {[{"40000", dirname, sub_sha} | acc], store}
      end)

    {:ok, tree_sha, store} = ObjectStore.put(store, Tree.new(entries))
    {tree_sha, store}
  end

  # ── Modal sandbox: clone → Claude → push ─────────────────────────

  defp run_in_sandbox!(sandbox, ticket) do
    script = compose_script(ticket)

    on_stdout =
      Modal.ContainerProcess.line_buffered(fn line ->
        # Sniff Claude's cost / usage markers as they stream past.
        # Each marker is "CLAUDE_<KEY>: <value>" printed by the inline
        # Python in compose_script/1. We forward the line to stderr
        # for the human AND stash the parsed value for the cost
        # summary at the end of the run.
        case parse_marker(line) do
          {:ok, key, value} ->
            Agent.update(__MODULE__.Costs, &Map.put(&1, key, value))

          :none ->
            :ok
        end

        IO.puts(:stderr, IO.ANSI.format([:faint, "  [sandbox] ", :reset, line]))
      end)

    # Capture stderr separately so a failed `git push` (or any other
    # bash command) gets its actual diagnostic into the raise message,
    # not buried in 100 lines of interleaved stdout.
    {:ok, stderr_agent} = Agent.start_link(fn -> [] end)

    on_stderr = fn chunk ->
      Agent.update(stderr_agent, fn acc -> [chunk | acc] end)
    end

    result =
      Modal.Sandbox.exec_streaming(sandbox, ["bash", "-c", script],
        on_stdout: on_stdout,
        on_stderr: on_stderr,
        timeout: 5 * 60_000
      )

    case result do
      {:ok, %{code: 0}} ->
        :ok

      {:ok, %{code: code}} ->
        stderr_tail =
          stderr_agent
          |> Agent.get(& &1)
          |> Enum.reverse()
          |> IO.iodata_to_binary()
          |> String.trim_trailing()
          |> String.split("\n")
          |> Enum.take(-20)
          |> Enum.join("\n")

        raise """
        sandbox bash script exited #{code}.
        Last 20 lines of stderr:
        #{stderr_tail}
        """

      {:error, err} ->
        raise err
    end
  end

  defp compose_script(ticket) do
    # Single bash script driving the whole sandbox-side flow. Each
    # phase has its own banner so the streamed output is scannable.
    # `set -euo pipefail` + explicit `git add` paths keep stray pyc
    # files out of Claude's commit.
    """
    set -euo pipefail

    echo "── clone the CF repo ──"
    mkdir -p /work && cd /work
    git -c http.extraheader="Authorization: Bearer $TOKEN" clone "$REMOTE" repo
    cd repo
    git config user.email "claude@modal.local"
    git config user.name  "Claude (via Modal)"

    echo
    echo "── install + verify baseline tests pass ──"
    # Direct pip install — we don't need uv-the-tool for this demo,
    # just the project layout. Avoids the `uv sync --extra dev`
    # path where a missing extra would silently fall back.
    pip install --quiet -e . pytest
    pytest -v

    echo
    echo "── Claude adds the feature ──"
    # --output-format json gives us a final `result` object with
    # `total_cost_usd` + `usage` (tokens). We save to disk, then
    # extract both the text result (for the human) and the cost
    # markers (for the orchestrator to grep out).
    claude -p #{shell_quote(ticket)} --permission-mode acceptEdits --output-format json \\
      > /tmp/claude.json 2> /tmp/claude.err || {
      echo "── claude failed; stderr: ──"
      cat /tmp/claude.err
      exit 1
    }

    python3 - <<'PY'
    import json
    with open('/tmp/claude.json') as f:
        data = json.load(f)
    # claude --output-format json can return either a JSON array of
    # events (with the result envelope as the last element) or the
    # bare result object directly, depending on CLI version. Handle
    # both shapes defensively.
    if isinstance(data, list):
        result = data[-1]
    else:
        result = data
    u = result.get('usage', {})
    print('CLAUDE_COST_USD:', f"{result.get('total_cost_usd', 0):.6f}")
    print('CLAUDE_INPUT_TOKENS:', u.get('input_tokens', 0))
    print('CLAUDE_OUTPUT_TOKENS:', u.get('output_tokens', 0))
    print('CLAUDE_CACHE_READ_TOKENS:', u.get('cache_read_input_tokens', 0))
    print('CLAUDE_CACHE_CREATE_TOKENS:', u.get('cache_creation_input_tokens', 0))
    print('CLAUDE_DURATION_MS:', result.get('duration_ms', 0))
    print('CLAUDE_NUM_TURNS:', result.get('num_turns', 0))
    print('── claude response ──')
    print(result.get('result', '<no result field>'))
    PY

    echo
    echo "── verify Claude's tests pass ──"
    pytest -v

    echo
    echo "── commit + push to main ──"
    # Explicit paths, not `git add -A`: keeps pyc / venv / cache
    # files out of the commit even if .gitignore doesn't catch one.
    git add src/ tests/ pyproject.toml README.md
    git diff --cached --stat
    git commit -m "Add via Claude (Modal sandbox)"
    git -c http.extraheader="Authorization: Bearer $TOKEN" push origin main
    echo "── done ──"
    """
  end

  defp shell_quote(s),
    do: "'" <> String.replace(s, "'", "'\"'\"'") <> "'"

  # Parse a single CLAUDE_<KEY>: <value> marker line. Returns
  # `{:ok, atom_key, parsed_value}` when matched, `:none` otherwise.
  # Values are coerced based on what the marker carries: floats for
  # cost, integers for token counts, integers for duration/turns.
  defp parse_marker(line) do
    case Regex.run(~r/^CLAUDE_([A-Z_]+):\s*(.+)$/, String.trim(line)) do
      [_, "COST_USD", v] -> {:ok, :claude_cost_usd, parse_float(v)}
      [_, "INPUT_TOKENS", v] -> {:ok, :claude_input_tokens, parse_int(v)}
      [_, "OUTPUT_TOKENS", v] -> {:ok, :claude_output_tokens, parse_int(v)}
      [_, "CACHE_READ_TOKENS", v] -> {:ok, :claude_cache_read_tokens, parse_int(v)}
      [_, "CACHE_CREATE_TOKENS", v] -> {:ok, :claude_cache_create_tokens, parse_int(v)}
      [_, "DURATION_MS", v] -> {:ok, :claude_duration_ms, parse_int(v)}
      [_, "NUM_TURNS", v] -> {:ok, :claude_num_turns, parse_int(v)}
      _ -> :none
    end
  end

  defp parse_float(s), do: s |> Float.parse() |> elem(0)
  defp parse_int(s), do: s |> Integer.parse() |> elem(0)

  # ── exgit: render the parent..HEAD diff ──────────────────────────

  defp render_diff(repo, parent_commit_sha, parent_tree_sha) do
    {:ok, head_sha} = RefStore.resolve(repo.ref_store, "refs/heads/main")
    {:ok, head_commit} = ObjectStore.get(repo.object_store, head_sha)
    {:ok, parent_commit} = ObjectStore.get(repo.object_store, parent_commit_sha)

    log("  parent (ours):       #{hex(parent_commit_sha)} — #{String.trim(parent_commit.message)}")
    log("  HEAD (post-Claude):  #{hex(head_sha)} — #{String.trim(head_commit.message)}")

    head_tree_sha = Commit.tree(head_commit)
    {:ok, changes} = Diff.trees(repo, parent_tree_sha, head_tree_sha)

    if changes == [] do
      log("  (no changes — Claude declined to ship anything)")
    else
      log("")
      log("  #{length(changes)} path(s) changed:")

      for c <- changes do
        marker =
          case c.op do
            :added -> "+"
            :removed -> "-"
            :modified -> "~"
          end

        log("    #{marker} #{c.path}")
      end

      log("")

      for c <- changes do
        log("  ── #{String.upcase(to_string(c.op))}: #{c.path} ──")
        render_one(repo, c)
        log("")
      end
    end

    log("  ✓ Full circle: Elixir → CF → Modal+Claude → CF → Elixir, all observed.")
  end

  defp render_one(repo, %{op: :added, new_sha: sha}) do
    {:ok, %Blob{data: data}} = ObjectStore.get(repo.object_store, sha)

    data
    |> IO.iodata_to_binary()
    |> String.split("\n", trim: false)
    |> Enum.each(fn line -> log("  + " <> line) end)
  end

  defp render_one(repo, %{op: :removed, old_sha: sha}) do
    {:ok, %Blob{data: data}} = ObjectStore.get(repo.object_store, sha)

    data
    |> IO.iodata_to_binary()
    |> String.split("\n", trim: false)
    |> Enum.each(fn line -> log("  - " <> line) end)
  end

  defp render_one(repo, %{op: :modified, old_sha: a_sha, new_sha: b_sha}) do
    {:ok, %Blob{data: a_data}} = ObjectStore.get(repo.object_store, a_sha)
    {:ok, %Blob{data: b_data}} = ObjectStore.get(repo.object_store, b_sha)

    a_lines = a_data |> IO.iodata_to_binary() |> String.split("\n")
    b_lines = b_data |> IO.iodata_to_binary() |> String.split("\n")

    pairs = Exgit.Diff.LineDiff.matched_pairs(a_lines, b_lines)
    unified(a_lines, b_lines, pairs)
  end

  # Minimal unified-style renderer: walk both sides via the matched
  # pairs (LCS-ish) and emit `-`, `+`, or `space` per line. Not
  # context-collapsed like real `git diff`, but accurate per-line
  # and trivial to read.
  defp unified(a_lines, b_lines, pairs) do
    pair_a_to_b = Map.new(pairs)
    pair_b_to_a = Map.new(pairs, fn {a, b} -> {b, a} end)

    walk(a_lines, b_lines, 0, 0, pair_a_to_b, pair_b_to_a)
  end

  defp walk(a, b, ai, bi, _a_to_b, _b_to_a)
       when ai >= length(a) and bi >= length(b),
       do: :ok

  defp walk(a, b, ai, bi, a_to_b, b_to_a) do
    case {Map.get(a_to_b, ai), Map.get(b_to_a, bi)} do
      {^bi, ^ai} ->
        # Matched pair: this line is unchanged.
        log("    " <> Enum.at(a, ai))
        walk(a, b, ai + 1, bi + 1, a_to_b, b_to_a)

      {_, _} when ai < length(a) and not is_map_key(a_to_b, ai) ->
        log("  - " <> Enum.at(a, ai))
        walk(a, b, ai + 1, bi, a_to_b, b_to_a)

      {_, _} when bi < length(b) and not is_map_key(b_to_a, bi) ->
        log("  + " <> Enum.at(b, bi))
        walk(a, b, ai, bi + 1, a_to_b, b_to_a)

      _ ->
        # Both indices map but to non-current counterparts; advance
        # whichever points further ahead so we don't loop.
        cond do
          ai < length(a) -> walk(a, b, ai + 1, bi, a_to_b, b_to_a)
          bi < length(b) -> walk(a, b, ai, bi + 1, a_to_b, b_to_a)
          true -> :ok
        end
    end
  end

  defp hex(<<sha::binary>>), do: Base.encode16(sha, case: :lower) |> String.slice(0, 12)

  # ── Phase timing ─────────────────────────────────────────────────
  #
  # Wraps each meaningful step so the end-of-run summary shows exactly
  # where the wall-clock went. Pure side-channel — `phase/2` returns
  # `fun`'s value untouched so the caller's `with`/`=` continue to work.

  defp setup_phases do
    {:ok, _} = Agent.start_link(fn -> [] end, name: __MODULE__.Phases)
  end

  defp setup_costs do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Costs)
  end

  # Modal sandbox compute pricing (us-east, current at time of
  # writing — verify against modal.com/pricing if invoices diverge).
  @cpu_cost_per_core_sec 0.0000131
  @mem_cost_per_gib_sec 0.00000222

  defp print_cost_summary do
    costs = Agent.get(__MODULE__.Costs, & &1)

    # ── Modal: sandbox compute only. Image build / storage are not
    # billed per-run (cached after first build); volumes / egress
    # aren't used by this script. So sandbox lifetime × resources
    # is the entire Modal bill.
    case costs do
      %{sandbox_lifetime_s: secs, sandbox_cpu_cores: cores, sandbox_memory_mb: mem_mb} ->
        mem_gib = mem_mb / 1024
        cpu_cost = cores * @cpu_cost_per_core_sec * secs
        mem_cost = mem_gib * @mem_cost_per_gib_sec * secs
        modal_total = cpu_cost + mem_cost

        log("  Modal:     $#{fmt_cost(modal_total)}  (sandbox: #{Float.round(secs, 1)}s × #{cores} vCPU × #{mem_mb} MiB)")
        log("    cpu:      $#{fmt_cost(cpu_cost)}")
        log("    memory:   $#{fmt_cost(mem_cost)}")

      _ ->
        log("  Modal:     (no sandbox-lifetime data captured)")
    end

    # ── Anthropic: from `claude --output-format json`'s `total_cost_usd`.
    # The CLI computes this from the actual input/output/cache tokens
    # against the model's per-token rates, so it's the source of truth
    # (no estimation needed).
    case costs do
      %{claude_cost_usd: usd} ->
        input = Map.get(costs, :claude_input_tokens, 0)
        output = Map.get(costs, :claude_output_tokens, 0)
        cache_r = Map.get(costs, :claude_cache_read_tokens, 0)
        cache_c = Map.get(costs, :claude_cache_create_tokens, 0)
        turns = Map.get(costs, :claude_num_turns, 0)

        log(
          "  Anthropic: $#{fmt_cost(usd)}  (#{turns} turn(s); #{input}+#{cache_c}+#{cache_r} in / #{output} out)"
        )

      _ ->
        log("  Anthropic: (no claude usage data captured)")
    end

    # ── Total run cost
    modal_total =
      case costs do
        %{sandbox_lifetime_s: secs, sandbox_cpu_cores: c, sandbox_memory_mb: m} ->
          c * @cpu_cost_per_core_sec * secs + m / 1024 * @mem_cost_per_gib_sec * secs

        _ ->
          0.0
      end

    grand_total = modal_total + Map.get(costs, :claude_cost_usd, 0.0)

    log("  ─────────")
    log("  Total:     $#{fmt_cost(grand_total)}  (Modal #{pct(modal_total, grand_total)}%, Anthropic #{pct(grand_total - modal_total, grand_total)}%)")
  end

  defp fmt_cost(f), do: :erlang.float_to_binary(f, decimals: 6)
  defp pct(_, whole) when whole in [0.0, +0.0, -0.0], do: "0"
  defp pct(part, whole), do: "#{trunc(part * 100 / whole)}"

  defp phase(name, fun) do
    log("\n── PHASE: #{name} ─────────────")
    t = now()
    result = fun.()
    ms = now() - t
    Agent.update(__MODULE__.Phases, fn acc -> [{name, ms} | acc] end)
    log("  (#{ms}ms)")
    result
  end

  defp print_phase_summary do
    phases = __MODULE__.Phases |> Agent.get(& &1) |> Enum.reverse()
    total = phases |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    longest_name = phases |> Enum.map(fn {n, _} -> String.length(n) end) |> Enum.max(fn -> 0 end)

    for {name, ms} <- phases do
      pct = if total > 0, do: trunc(ms * 100 / total), else: 0
      log("  #{String.pad_trailing(name, longest_name)}  #{fmt_ms(ms)} (#{pct}%)")
    end

    log("  #{String.duplicate("─", longest_name + 16)}")
    log("  #{String.pad_trailing("total", longest_name)}  #{fmt_ms(total)}")
  end

  defp fmt_ms(ms) when ms < 1000, do: String.pad_leading("#{ms}ms", 7)
  defp fmt_ms(ms), do: String.pad_leading("#{Float.round(ms / 1000, 2)}s", 7)

  # ── Telemetry ────────────────────────────────────────────────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "uv-roundtrip-telemetry",
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

  # ── tiny utilities ───────────────────────────────────────────────

  defp now, do: System.monotonic_time(:millisecond)
  defp log(msg), do: IO.puts(:stderr, msg)
end

UvRoundtrip.run(System.argv())
