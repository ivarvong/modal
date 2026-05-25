# A small full-stack demo of the Elixir Modal client.
#
# Generate random data in Elixir, publish it as a git repo to Cloudflare
# Artifacts, then ask a Modal sandbox to clone the repo and sum the
# column with pandas. The script verifies the remote answer against a
# locally-computed one.
#
#     elixir → exgit → Cloudflare Artifacts → Modal sandbox → pandas
#
#     elixir scripts/cloudflare_roundtrip.exs
#
# Expects:
#   MODAL_TOKEN_ID, MODAL_TOKEN_SECRET   (modal.com)
#   CF_ACCOUNT_ID,  CF_API_TOKEN         (cloudflare.com)
#
# Resource cleanup is handled by short TTLs (sandbox timeout: 300s,
# Cloudflare read token ttl: 300s) rather than try/after blocks. If the
# script crashes mid-flight, everything reaps itself in five minutes.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)},
  {:exgit, github: "ivarvong/exgit", ref: "main"}
])

defmodule Demo do
  @row_count 1_000

  def run do
    # 1. Make some data locally and compute the answer.
    rows = for i <- 1..@row_count, do: {i, :rand.uniform(10_000)}
    csv = "id,value\n" <> Enum.map_join(rows, "", fn {i, v} -> "#{i},#{v}\n" end)
    local_sum = Enum.reduce(rows, 0, fn {_, v}, acc -> acc + v end)
    log("local: #{@row_count} rows, sum=#{local_sum}")

    # 2. Provision a fresh Cloudflare Artifacts repo (git over HTTPS,
    #    short-lived auth tokens). create_repo/2 returns an inline
    #    token we can push with immediately.
    cf =
      Exgit.CloudflareArtifacts.new(
        account_id: System.fetch_env!("CF_ACCOUNT_ID"),
        api_token: System.fetch_env!("CF_API_TOKEN")
      )

    repo_name = "modal-demo-#{System.os_time(:second)}"
    {:ok, repo} = Exgit.CloudflareArtifacts.create_repo(cf, name: repo_name, default_branch: "main")
    log("repo:  #{repo.remote}")

    # 3. Push the CSV with exgit — no `git` binary, no temp dir.
    :ok = push_csv(repo.remote, repo.token, csv)
    log("push:  data.csv (#{byte_size(csv)} bytes)")

    # 4. Mint a tightly-scoped read token for the sandbox.
    {:ok, token} =
      Exgit.CloudflareArtifacts.create_token(cf, repo: repo_name, scope: :read, ttl: 300)

    # 5. Boot a Modal sandbox and ask pandas to sum the column.
    remote_sum = sum_in_sandbox(repo.remote, token.plaintext)
    log("remote: sum=#{remote_sum}")

    # 6. Cross-check.
    if remote_sum == local_sum do
      log("\n  ✓ #{local_sum} ✓  (computed twice, end-to-end)\n")
    else
      log("\n  ✗ mismatch: local=#{local_sum} remote=#{remote_sum}\n")
      System.halt(1)
    end

    # 7. Politeness cleanup on the success path. Failure paths rely on
    #    short TTLs to reap themselves.
    Exgit.CloudflareArtifacts.delete_token(cf, token.id)
    Exgit.CloudflareArtifacts.delete_repo(cf, repo_name)
  end

  # Build a one-commit git history in memory and push it. Pure Elixir,
  # no shelling out.
  defp push_csv(remote, token, csv) do
    alias Exgit.{ObjectStore, RefStore}
    alias Exgit.Object.{Blob, Tree, Commit}

    {:ok, r} = Exgit.init([])

    {:ok, blob_sha, store} = ObjectStore.put(r.object_store, Blob.new(csv))
    {:ok, tree_sha, store} = ObjectStore.put(store, Tree.new([{"100644", "data.csv", blob_sha}]))

    me = "demo <demo@modal.local> #{System.os_time(:second)} +0000"

    {:ok, commit_sha, store} =
      ObjectStore.put(
        store,
        Commit.new(tree: tree_sha, parents: [], author: me, committer: me, message: "data.csv\n")
      )

    {:ok, refs} = RefStore.write(r.ref_store, "refs/heads/main", commit_sha, [])
    r = %{r | object_store: store, ref_store: refs}

    {:ok, _} =
      Exgit.push(r, remote,
        auth: Exgit.Credentials.Artifacts.auth(token),
        refspecs: ["refs/heads/main"]
      )

    :ok
  end

  # Run a Modal sandbox: a python:3.14 image with git and pandas. Clone
  # the repo, sum the column, print the answer. Container images are
  # content-addressed and cached, so the second run boots from cache.
  defp sum_in_sandbox(remote, token) do
    {:ok, modal} = Modal.Client.start_link(Modal.Credentials.load!())

    {:ok, app} = Modal.App.lookup(modal, "modal-elixir-cloudflare-roundtrip")

    {:ok, image, status} =
      Modal.Image.get_or_create(
        modal,
        [
          "FROM python:3.14-slim",
          "RUN apt-get update && apt-get install -y --no-install-recommends git " <>
            "&& rm -rf /var/lib/apt/lists/* && pip install --no-cache-dir pandas"
        ],
        app: app
      )

    log("image: #{image} (#{status})")

    # Pass the read token via a Modal Secret — never bake credentials
    # into the image.
    secret =
      Modal.Secret.create!(modal,
        app: app,
        name: "modal-demo-#{System.os_time(:second)}",
        env: %{"REMOTE" => remote, "TOKEN" => token}
      )

    script = ~S"""
    set -euo pipefail
    git -c http.extraheader="Authorization: Bearer $TOKEN" \
        clone --depth 1 "$REMOTE" /work
    python3 -c 'import pandas as pd; print(int(pd.read_csv("/work/data.csv")["value"].sum()))'
    """

    # Modal.Sandbox.run/2 is the System.cmd/3 of Modal: create + exec +
    # await + terminate, with stderr captured separately and the sandbox
    # cleaned up on any exit path. await!/2-style — non-zero raises a
    # %Modal.Error{kind: :exec_failed} that includes stderr in its
    # message and metadata.
    %{stdout: out} =
      Modal.Sandbox.run!(modal,
        app: app,
        image_id: image,
        secret_ids: [secret],
        cmd: ["bash", "-c", script],
        timeout_secs: 300,
        await_timeout: 120_000
      )

    out |> String.trim() |> String.to_integer()
  end

  defp log(msg), do: IO.puts(:stderr, msg)
end

Demo.run()
