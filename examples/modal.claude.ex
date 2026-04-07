defmodule Mix.Tasks.Modal.Claude do
  @moduledoc """
  Run Claude Code headless inside a Modal sandbox to work on a ticket
  against `elixir-ai-tools/just_bash`.

  ## Usage

      export MODAL_TOKEN_ID=...
      export MODAL_TOKEN_SECRET=...
      export ANTHROPIC_API_KEY=sk-ant-...

      mix modal.claude "fix the typo in the README"

  ## What's per-hour vs per-ticket

    * **Per-hour (cached image build)** — `Modal.Image.get_or_create/3` is
      content-addressed; identical layers hit the cache and return instantly.
      The image installs git, the Claude Code CLI, an unprivileged `claude`
      user, and pre-clones + compiles `just_bash` so per-ticket boots are fast.
      Re-run periodically (e.g. hourly cron) to pick up upstream changes —
      same code path, just a fresh hash.

    * **Per-ticket (on-demand)** — create a sandbox from the cached image,
      `git pull` for any commits since the image was baked, run `claude -p`
      with the ticket text, stream output, terminate. Secrets are passed in
      lazily from the caller's environment via a freshly-created Modal
      Secret attached at sandbox-creation time — never baked into the image.
  """
  @shortdoc "Run Claude Code on a ticket inside a Modal sandbox"
  use Mix.Task

  import Modal.MixHelpers

  alias Modal.RPC

  @repo_url "https://github.com/elixir-ai-tools/just_bash"
  # NOTE: Modal sandboxes always run as root (Dockerfile `USER` is ignored).
  # Claude Code is fine with that as long as we attach a PTY at exec time —
  # without one it tries to fall back to `--dangerously-skip-permissions`,
  # which itself refuses to run as root. PTY support comes from `pty: true`
  # on `Modal.Sandbox.exec/3`.
  @workdir "/root/work/just_bash"

  @impl true
  def run(args) do
    ticket =
      case args do
        [] -> Mix.raise(~s|usage: mix modal.claude "ticket text..."|)
        parts -> Enum.join(parts, " ")
      end

    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)

    {token_id, token_secret} = credentials!()

    anthropic_key =
      System.get_env("ANTHROPIC_API_KEY") ||
        Mix.raise("Set ANTHROPIC_API_KEY in your environment")

    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    {:ok, app_id} = Modal.App.lookup(client, "elixir-claude-code")

    # ─────────────────────────────────────────────────────────────────
    # === PER-HOUR === Build (or reuse cached) image.
    #
    # These layers are content-addressed by Modal. Re-running this task
    # without changing the layer list is a near-instant cache hit. The
    # only thing that changes hourly in practice is whatever the install
    # script and `git clone` pull down — bump a comment to force a rebuild
    # if you want to refresh, or wire this section into a cron.
    # ─────────────────────────────────────────────────────────────────
    header("PER-HOUR: image build")
    per_hour_t0 = now()
    t0 = per_hour_t0

    {:ok, image_id, image_status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM hexpm/elixir:1.19.4-erlang-26.2.5.3-debian-bullseye-20260316-slim",
          # System deps.
          "RUN apt-get update && apt-get install -y --no-install-recommends " <>
            "git curl ca-certificates build-essential && rm -rf /var/lib/apt/lists/*",
          "WORKDIR /root",
          "RUN mix local.hex --force && mix local.rebar --force",
          # Official Claude Code installer. Download to a file first so a failed
          # curl actually fails the layer (sh has no pipefail; `curl | bash`
          # masks curl's exit code). Retry on 429 from claude.ai.
          ~S{RUN bash -c 'set -eo pipefail; for i in 1 2 3 4 5; do } <>
            ~S{curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && break || sleep 10; } <>
            ~S{done; bash /tmp/install.sh'},
          "ENV PATH=/root/.local/bin:$PATH",
          # Smoke-test so a broken install fails the build, not the first ticket.
          "RUN claude --version",
          # Pre-clone + warm the build cache. Per-ticket boots only need `git pull`.
          "RUN mkdir -p /root/work && git clone --depth=1 #{@repo_url} #{@workdir} && " <>
            "cd #{@workdir} && mix deps.get && mix compile"
        ],
        app_id: app_id
      )

    info("image: #{image_id} [#{image_status}] (#{elapsed(t0)})")
    per_hour_ms = ms_since(per_hour_t0)

    # ─────────────────────────────────────────────────────────────────
    # === PER-TICKET === Everything below runs once per ticket.
    # ─────────────────────────────────────────────────────────────────
    per_ticket_t0 = now()
    header("PER-TICKET: secret")

    # The only way Modal accepts env vars at sandbox-start is via Secret
    # objects attached by id. We create one on the fly from the caller's
    # shell — no dashboard step, no id to manage. Overwrite-if-exists so
    # subsequent runs pick up rotated keys.
    step("Creating ephemeral Modal Secret from local env")
    t0 = now()
    {:ok, secret_id} = create_secret_from_env(client, app_id, %{
      "ANTHROPIC_API_KEY" => anthropic_key
    })
    info("secret: #{secret_id} (#{elapsed(t0)})")

    header("PER-TICKET: sandbox")

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        workdir: "/root",
        secret_ids: [secret_id],
        timeout: 1_800,
        idle_timeout: 60
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("git pull (catch up since image bake)")
    run!(sandbox, "cd #{@workdir} && git pull --ff-only")

    step("Sanity-check Claude can see the API key")
    run!(sandbox, "test -n \"$ANTHROPIC_API_KEY\" && echo 'key present' || (echo 'MISSING' && exit 1)")

    step("Running Claude Code on the ticket -- STREAMING")
    info("ticket: #{ticket}")

    # PTY is required: Claude Code refuses to run without a terminal
    # (and refuses `--dangerously-skip-permissions` as root, which we are).
    # `--permission-mode acceptEdits` lets it apply file edits unattended
    # without the root-blocked dangerous-skip flag.
    stream!(
      sandbox,
      "cd #{@workdir} && claude -p #{shell_escape(ticket)} " <>
        "--permission-mode acceptEdits 2>&1",
      pty: true
    )

    step("Diff Claude produced")
    run!(sandbox, "cd #{@workdir} && git --no-pager diff --stat && echo '---' && git --no-pager diff")

    Modal.Sandbox.terminate(sandbox)

    per_ticket_ms = ms_since(per_ticket_t0)

    Mix.shell().info("""

    \e[1m=== SUMMARY ===\e[0m
      per-hour  (image build, cached)  : #{fmt_ms(per_hour_ms)}   #{if image_status == :cached, do: "(cache hit)", else: "(fresh build)"}
      per-ticket (secret + sandbox + claude): #{fmt_ms(per_ticket_ms)}
      total                            : #{fmt_ms(per_hour_ms + per_ticket_ms)}

    \e[32mDone.\e[0m
    """)
  end

  defp ms_since(t0), do: System.monotonic_time(:millisecond) - t0
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"

  # ── Secret helper ───────────────────────────────────────────────────

  defp create_secret_from_env(client, app_id, env_map) do
    request = %Modal.Client.SecretGetOrCreateRequest{
      deployment_name: "claude-code-env-#{System.os_time(:second)}",
      app_id: app_id,
      env_dict: env_map,
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_OVERWRITE_IF_EXISTS
    }

    case RPC.call(client, :SecretGetOrCreate, request) do
      {:ok, %{secret_id: id}} -> {:ok, id}
      {:error, reason} -> Mix.raise("SecretGetOrCreate failed: #{inspect(reason)}")
    end
  end

  defp shell_escape(s), do: "'" <> String.replace(s, "'", ~S('"'"')) <> "'"

  # Strip ANSI/CSI/OSC escape sequences emitted under a PTY so Claude Code's
  # streamed output is readable in a plain terminal log.
  defp strip_ansi(s) do
    s
    # CSI sequences: ESC [ ... letter
    |> String.replace(~r/\e\[[0-9;?]*[ -\/]*[@-~]/, "")
    # OSC sequences: ESC ] ... BEL or ESC \
    |> String.replace(~r/\e\][^\a]*(?:\a|\e\\)/, "")
    # Other ESC + single byte
    |> String.replace(~r/\e[PX^_].*?\e\\/, "")
    |> String.replace(~r/\e[@-Z\\-_]/, "")
  end

  # ── exec helpers (copied from modal.demo.ex for self-containment) ───

  defp run!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", cmd])
    {:ok, result} = Modal.ContainerProcess.await(proc)
    Modal.ContainerProcess.close(proc)

    if String.trim(result.stdout || "") != "" do
      result.stdout |> String.trim() |> String.split("\n") |> Enum.each(&info("  #{&1}"))
    end

    color = if (result.code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{result.code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp stream!(%Modal.Sandbox{} = sandbox, cmd, opts) do
    t0 = now()
    info("$ #{cmd}")

    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", cmd], opts)

    exit_task =
      Task.async(fn ->
        {:ok, code} = Modal.ContainerProcess.exit_code(proc)
        code
      end)

    proc
    |> Modal.ContainerProcess.stream()
    |> Enum.each(fn chunk -> IO.write("  " <> strip_ansi(chunk)) end)

    code = Task.await(exit_task, :infinity)
    Modal.ContainerProcess.close(proc)

    color = if (code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{code || 0}\e[0m (#{elapsed(t0)})")
  end

  defp header(msg), do: Mix.shell().info("\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: Mix.shell().info("\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: Mix.shell().info("  #{msg}")
end
