# 10 random math ops against a warm Python sandbox — first call pays
# the boot cost, the rest are sub-100ms. Demonstrates the
# "long-lived sandbox kept idle between requests" pattern that
# real services use to amortise startup latency.
#
# The sandbox is named (Sandbox.from_name lookup) and keeps itself
# warm via `idle_timeout_secs`. Run this twice in a row: the second
# run finds the still-warm sandbox and every call is fast.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule Calc do
  @app_name "modal-elixir-calc"
  @sandbox_name "calc-worker"
  @idle_timeout 300

  def run do
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    {:ok, image_id, _} =
      Modal.Image.get_or_create(client, ["FROM python:3.14-slim"], app: app)

    sandbox = find_or_create(client, app, image_id)

    exprs = random_exprs(10)
    log("\nSending 10 expressions to sandbox #{sandbox.id}")
    log("(idle_timeout: #{@idle_timeout}s — sandbox stays warm between runs)\n")

    results =
      Enum.map(Enum.with_index(exprs, 1), fn {expr, i} ->
        t = now()

        # `exec_streaming/3` is the idiomatic one-call form for "run a
        # command, get the result" — fuses exec/3 + await/2 + close/1.
        {:ok, %{stdout: output, code: code}} =
          Modal.Sandbox.exec_streaming(sandbox, ["python3", "-c", "print(#{expr})"])

        ms = now() - t

        result = if code == 0, do: String.trim(output), else: "error (exit #{code})"
        tag = if i == 1, do: " ← boot", else: ""

        log("  #{pad(i)}. #{pad_expr(expr)} = #{pad_result(result)}  #{fmt_ms(ms)}#{tag}")

        # Pace for human readability (so the boot vs warm difference is
        # obvious in the terminal). Drop this sleep for throughput
        # benchmarking — the warm calls are ~50ms apart unthrottled.
        if i < 10, do: Process.sleep(1000)

        ms
      end)

    [first | rest] = results
    log("\n  first (boot):  #{fmt_ms(first)}")
    log("  avg (warm):    #{fmt_ms(round(Enum.sum(rest) / length(rest)))}")
  end

  # ── Sandbox lifecycle ────────────────────────────────────────────

  defp find_or_create(client, app, image_id) do
    case Modal.Sandbox.from_name(client, @sandbox_name, app_name: @app_name) do
      {:ok, sb} ->
        log("  found warm sandbox #{sb.id}")
        sb

      {:error, _} ->
        log("  no warm sandbox found — booting...")

        Modal.Sandbox.create!(client,
          app: app,
          image_id: image_id,
          name: @sandbox_name,
          cmd: ["sleep", "infinity"],
          cpu: 0.125,
          memory_mb: 256,
          idle_timeout_secs: @idle_timeout
        )
    end
  end

  # ── Random math expressions ──────────────────────────────────────

  defp random_exprs(n), do: Enum.map(1..n, fn _ -> random_expr() end)

  defp random_expr do
    Enum.random([
      fn -> "#{rand(100)} ** #{rand(5) + 2}" end,
      fn -> "#{rand(10_000)} * #{rand(10_000)}" end,
      fn -> "sum(range(#{rand(900_000) + 100_000}))" end,
      fn ->
        "len(list(filter(lambda x: x % #{rand(9) + 2} == 0, range(#{rand(90_000) + 10_000}))))"
      end,
      fn -> "#{rand(1000)} * #{rand(1000)} + #{rand(1000)} * #{rand(1000)}" end
    ]).()
  end

  defp rand(n), do: :rand.uniform(n)

  # ── Formatting ───────────────────────────────────────────────────

  defp fmt_ms(ms) when ms < 1000, do: "\e[33m#{ms}ms\e[0m"
  defp fmt_ms(ms), do: "\e[31m#{Float.round(ms / 1000, 2)}s\e[0m"

  defp pad(i), do: String.pad_leading("#{i}", 2)
  defp pad_expr(e), do: String.pad_trailing(e, 44)
  defp pad_result(r), do: String.pad_trailing(r, 14)

  defp now, do: System.monotonic_time(:millisecond)
  defp log(msg), do: IO.puts(:stderr, msg)
end

Calc.run()
