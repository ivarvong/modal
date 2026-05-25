# Run the Claude Code CLI headless inside a Modal sandbox to work on
# a ticket against a public Elixir repo.
#
#     export ANTHROPIC_API_KEY=sk-ant-...
#     elixir scripts/claude_code.exs "add a docstring to consumer.ex"
#     elixir scripts/claude_code.exs --repo owner/name "make X do Y"
#
# Two cost regimes:
#
#   * **Per-hour** — `Modal.Image.get_or_create/3` is content-addressed;
#     identical layers cache-hit and return instantly. The image
#     installs the Claude Code CLI and pre-clones + compiles the
#     target repo so per-ticket boots are fast.
#
#   * **Per-ticket** — create a sandbox from the cached image,
#     `git pull` for commits since the bake, run `claude -p`,
#     stream the streamed output, terminate. The API key is passed
#     in via a freshly-created Modal Secret attached at boot —
#     never baked into the image.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule ClaudeCode do
  @default_repo "elixir-lang/gen_stage"

  # Modal sandboxes run as root (Dockerfile USER is ignored). Claude
  # Code is fine with that as long as we attach a PTY at exec time —
  # without one it tries to fall back to
  # --dangerously-skip-permissions, which itself refuses to run as
  # root. PTY support comes from `pty: true` on exec/3.

  def run(args) do
    {repo, ticket_parts} = parse_args(args)

    if ticket_parts == [] do
      raise ~s|usage: elixir scripts/claude_code.exs [--repo owner/name] "ticket text..."|
    end

    ticket = Enum.join(ticket_parts, " ")
    repo_url = "https://github.com/#{repo}"
    repo_name = repo |> String.split("/") |> List.last()
    workdir = "/root/work/#{repo_name}"

    :logger.set_application_level(:grpc, :warning)

    anthropic_key =
      System.get_env("ANTHROPIC_API_KEY") ||
        raise "set ANTHROPIC_API_KEY in your environment"

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, "modal-elixir-claude-code")

    # ── PER-HOUR: build (or reuse cached) image ──────────────────
    header("PER-HOUR: image build")
    per_hour_t0 = now()
    t0 = per_hour_t0

    {:ok, image_id, image_status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM hexpm/elixir:1.19.5-erlang-28.5-debian-bookworm-20260421-slim",
          "RUN apt-get update && apt-get install -y --no-install-recommends " <>
            "git curl ca-certificates build-essential && rm -rf /var/lib/apt/lists/*",
          "WORKDIR /root",
          "RUN mix local.hex --force && mix local.rebar --force",
          # Official Claude Code installer. Download first so a failed
          # curl actually fails the layer; `curl | bash` would mask it.
          # Retry on 429 from claude.ai.
          ~S{RUN bash -c 'set -eo pipefail; for i in 1 2 3 4 5; do } <>
            ~S{curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && break || sleep 10; } <>
            ~S{done; bash /tmp/install.sh'},
          "ENV PATH=/root/.local/bin:$PATH",
          # Smoke-test so a broken install fails the build, not the first ticket.
          "RUN claude --version",
          # Pre-clone + warm the build cache. Per-ticket boots only need git pull.
          "RUN mkdir -p /root/work && git clone --depth=1 #{repo_url} #{workdir} && " <>
            "cd #{workdir} && mix deps.get && mix compile"
        ],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    info("image: #{image_id} [#{image_status}] (#{elapsed(t0)})")
    per_hour_ms = ms_since(per_hour_t0)

    # ── PER-TICKET ───────────────────────────────────────────────
    per_ticket_t0 = now()

    header("PER-TICKET: secret")
    step("Creating ephemeral Modal Secret from local env")
    t0 = now()

    {:ok, secret_id} =
      Modal.Secret.create(client,
        app: app,
        name: "claude-code-env-#{System.os_time(:second)}",
        env: %{"ANTHROPIC_API_KEY" => anthropic_key}
      )

    info("secret: #{secret_id} (#{elapsed(t0)})")

    header("PER-TICKET: sandbox")

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        workdir: "/root",
        secret_ids: [secret_id],
        timeout_secs: 1_800,
        idle_timeout_secs: 60,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("git pull (catch up since image bake)")
    run!(sandbox, "cd #{workdir} && git pull --ff-only")

    step("Sanity-check Claude can see the API key")
    run!(sandbox, "test -n \"$ANTHROPIC_API_KEY\" && echo 'key present' || (echo 'MISSING' && exit 1)")

    step("Running Claude Code on the ticket — STREAMING")
    info("repo:   #{repo}")
    info("ticket: #{ticket}")

    # PTY: Claude Code refuses to run without a terminal (and refuses
    # --dangerously-skip-permissions as root, which we are). PTY mode
    # also means the stream is full of ANSI; strip in the writer.
    stream_with_pty!(
      sandbox,
      "cd #{workdir} && claude -p #{shell_escape(ticket)} --permission-mode acceptEdits 2>&1"
    )

    step("Diff Claude produced")
    run!(sandbox, "cd #{workdir} && git --no-pager diff --stat && echo '---' && git --no-pager diff")

    Modal.Sandbox.terminate(sandbox)
    per_ticket_ms = ms_since(per_ticket_t0)

    IO.puts(:stderr, """

    \e[1m=== SUMMARY ===\e[0m
      per-hour  (image build, cached)  : #{fmt_ms(per_hour_ms)}   #{if image_status == :cached, do: "(cache hit)", else: "(fresh build)"}
      per-ticket (secret + sandbox + claude): #{fmt_ms(per_ticket_ms)}
      total                            : #{fmt_ms(per_hour_ms + per_ticket_ms)}

    \e[32mDone.\e[0m
    """)
  end

  # ── exec helpers ─────────────────────────────────────────────────

  defp run!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")
    result = Modal.Sandbox.exec_streaming!(sandbox, ["bash", "-c", cmd])

    if String.trim(result.stdout) != "" do
      result.stdout |> String.trim() |> String.split("\n") |> Enum.each(&info("  #{&1}"))
    end

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp stream_with_pty!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    # PTY output is ANSI-laden; strip CSI/OSC sequences chunk-by-chunk
    # so the log stays readable when piped to a file.
    on_chunk = fn chunk -> IO.write("  " <> strip_ansi(chunk)) end

    code =
      case Modal.Sandbox.exec_streaming(sandbox, ["bash", "-c", cmd],
             on_stdout: on_chunk,
             exec_opts: [pty: true],
             timeout: :infinity
           ) do
        {:ok, %{code: c}} ->
          c || 0

        {:error, err} ->
          info("\e[31mexec_streaming failed: #{Exception.message(err)}\e[0m")
          1
      end

    color = if code == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{code}\e[0m (#{elapsed(t0)})")
  end

  # ── arg parsing ─────────────────────────────────────────────────

  defp parse_args(args), do: parse_args(args, @default_repo, [])

  defp parse_args(["--repo", repo | rest], _default, acc), do: parse_args(rest, repo, acc)
  defp parse_args([arg | rest], repo, acc), do: parse_args(rest, repo, [arg | acc])
  defp parse_args([], repo, acc), do: {repo, Enum.reverse(acc)}

  defp shell_escape(s), do: "'" <> String.replace(s, "'", ~S('"'"')) <> "'"

  # Strip ANSI/CSI/OSC escape sequences emitted under PTY so the log
  # reads cleanly. CSI param-byte range is 0x30-0x3F (digits +
  # `:;<=>?`), wider than `[0-9;?]` — xterm private-mode escapes
  # otherwise leak through.
  defp strip_ansi(s) do
    s
    |> String.replace(~r/\e\[[0-9;:<>=?]*[ -\/]*[@-~]/, "")
    |> String.replace(~r/\e\][^\a]*(?:\a|\e\\)/, "")
    |> String.replace(~r/\e[PX^_].*?\e\\/, "")
    |> String.replace(~r/\e[@-Z\\-_]/, "")
  end

  defp ms_since(t0), do: System.monotonic_time(:millisecond) - t0
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"

  defp header(msg), do: IO.puts(:stderr, "\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: IO.puts(:stderr, "\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: IO.puts(:stderr, "  #{msg}")

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

ClaudeCode.run(System.argv())
