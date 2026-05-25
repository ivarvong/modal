# Parallel Monte Carlo π estimator across N Modal sandboxes.
#
# A deliberately stress-test-shaped dogfood of the v1.0 client surface:
#
#   * `Modal.App.lookup/3` returning a struct
#   * `Modal.Image.get_or_create/3` with `:on_log` for live build output
#   * `Modal.Sandbox.run!/2` fanned out via `Task.async_stream/3`
#   * `:timeout_secs`/`:idle_timeout_secs` (and a deliberately-omitted
#     `:idle_timeout_secs` to confirm the field is no longer sent on
#     the wire — the proto default of 0 would mean instant death)
#   * `await!/2` raising `%Modal.Error{kind: :exec_failed}` on a
#     non-zero exit, with stderr embedded in the message
#   * `[:modal, :rpc, :stop]` telemetry with `:status`/`:error_kind`,
#     aggregated across concurrent dispatches
#
# Run:
#
#     MODAL_TOKEN_ID=ak-... MODAL_TOKEN_SECRET=as-... elixir scripts/parallel_pi.exs

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule PiDemo do
  @parallelism 8
  @points_per_sandbox 2_000_000

  def run do
    setup_telemetry()
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())

    {:ok, app} = Modal.App.lookup(client, "modal-elixir-pi-demo")
    log("app:   #{inspect(app)}")

    # ── PHASE 1: image build ─────────────────────────────────────
    log("\n── PHASE 1: image build ─────────────")
    t = now()

    {:ok, image, status} =
      Modal.Image.get_or_create(
        client,
        [
          # Deliberately no numpy — keeps cold-start dominated by
          # container boot (the thing the script is measuring) rather
          # than pip install. The Pi estimator uses stdlib `random` +
          # `math` so the image stays minimal.
          "FROM python:3.14-slim"
        ],
        app: app,
        # Live build output to stderr. Line-buffered so multi-line
        # chunks don't mangle the "  | " prefix — consistent with
        # every other script. On a cache hit this fires zero times.
        on_log: Modal.Image.line_buffered(fn line -> IO.puts(:stderr, "  | " <> line) end)
      )

    log("image: #{image} [#{status}] (#{elapsed(t)})")

    # ── PHASE 2: fan out ─────────────────────────────────────────
    log("\n── PHASE 2: #{@parallelism} sandboxes in parallel ─────────────")
    log("(one of them deliberately exits non-zero to exercise :exec_failed)\n")

    t = now()

    # 1..N estimate π honestly; `:fail` runs a script that exits 17.
    inputs = Enum.concat(1..@parallelism, [:fail])

    results =
      inputs
      |> Task.async_stream(
        fn id -> {id, run_sandbox(client, app, image, id)} end,
        max_concurrency: @parallelism + 1,
        # Per-task ceiling. Includes RPC, gRPC handshake, container boot,
        # numpy import (~200ms cold), and the 2M-point compute (~1s).
        timeout: 120_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, v} -> v end)

    log("all #{length(results)} sandboxes settled in #{elapsed(t)}\n")

    # ── PHASE 3: verify ──────────────────────────────────────────
    log("── PHASE 3: results ─────────────")
    print_results(results)

    # ── PHASE 4: telemetry ───────────────────────────────────────
    log("\n── PHASE 4: telemetry counters (per-RPC) ─────────────")
    print_telemetry()
  end

  # ── Per-sandbox runner ───────────────────────────────────────────

  defp run_sandbox(client, app, image, id) do
    script = build_script(id)

    started = now()

    try do
      result =
        Modal.Sandbox.run!(client,
          app: app,
          image_id: image,
          cmd: ["bash", "-c", script],
          # Wall-clock ceiling on the sandbox itself.
          timeout_secs: 60,
          # No `:idle_timeout_secs` — confirms that omitting it doesn't
          # produce the instant-death-on-omit bug we fixed.
          await_timeout: 90_000
        )

      ms = now() - started
      log("  ✓ #{label(id)}: #{String.trim(result.stdout)} (#{ms}ms)")
      {:ok, parse_pi(result.stdout), ms}
    rescue
      e in Modal.Error ->
        ms = now() - started
        log("  ✗ #{label(id)}: #{e.kind} (#{ms}ms)")
        {:error, e, ms}
    end
  end

  defp label(:fail), do: "fail "
  defp label(n), do: "sb-#{String.pad_leading(to_string(n), 2, " ")}"

  defp build_script(:fail) do
    """
    set -eo pipefail
    echo "I am the deliberately-failing sandbox."
    echo "Simulating: division by zero in upstream service" >&2
    echo "Stack trace would go here on stderr" >&2
    exit 17
    """
  end

  defp build_script(_n) do
    # Pure-Python Monte Carlo, no numpy import — keeps the cold-start
    # cost dominated by container boot (the thing we want to measure
    # under concurrency) rather than numpy's ~200ms first-import tax.
    py = """
    import random
    n = #{@points_per_sandbox}
    hits = 0
    for _ in range(n):
        x = random.random()
        y = random.random()
        if x * x + y * y <= 1.0:
            hits += 1
    print(4.0 * hits / n)
    """

    "python3 -c " <> shell_quote(py)
  end

  defp parse_pi(stdout) do
    case Float.parse(String.trim(stdout)) do
      {f, _} -> f
      :error -> :nan
    end
  end

  defp shell_quote(s),
    do: "'" <> String.replace(s, "'", "'\"'\"'") <> "'"

  # ── Result printer ───────────────────────────────────────────────

  defp print_results(results) do
    {oks, errs} =
      Enum.split_with(results, fn
        {_, {:ok, _, _}} -> true
        {_, {:error, _, _}} -> false
      end)

    estimates = Enum.map(oks, fn {_, {:ok, pi, _}} -> pi end)

    if estimates != [] do
      avg = Enum.sum(estimates) / length(estimates)
      best = Enum.min_by(estimates, &abs(&1 - :math.pi()))
      worst = Enum.max_by(estimates, &abs(&1 - :math.pi()))

      log("  successful:  #{length(oks)} / #{length(results)}")
      log("  best:        #{format_float(best, 8)} (Δ #{format_delta(best)})")
      log("  worst:       #{format_float(worst, 8)} (Δ #{format_delta(worst)})")
      log("  average:     #{format_float(avg, 8)} (Δ #{format_delta(avg)})")
      log("  vs π:        #{format_float(:math.pi(), 8)}")

      delta = abs(avg - :math.pi())

      verdict =
        cond do
          delta < 0.001 -> "  ✓ accurate to 1e-3 — Modal compute survived fan-out cleanly"
          delta < 0.01 -> "  ~ accurate to 1e-2 — within MC noise for #{@points_per_sandbox}-pt samples"
          true -> "  ✗ outside MC noise (Δ #{format_float(delta, 6)}) — investigate"
        end

      log(verdict)
    end

    for {id, {:error, err, ms}} <- errs do
      log("\n  failed sandbox #{inspect(id)} (#{ms}ms):")
      log("    kind:     #{err.kind}")
      log("    code:     #{inspect(err.code)}")
      log("    message:  #{Exception.message(err)}")

      case err.metadata do
        %{stdout: out, stderr: stderr} ->
          if String.trim(out) != "", do: log("    stdout:   #{inspect(out)}")
          if String.trim(stderr) != "", do: log("    stderr:   #{inspect(stderr)}")

        _ ->
          :ok
      end
    end
  end

  defp format_float(f, places),
    do: f |> Float.round(places) |> Float.to_string()

  defp format_delta(f),
    do: f |> Kernel.-(:math.pi()) |> abs() |> Float.round(6) |> Float.to_string()

  # ── Telemetry ────────────────────────────────────────────────────
  #
  # Counts every `[:modal, :rpc, :stop]` event by
  # `{method, status, error_kind}`. The aggregation runs from many
  # processes concurrently — `Agent.update/2` serialises us into a
  # single counter without any caller-side locking.

  defp setup_telemetry do
    {:ok, _} = Agent.start_link(fn -> %{} end, name: __MODULE__.Metrics)

    :telemetry.attach(
      "pi-demo-telemetry",
      [:modal, :rpc, :stop],
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  @doc false
  def handle_telemetry(_event, _measurements, meta, _config) do
    key = {meta.method, Map.get(meta, :status), Map.get(meta, :error_kind)}
    Agent.update(__MODULE__.Metrics, fn m -> Map.update(m, key, 1, &(&1 + 1)) end)
  end

  defp print_telemetry do
    metrics = Agent.get(__MODULE__.Metrics, & &1)

    metrics
    |> Enum.sort()
    |> Enum.each(fn {{method, status, error_kind}, count} ->
      tag = if error_kind, do: " (#{error_kind})", else: ""
      log("  #{count |> to_string() |> String.pad_leading(3)} × #{method} #{status}#{tag}")
    end)
  end
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
  defp log(msg), do: IO.puts(:stderr, msg)
end

PiDemo.run()
