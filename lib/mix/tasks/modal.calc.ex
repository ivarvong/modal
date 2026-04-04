defmodule Mix.Tasks.Modal.Calc do
  @moduledoc """
  Sends 10 random math expressions to a persistent Python sandbox and reports
  the latency of each exec call.

  The sandbox is kept alive between runs (idle_timeout: 300s), so the first
  call in a session pays the boot cost and subsequent calls are warm.

      mix modal.calc
  """
  @shortdoc "10 random math ops against a warm Python sandbox"
  use Mix.Task

  import Modal.MixHelpers

  @app_name "elixir-calc"
  @sandbox_name "calc-worker"
  @idle_timeout 300

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {token_id, token_secret} = credentials!()

    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    {:ok, app_id} = Modal.App.lookup(client, @app_name)

    {:ok, image_id, _} =
      Modal.Image.get_or_create(client, ["FROM python:3.12-slim"], app_id: app_id)

    sandbox = find_or_create(client, app_id, image_id)

    exprs = random_exprs(10)

    Mix.shell().info("\nSending 10 expressions to sandbox #{sandbox.id}")
    Mix.shell().info("(idle_timeout: #{@idle_timeout}s — sandbox stays warm between runs)\n")

    results =
      Enum.map(Enum.with_index(exprs, 1), fn {expr, i} ->
        t = now()
        proc = Modal.Sandbox.exec!(sandbox, ["python3", "-c", "print(#{expr})"])
        {:ok, %{stdout: output, code: code}} = Modal.ContainerProcess.await(proc)
        Modal.ContainerProcess.close(proc)
        ms = now() - t

        result = if code == 0, do: String.trim(output), else: "error (exit #{code})"
        tag = if i == 1, do: " ← boot", else: ""

        Mix.shell().info(
          "  #{pad(i)}. #{pad_expr(expr)} = #{pad_result(result)}  #{fmt_ms(ms)}#{tag}"
        )

        if i < 10, do: Process.sleep(1000)

        ms
      end)

    [first | rest] = results
    Mix.shell().info("\n  first (boot):  #{fmt_ms(first)}")
    Mix.shell().info("  avg (warm):    #{fmt_ms(round(Enum.sum(rest) / length(rest)))}")
  end

  # ── Sandbox lifecycle ────────────────────────────────────────────

  defp find_or_create(client, app_id, image_id) do
    case Modal.Sandbox.from_name(client, @sandbox_name, app_name: @app_name) do
      {:ok, sb} ->
        Mix.shell().info("  found warm sandbox #{sb.id}")
        sb

      {:error, _} ->
        Mix.shell().info("  no warm sandbox found — booting...")

        Modal.Sandbox.create!(client,
          app_id: app_id,
          image_id: image_id,
          name: @sandbox_name,
          cmd: ["sleep", "infinity"],
          cpu: 0.125,
          memory_mb: 256,
          idle_timeout: @idle_timeout
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
end
