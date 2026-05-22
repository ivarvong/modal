defmodule Mix.Tasks.Modal.Eval do
  @moduledoc """
  Two-phase eval: clone a GitHub repo and run its Elixir test suite in a Modal sandbox.

  ## Usage

      export MODAL_TOKEN_ID=...
      export MODAL_TOKEN_SECRET=...

      mix modal.eval prepare ivarvong/pyex   # Build (and cache) the sandbox image.
      mix modal.eval run     ivarvong/pyex   # Run the tests. Fast — image is cached.

      mix modal.eval prepare ivarvong/exgit
      mix modal.eval run     ivarvong/exgit

  ## Phases

    * **prepare** — Calls `Modal.Image.get_or_create/3` with a layer stack that
      clones the repo, installs deps, and compiles in `MIX_ENV=test`. Layers are
      content-addressed: re-running without changing them is a near-instant cache hit.

    * **run** — Calls `get_or_create` (cache hit, ~100ms), boots a sandbox from
      that image, does a `git pull` to pick up commits since the image was baked,
      then streams `mix test`. Only files that changed since the last prepare need
      recompilation.
  """
  @shortdoc "Two-phase eval: prepare builds the image, run executes the tests"
  use Mix.Task

  import Modal.MixHelpers

  @base_image "hexpm/elixir:1.19.5-erlang-28.5-debian-bookworm-20260421-slim"

  @impl true
  def run(args) do
    case args do
      ["prepare", repo | _] -> do_prepare(repo)
      ["run", repo | _] -> do_run(repo)
      _ -> Mix.raise("usage: mix modal.eval [prepare | run] owner/repo")
    end
  end

  # ── Shared ───────────────────────────────────────────────────────────

  defp parse_repo(repo) do
    case String.split(repo, "/") do
      [owner, name] -> {owner, name, "https://github.com/#{owner}/#{name}", "/work/#{name}"}
      _ -> Mix.raise("repo must be owner/repo, got: #{inspect(repo)}")
    end
  end

  defp app_name(repo_name), do: "elixir-eval-#{repo_name}"

  defp image_layers(repo_url, workdir) do
    [
      "FROM #{@base_image}",
      "RUN apt-get update && apt-get install -y --no-install-recommends " <>
        "git build-essential curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      # uv installs a pre-built CPython 3.14 binary in seconds; symlink it as python3.
      "RUN curl -LsSf https://astral.sh/uv/install.sh | sh && " <>
        "/root/.local/bin/uv python install 3.14 && " <>
        "ln -sf $(/root/.local/bin/uv python find 3.14) /usr/local/bin/python3",
      "RUN mix local.hex --force && mix local.rebar --force",
      "RUN git clone #{repo_url} #{workdir}",
      "RUN cd #{workdir} && mix deps.get",
      "RUN cd #{workdir} && MIX_ENV=test mix compile"
    ]
  end

  defp connect!(token_id, token_secret) do
    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    client
  end

  defp build_image(client, app_id, repo_url, workdir) do
    step("Building image (or fetching from cache)")
    t0 = now()
    {:ok, image_id, status} = Modal.Image.get_or_create(client, image_layers(repo_url, workdir), app_id: app_id)
    info("image: #{image_id} [#{status}] (#{elapsed(t0)})")
    image_id
  end

  # ── Prepare ──────────────────────────────────────────────────────────

  defp do_prepare(repo) do
    {_owner, repo_name, repo_url, workdir} = parse_repo(repo)

    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {token_id, token_secret} = credentials!()

    header("PREPARE: #{repo}")

    client = connect!(token_id, token_secret)
    {:ok, app_id} = Modal.App.lookup(client, app_name(repo_name))
    _image_id = build_image(client, app_id, repo_url, workdir)

    Mix.shell().info("\n\e[32mPrepare done. Run `mix modal.eval run #{repo}` to execute the tests.\e[0m\n")
  end

  # ── Run ──────────────────────────────────────────────────────────────

  defp do_run(repo) do
    {_owner, repo_name, repo_url, workdir} = parse_repo(repo)

    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {token_id, token_secret} = credentials!()

    header("RUN: #{repo}")

    client = connect!(token_id, token_secret)
    {:ok, app_id} = Modal.App.lookup(client, app_name(repo_name))
    image_id = build_image(client, app_id, repo_url, workdir)

    step("Creating sandbox")
    t0 = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout: 1800,
        idle_timeout: 300
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    info("sandbox: #{sandbox.id} (boot: #{elapsed(t0)})")

    step("git pull (catch up since image bake)")
    stream!(sandbox, "cd #{workdir} && git pull --ff-only 2>&1")

    step("Running tests")
    exit_code = stream!(sandbox, "cd #{workdir} && mix test 2>&1")

    Modal.Sandbox.terminate(sandbox)

    if exit_code == 0 do
      Mix.shell().info("\n\e[32mAll tests passed.\e[0m\n")
    else
      Mix.shell().info("\n\e[31mTests failed (exit #{exit_code}).\e[0m\n")
      System.halt(exit_code)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp stream!(%Modal.Sandbox{} = sandbox, cmd) do
    t0 = now()
    info("$ #{cmd}")

    # Write the exit code to a sentinel file so we can recover it via a fresh
    # exec if the worker JWT expires before the exit-code poll returns.
    # `exit $CODE` preserves the real exit code as the process's own exit code.
    sentinel = "/tmp/.eval_exit_#{:erlang.unique_integer([:positive])}"
    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", "#{cmd}; CODE=$?; echo $CODE > #{sentinel}; exit $CODE"], timeout_secs: 1800)

    exit_task =
      Task.async(fn ->
        case Modal.ContainerProcess.exit_code(proc) do
          {:ok, code} -> {:ok, code}
          {:error, reason} -> {:error, reason}
        end
      end)

    proc |> Modal.ContainerProcess.stream() |> Enum.each(&IO.write("  " <> &1))

    code =
      case Task.await(exit_task, :infinity) do
        {:ok, code} ->
          code

        {:error, _} ->
          # JWT expired before we got the exit code — read sentinel via a fresh exec.
          fresh = Modal.Sandbox.exec!(sandbox, ["bash", "-c", "cat #{sentinel}"])
          {:ok, %{stdout: s}} = Modal.ContainerProcess.await(fresh)
          Modal.ContainerProcess.close(fresh)
          s |> String.trim() |> String.to_integer()
      end

    Modal.ContainerProcess.close(proc)

    color = if (code || 0) == 0, do: "\e[32m", else: "\e[31m"
    info("#{color}exit: #{code || 0}\e[0m (#{elapsed(t0)})")
    code || 0
  end

  defp header(msg), do: Mix.shell().info("\n\e[1m=== #{msg} ===\e[0m")
  defp step(msg), do: Mix.shell().info("\n\e[36m> #{msg}\e[0m")
  defp info(msg), do: Mix.shell().info("  #{msg}")
end
