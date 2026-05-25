# Distributed Monte Carlo π — Elixir orchestrator using Modal Dict
# + Queue as the shared coordination layer.
#
# Pattern:
#
#   Elixir                          Modal (cloud)
#   ─────────────────              ────────────────
#   producer       ──put────►      Queue[jobs]
#                                      │
#                  ◄────get────────────┤
#   N consumer Tasks                   │
#   (compute π locally)                │
#                  ─────put───►     Dict[results]
#                                      │
#   aggregator     ◄────get──────────  ┘
#
# What this demonstrates about the Elixir Modal client:
#
#   * `Modal.Queue` and `Modal.Dict` are first-class wrappers around
#     Modal's distributed coordination primitives — usable as the
#     ONLY Modal touchpoint, with no Python in sight.
#   * Producer/consumer/aggregator stages can be separate processes,
#     separate BEAM nodes, or — by switching Modal accounts — entirely
#     separate organizations. All they share is the Queue/Dict name.
#   * Default JSON value encoding (Elixir-native) means cross-runtime
#     compatibility is one decision away: pass `encoding: :raw` if
#     you want to interop with a Python worker that owns its own
#     serialization.
#
# Versus `parallel_pi.exs` (sandbox-per-worker): same problem,
# different orchestration primitive. parallel_pi spawns 8 throwaway
# Sandboxes (Modal does the compute). This script does compute
# locally and uses Modal as the SHARED MUTABLE STATE — the producer,
# consumers, and aggregator could be on three different machines.
#
#     elixir scripts/distributed_pi.exs
#
# Needs (in .env):
#   MODAL_TOKEN_ID, MODAL_TOKEN_SECRET   — modal.com

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule DistributedPi do
  @app_name "modal-elixir-distributed-pi"
  @jobs 16
  @consumers 8
  @samples_per_job 1_000_000

  def run do
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)
    log("app: #{inspect(app)}")

    # Unique names per run so back-to-back invocations don't fight
    # over the same queue/dict.
    suffix = "#{System.os_time(:second)}-#{:rand.uniform(1_000_000)}"

    {queue, results_dict} = create_coordination!(client, app, suffix)

    try do
      push_jobs!(queue)
      consume_concurrent!(queue, results_dict)
      aggregate_and_print!(results_dict)
    after
      log("\n  cleanup: dropping queue + dict")
      Modal.Queue.delete(queue)
      Modal.Dict.delete(results_dict)
    end
  end

  # ── Phase 1: Queue + Dict ───────────────────────────────────────

  defp create_coordination!(client, app, suffix) do
    log_header("PHASE 1 — Modal.Queue + Modal.Dict")
    t = now()

    {:ok, queue} =
      Modal.Queue.get_or_create(client, "pi-work-#{suffix}", app: app)

    {:ok, results} =
      Modal.Dict.get_or_create(client, "pi-results-#{suffix}", app: app)

    log("  ✓ queue: #{queue.name} (#{queue.id})")
    log("  ✓ dict:  #{results.name} (#{results.id})")
    log("  created in #{elapsed(t)}")

    {queue, results}
  end

  # ── Phase 2: producer ──────────────────────────────────────────

  defp push_jobs!(queue) do
    log_header("PHASE 2 — producer (Elixir → Modal.Queue)")

    jobs =
      Enum.map(1..@jobs, fn i ->
        %{job_id: i, samples: @samples_per_job}
      end)

    t = now()
    :ok = Modal.Queue.put_many(queue, jobs)

    log(
      "  ✓ enqueued #{@jobs} jobs (each #{@samples_per_job} samples) in #{elapsed(t)} — queue len: #{Modal.Queue.len(queue)}"
    )
  end

  # ── Phase 3: consumers ─────────────────────────────────────────

  defp consume_concurrent!(queue, dict) do
    log_header("PHASE 3 — #{@consumers} parallel Elixir consumers")

    log("  Each consumer loops: Queue.get → compute → Dict.put")
    log("  until the queue is empty. Modal serialises gets across consumers.")
    log("")

    t = now()

    1..@consumers
    |> Task.async_stream(
      fn worker_id ->
        consumer_loop(queue, dict, worker_id, 0)
      end,
      max_concurrency: @consumers,
      timeout: 300_000,
      ordered: false
    )
    |> Enum.each(fn {:ok, {worker_id, jobs_done}} ->
      log("    worker #{worker_id}: processed #{jobs_done} jobs")
    end)

    log("\n  ✓ all #{@jobs} jobs drained in #{elapsed(t)}")
  end

  defp consumer_loop(queue, dict, worker_id, processed) do
    case Modal.Queue.get(queue, timeout_secs: 1.0) do
      {:ok, %{"job_id" => job_id, "samples" => n}} ->
        hits = monte_carlo_hits(n)

        result = %{
          job_id: job_id,
          samples: n,
          hits: hits,
          worker_id: worker_id
        }

        :ok = Modal.Dict.put(dict, to_string(job_id), result)
        consumer_loop(queue, dict, worker_id, processed + 1)

      :empty ->
        {worker_id, processed}

      {:error, e} ->
        raise "consumer #{worker_id}: queue.get failed: #{inspect(e)}"
    end
  end

  defp monte_carlo_hits(n) do
    Enum.reduce(1..n, 0, fn _, acc ->
      x = :rand.uniform()
      y = :rand.uniform()
      if x * x + y * y < 1.0, do: acc + 1, else: acc
    end)
  end

  # ── Phase 4: aggregate from Dict ───────────────────────────────

  defp aggregate_and_print!(dict) do
    log_header("PHASE 4 — aggregate from Modal.Dict")

    t = now()

    results =
      1..@jobs
      |> Enum.map(fn id ->
        case Modal.Dict.get(dict, to_string(id)) do
          {:ok, body} -> body
          :not_found -> raise "missing job #{id} from Dict"
        end
      end)

    total_samples = Enum.reduce(results, 0, fn r, acc -> acc + r["samples"] end)
    total_hits = Enum.reduce(results, 0, fn r, acc -> acc + r["hits"] end)
    pi_estimate = 4.0 * total_hits / total_samples
    error = abs(pi_estimate - :math.pi())

    log("  read #{length(results)} results in #{elapsed(t)}")
    log("")
    log("  total samples: #{total_samples}")
    log("  total hits:    #{total_hits}")
    log("  π estimate:    #{:erlang.float_to_binary(pi_estimate, decimals: 6)}")

    log(
      "  actual π:      #{:erlang.float_to_binary(:math.pi(), decimals: 6)}  " <>
        "(error: #{:erlang.float_to_binary(error, decimals: 6)})"
    )

    log("")
    log("  worker → jobs:")

    results
    |> Enum.group_by(& &1["worker_id"])
    |> Enum.sort()
    |> Enum.each(fn {worker_id, jobs} ->
      log("    #{worker_id}: #{length(jobs)} jobs")
    end)

    log("""

      Notes:
        * `Modal.Queue.get/2` is a server-side atomic pop — Modal
          guarantees each job is delivered to exactly one consumer.
          No application-level locking needed.
        * Producer, consumers, and aggregator share NOTHING locally.
          Move any of them to a different BEAM node (or even a
          different Modal account) and the demo still works — the
          Queue/Dict pair is the only coordination layer.
        * Values are JSON-encoded by default. For cross-runtime
          interop with a Python worker that expects pickle, pass
          `encoding: :raw` and serialize yourself.
    """)
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp log_header(msg), do: IO.puts(:stderr, "\n\e[1m── #{msg} ──────────────\e[0m")
  defp log(msg), do: IO.puts(:stderr, msg)
  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: fmt_ms(now() - t)
  defp fmt_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp fmt_ms(ms), do: "#{Float.round(ms / 1000, 2)}s"
end

DistributedPi.run()
