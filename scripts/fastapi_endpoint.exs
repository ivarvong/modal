# Boot a FastAPI app inside a Modal sandbox and call it from Elixir.
#
# Demonstrates the "Elixir orchestrator, Python service" shape — write
# a small FastAPI app to the sandbox, start uvicorn as a background
# exec, ask Modal for the public tunnel URL of the bound port, then
# POST to it like any other HTTPS service. Terminate the sandbox when
# you're done; uvicorn dies with it.
#
# This is the production shape for a lot of ML / data services:
# Elixir handles the request lifecycle, multitenancy, and supervision;
# Python handles the heavy compute, model loading, or library access
# Elixir doesn't have. Modal makes the "spin up a Python HTTPS
# endpoint" step a one-RPC affair.
#
# Run:
#
#     elixir scripts/fastapi_endpoint.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule FastAPIEndpoint do
  @app_name "modal-elixir-fastapi-endpoint"
  @container_port 8000

  # The FastAPI app we write to the sandbox. POST /sum sums a list,
  # GET / is a health check. Deliberately tiny — the demo is about
  # the orchestration, not the API design.
  @fastapi_app """
  from fastapi import FastAPI
  from pydantic import BaseModel

  app = FastAPI()


  class SumRequest(BaseModel):
      numbers: list[int]


  @app.get("/")
  def health():
      return {"status": "ok", "service": "elixir-orchestrated-fastapi"}


  @app.post("/sum")
  def sum_endpoint(req: SumRequest):
      return {"sum": sum(req.numbers), "count": len(req.numbers)}
  """

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    # ── PHASE 1: image with FastAPI + uvicorn ──────────────────
    log("\n── PHASE 1: image ─────────────")
    t = now()

    {:ok, image_id, status} =
      Modal.Image.get_or_create(
        client,
        [
          "FROM python:3.14-slim",
          "RUN pip install --no-cache-dir 'fastapi[standard]==0.115.6' uvicorn"
        ],
        app: app,
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image_id} [#{status}] (#{elapsed(t)})")

    # ── PHASE 2: sandbox with port 8000 exposed ────────────────
    log("\n── PHASE 2: sandbox with port #{@container_port} tunneled ─────────────")
    t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 300,
        # Tells Modal to expose this container port via an HTTPS
        # tunnel. The tunnel URL comes back from
        # `Modal.Sandbox.tunnels/1` once the sandbox is up.
        ports: [@container_port],
        # If this script is killed mid-flight, the watchdog fires
        # SandboxTerminate so uvicorn dies cleanly Modal-side.
        terminate_on_caller_exit: :silent
      )

    log("sandbox: #{sandbox.id} (#{elapsed(t)})")

    try do
      session(client, sandbox)
    after
      :ok = Modal.Sandbox.terminate(sandbox)
      log("\nsandbox terminated (uvicorn killed with it)")

      log("\n── telemetry ─────────────")
      print_telemetry()
    end
  end

  defp session(_client, sandbox) do
    # ── PHASE 3: write the FastAPI app + start uvicorn ─────────
    log("\n── PHASE 3: write app.py + start uvicorn (background exec) ─────────────")
    t = now()

    :ok = Modal.Filesystem.mkdir(sandbox, "/work", parents: true)
    :ok = Modal.Filesystem.write_file(sandbox, "/work/app.py", @fastapi_app)
    log("wrote /work/app.py (#{byte_size(@fastapi_app)} bytes)")

    # Background exec: kick uvicorn off without awaiting. The
    # ContainerProcess stays open for the lifetime of the server;
    # we just keep the handle around so close-on-terminate fires.
    {:ok, uvicorn_proc} =
      Modal.Sandbox.exec(
        sandbox,
        [
          "uvicorn",
          "app:app",
          "--host",
          "0.0.0.0",
          "--port",
          to_string(@container_port),
          "--log-level",
          "warning"
        ],
        workdir: "/work"
      )

    log("uvicorn started (proc #{uvicorn_proc.exec_id}) — backgrounded")

    # ── PHASE 4: discover tunnel + wait for uvicorn ready ─────
    log("\n── PHASE 4: discover tunnel URL ─────────────")
    {:ok, tunnels} = Modal.Sandbox.tunnels(sandbox)

    # `tunnels` is now a `%{container_port => %Modal.Tunnel{}}` map
    # (since the Python-parity refactor) — same shape as the Python
    # SDK's `Sandbox.tunnels()` after v0.64.153.
    tunnel = tunnels[@container_port] || raise "no tunnel for container_port #{@container_port}"

    base_url = Modal.Tunnel.url(tunnel)
    log("tunnel:  #{base_url} → container :#{tunnel.container_port}")

    log("\n── PHASE 5: wait for uvicorn to bind ─────────────")
    t = now()
    wait_for_ready!(base_url, 30_000)
    log("ready in #{elapsed(t)}")

    # ── PHASE 6: real HTTP calls from Elixir ──────────────────
    log("\n── PHASE 6: hit the endpoint from Elixir ─────────────")

    # GET / health check. Req handles JSON encode/decode + connection
    # pooling automatically; the response body comes back as a map.
    t = now()
    %Req.Response{status: 200, body: body} = Req.get!(base_url <> "/")
    log("GET  /     → 200 in #{elapsed(t)} — #{inspect(body)}")
    assert!(body["status"] == "ok", "unexpected health response: #{inspect(body)}")

    # POST /sum with a payload that uses Pydantic validation. Req's
    # `json:` option encodes the body and sets the right Content-Type.
    t = now()
    %Req.Response{status: 200, body: body} =
      Req.post!(base_url <> "/sum", json: %{"numbers" => Enum.to_list(1..100)})

    log("POST /sum  → 200 in #{elapsed(t)} — #{inspect(body)}")

    expected = Enum.sum(1..100)
    assert!(body["sum"] == expected, "expected sum=#{expected}, got #{inspect(body)}")
    assert!(body["count"] == 100, "expected count=100, got #{inspect(body)}")

    # POST /sum with a bad payload — Pydantic should 422 back at us.
    t = now()
    %Req.Response{status: 422, body: body} =
      Req.post!(base_url <> "/sum", json: %{"numbers" => "nope"})

    log("POST /sum (bad payload) → 422 in #{elapsed(t)} — Pydantic validation")
    assert!(is_list(body["detail"]), "expected Pydantic detail array, got #{inspect(body)}")

    log("\n  ✓ FastAPI inside a Modal sandbox, called over HTTPS from Elixir")
  end

  # ── HTTP via Req ─────────────────────────────────────────────────
  #
  # Req is a hard dep of the library now (used by Modal.Volume.put_file
  # for content-addressed blob uploads), so demo scripts may as well
  # use it directly — much less ceremony than the prior :httpc path.

  defp wait_for_ready!(url, deadline_ms) do
    started = now()

    Stream.repeatedly(fn -> Req.get(url <> "/", retry: false) end)
    |> Enum.reduce_while(nil, fn result, _ ->
      cond do
        now() - started > deadline_ms ->
          raise "uvicorn never became ready at #{url} within #{deadline_ms}ms"

        match?({:ok, %Req.Response{status: 200}}, result) ->
          {:halt, :ok}

        true ->
          Process.sleep(200)
          {:cont, nil}
      end
    end)
  end

  defp assert!(true, _msg), do: :ok
  defp assert!(false, msg), do: raise("assertion failed: #{msg}")

  # ── Telemetry ────────────────────────────────────────────────────

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach_many(
      "fastapi-endpoint-telemetry",
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

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
  defp log(msg), do: IO.puts(:stderr, msg)
end

FastAPIEndpoint.run()
