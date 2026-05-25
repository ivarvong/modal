defmodule Modal.Contract.NetworkAccessTest do
  @moduledoc """
  Validates Modal's `NetworkAccess` egress controls end-to-end.

  Asserted behaviors (each via a sandbox exec'ing curl):

    - `network_access: :open` — outbound to the public internet
      works (curl GitHub succeeds, non-zero bytes).
    - `network_access: :blocked` — outbound is denied (curl exits
      non-zero, no body).
    - `network_access: {:allowlist, github_cidrs}` — curl to GitHub
      succeeds; curl to Anthropic's API (not in the allowlist)
      fails. Confirms ALLOWLIST is enforced, not just declared.

  Also validates `Modal.Sandbox.github_cidrs!/1` against the real
  GitHub meta endpoint.
  """
  use ExUnit.Case, async: false
  alias Modal.Contract.Support
  @moduletag :contract
  @moduletag timeout: 180_000

  setup_all do
    client = Support.client!()
    {:ok, app} = Modal.App.lookup(client, Support.app_name())

    # An image with curl. Reused via Modal's image cache.
    {:ok, image_id, _} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM debian:bookworm-slim",
          "RUN apt-get update && apt-get install -y curl ca-certificates && rm -rf /var/lib/apt/lists/*"
        ],
        app: app
      )

    %{client: client, app: app, image_id: image_id}
  end

  defp curl_in_sandbox(client, app, image_id, url, sandbox_opts) do
    sandbox =
      Modal.Sandbox.create!(
        client,
        Keyword.merge(
          [
            app: app,
            image_id: image_id,
            cmd: ["sleep", "60"],
            timeout_secs: 120,
            idle_timeout_secs: 30
          ],
          sandbox_opts
        )
      )

    try do
      proc =
        Modal.Sandbox.exec!(sandbox, [
          "curl",
          "-s",
          "-o",
          "/dev/null",
          "-w",
          "%{http_code}",
          "--max-time",
          "10",
          url
        ])

      # Use non-bang await/2 — `:blocked` egress causes curl to
      # exit non-zero, and `await!/2` would raise on that.
      result =
        case Modal.ContainerProcess.await(proc, timeout: 30_000) do
          {:ok, r} ->
            r

          {:error, %Modal.Error{kind: :exec_failed, metadata: meta}} ->
            %{code: meta[:code] || 1, stdout: meta[:stdout] || "", stderr: meta[:stderr] || ""}
        end

      Modal.ContainerProcess.close(proc)
      {result.code, String.trim(result.stdout)}
    after
      Modal.Sandbox.terminate(sandbox)
    end
  end

  test "network_access: :open allows outbound to GitHub", %{
    client: client,
    app: app,
    image_id: image_id
  } do
    {exit_code, http_code} =
      curl_in_sandbox(client, app, image_id, "https://api.github.com/zen", network_access: :open)

    assert exit_code == 0, "curl should succeed under :open egress"
    assert http_code == "200", "expected HTTP 200, got #{inspect(http_code)}"
  end

  test "network_access: :blocked denies outbound (curl exits non-zero)", %{
    client: client,
    app: app,
    image_id: image_id
  } do
    {exit_code, _http_code} =
      curl_in_sandbox(client, app, image_id, "https://api.github.com/zen",
        network_access: :blocked
      )

    refute exit_code == 0,
           "curl should fail under :blocked egress; got exit_code=#{exit_code}"
  end

  test "network_access: {:allowlist, github_cidrs} permits GitHub but denies Anthropic", %{
    client: client,
    app: app,
    image_id: image_id
  } do
    # Fetched live — this is the actual GitHub CIDRs list.
    gh = Modal.Sandbox.github_cidrs!()
    assert match?([_ | _], gh)
    assert Enum.all?(gh, &is_binary/1)
    assert Enum.all?(gh, &String.contains?(&1, "/"))

    {gh_exit, gh_code} =
      curl_in_sandbox(client, app, image_id, "https://api.github.com/zen",
        network_access: {:allowlist, gh}
      )

    assert gh_exit == 0, "GitHub should be allowed (in CIDR list); got exit=#{gh_exit}"
    assert gh_code == "200"

    {anth_exit, _} =
      curl_in_sandbox(client, app, image_id, "https://api.anthropic.com/v1/messages",
        network_access: {:allowlist, gh}
      )

    refute anth_exit == 0,
           "Anthropic should be blocked (not in GH CIDR list); got exit=#{anth_exit}"
  end
end
