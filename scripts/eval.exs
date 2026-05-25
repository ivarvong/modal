# Two-phase eval: clone a GitHub repo and run its Elixir test suite
# in a Modal sandbox.
#
#     elixir scripts/eval.exs prepare elixir-lang/gen_stage   # build (or cache) the image
#     elixir scripts/eval.exs run     elixir-lang/gen_stage   # boot from cache, git pull, mix test
#
# Works with any public owner/repo whose default branch is an Elixir
# project. The image clones, runs mix deps.get + MIX_ENV=test mix
# compile once at prepare time; subsequent runs boot from cache.
#
# Phases:
#
#   * `prepare` — calls Image.get_or_create with a layer stack that
#     clones the repo, installs deps, and compiles in MIX_ENV=test.
#     Layers are content-addressed; re-running without changes is a
#     near-instant cache hit.
#
#   * `run` — get_or_create (cache hit, ~100ms), boot a sandbox,
#     git pull to catch up since the bake, stream `mix test`. Only
#     files that changed since the last prepare recompile.
#
# Real shape for any CI runner or PR-bot pattern that benefits from
# a baked baseline image.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule Eval do
  @base_image "hexpm/elixir:1.19.5-erlang-28.5-debian-bookworm-20260421-slim"

  def run(args) do
    :logger.set_application_level(:grpc, :warning)

    case args do
      ["prepare", repo | _] -> do_prepare(repo)
      ["run", repo | _] -> do_run(repo)
      _ -> raise "usage: elixir scripts/eval.exs [prepare | run] owner/repo"
    end
  end

  # ── Shared ───────────────────────────────────────────────────────

  defp parse_repo(repo) do
    case String.split(repo, "/") do
      [owner, name] -> {owner, name, "https://github.com/#{owner}/#{name}", "/work/#{name}"}
      _ -> raise "repo must be owner/repo, got: #{inspect(repo)}"
    end
  end

  defp app_name(repo_name), do: "modal-elixir-eval-#{repo_name}"

  defp image_layers(repo_url, workdir) do
    [
      "FROM #{@base_image}",
      "RUN apt-get update && apt-get install -y --no-install-recommends " <>
        "git build-essential curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      # uv installs a pre-built CPython in seconds; alias as python3.
      "RUN curl -LsSf https://astral.sh/uv/install.sh | sh && " <>
        "/root/.local/bin/uv python install 3.14 && " <>
        "ln -sf $(/root/.local/bin/uv python find 3.14) /usr/local/bin/python3",
      "RUN mix local.hex --force && mix local.rebar --force",
      "RUN git clone #{repo_url} #{workdir}",
      "RUN cd #{workdir} && mix deps.get",
      "RUN cd #{workdir} && MIX_ENV=test mix compile"
    ]
  end

  defp build_image(client, app, repo_url, workdir) do
    step("Building image (or fetching from cache)")
    t0 = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(client, image_layers(repo_url, workdir),
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    info("image: #{image_id} [#{status}] (#{elapsed(t0)})")
    image_id
  end

  # ── prepare ──────────────────────────────────────────────────────

  defp do_prepare(repo) do
    {_owner, repo_name, repo_url, workdir} = parse_repo(repo)
    header("PREPARE: #{repo}")

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, app_name(repo_name))
    _image_id = build_image(client, app, repo_url, workdir)

    IO.puts(
      :stderr,
      "\n\e[32mPrepare done. Run `elixir scripts/eval.exs run #{repo}` to execute the tests.\e[0m\n"
    )
  end

  # ── run ──────────────────────────────────────────────────────────

  defp do_run(repo) do
    {_owner, repo_name, repo_url, workdir} = parse_repo(repo)
    header("RUN: #{repo}")

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, app_name(repo_name))
    image_id = build_image(client, app, repo_url, workdir)

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 1800,
        idle_timeout_secs: 300,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("git pull (catch up since image bake)")
    stream!(sandbox, "cd #{workdir} && git pull --ff-only 2>&1")

    # Always refetch deps. The image baked them once at prepare time,
    # but `git pull` may have introduced new mix.exs entries (or
    # bumped versions in mix.lock) since. Hex caches per-package so
    # the no-op case is fast — a few seconds, dominated by `mix
    # local.hex` checks that are already done in the image.
    step("mix deps.get (catch up with any new deps)")
    stream!(sandbox, "cd #{workdir} && mix deps.get 2>&1")

    step("Running tests")
    exit_code = stream!(sandbox, "cd #{workdir} && mix test 2>&1")

    Modal.Sandbox.terminate(sandbox)

    if exit_code == 0 do
      IO.puts(:stderr, "\n\e[32mAll tests passed.\e[0m\n")
    else
      IO.puts(:stderr, "\n\e[31mTests failed (exit #{exit_code}).\e[0m\n")
      System.halt(exit_code)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp stream!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    on_line = Modal.ContainerProcess.line_buffered(fn line -> IO.puts("  " <> line) end)

    result =
      Modal.Sandbox.exec_streaming(sandbox, ["bash", "-c", cmd],
        on_stdout: on_line,
        timeout: :infinity
      )

    code =
      case result do
        {:ok, %{code: c}} -> c || 0
        {:error, _} -> 1
      end

    color = if code == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{code}\e[0m (#{elapsed(t0)})")
    code
  end

  defp header(msg), do: IO.puts(:stderr, "\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: IO.puts(:stderr, "\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: IO.puts(:stderr, "  #{msg}")

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

Eval.run(System.argv())
