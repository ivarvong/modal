# Headless Chromium screenshot via Modal — boots Playwright in a
# Python sandbox, drives a page, downloads the PNG. The full
# "deploy a complex Python runtime on demand" story in one script.
#
#     elixir scripts/screenshot.exs https://nytimes.com
#     elixir scripts/screenshot.exs https://nytimes.com 2 2048
#
# Args:
#   1. URL (default: https://nytimes.com)
#   2. CPU cores (default: 1)
#   3. Memory MiB (default: 1024)
#
# Output: screenshot.png in the cwd. Cost report at the end.
#
# The image (Python + Playwright + Chromium) is ~2GB and takes ~2
# minutes to build the first time; every subsequent run is a cache
# hit and skips it.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule Screenshot do
  @default_url "https://nytimes.com"
  @output_path "screenshot.png"
  @app_name "modal-elixir-screenshot"

  @cpu_cost_per_core_sec 0.0000131
  @mem_cost_per_gib_sec 0.00000222

  @dockerfile [
    "FROM python:3.14-slim",
    "RUN pip install --no-cache-dir playwright",
    "RUN playwright install chromium --with-deps"
  ]

  @screenshot_script """
  from playwright.sync_api import sync_playwright
  import sys

  url, out = sys.argv[1], "/tmp/screenshot.png"

  with sync_playwright() as p:
      browser = p.chromium.launch()
      page = browser.new_page(viewport={"width": 1280, "height": 900})
      page.goto(url, wait_until="networkidle", timeout=60000)
      page.screenshot(path=out, full_page=False)
      browser.close()
  """

  def run(args) do
    :logger.set_application_level(:grpc, :warning)

    url = Enum.at(args, 0, @default_url)
    cpu_cores = args |> Enum.at(1, "1") |> String.to_integer()
    memory_mb = args |> Enum.at(2, "1024") |> String.to_integer()

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    phase("image")
    t = now()
    {:ok, image_id, image_status} = Modal.Image.get_or_create(client, @dockerfile, app: app)

    case image_status do
      :cached -> done(t, "cached")
      :built -> done(t, "built (Playwright + Chromium installed)")
    end

    phase("sandbox boot")
    sandbox_t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout_secs: 300,
        idle_timeout_secs: 60,
        cpu: cpu_cores * 1.0,
        memory_mb: memory_mb,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    done(sandbox_t, "ready — #{cpu_cores} vCPU, #{memory_mb} MiB (id: #{sandbox.id})")

    phase("screenshot")
    t = now()
    :ok = Modal.Filesystem.write_file(sandbox, "/tmp/screenshot.py", @screenshot_script)

    %{stdout: stdout, code: code} =
      Modal.Sandbox.exec_streaming!(sandbox, [
        "bash",
        "-c",
        "python3 /tmp/screenshot.py \"$1\" 2>&1",
        "--",
        url
      ])

    if code != 0 do
      if stdout != "", do: log("output: #{String.trim(stdout)}")
      raise "screenshot failed (exit #{code})"
    end

    done(t, url)

    phase("download")
    t = now()
    {:ok, png_bytes} = Modal.Filesystem.read_file(sandbox, "/tmp/screenshot.png")
    File.write!(@output_path, png_bytes)
    done(t, "#{byte_size(png_bytes)} bytes → #{@output_path}")

    Modal.Sandbox.terminate(sandbox)
    sandbox_secs = (now() - sandbox_t) / 1000

    phase("cost")
    print_cost(cpu_cores, memory_mb, sandbox_secs)
  end

  defp print_cost(cpu_cores, memory_mb, secs) do
    mem_gib = memory_mb / 1024
    cpu_cost = cpu_cores * @cpu_cost_per_core_sec * secs
    mem_cost = mem_gib * @mem_cost_per_gib_sec * secs
    total = cpu_cost + mem_cost

    log("sandbox lifetime:  #{Float.round(secs, 1)}s")

    log(
      "cpu  #{cpu_cores} core#{if cpu_cores == 1, do: "", else: "s"}  × $#{@cpu_cost_per_core_sec}/core/s × #{Float.round(secs, 1)}s = $#{fmt_cost(cpu_cost)}"
    )

    log(
      "mem  #{memory_mb} MiB  × $#{@mem_cost_per_gib_sec}/GiB/s  × #{Float.round(secs, 1)}s = $#{fmt_cost(mem_cost)}"
    )

    log(
      "total: \e[1m$#{fmt_cost(total)}\e[0m  (~$#{fmt_cost(total * 1000)} per 1,000 screenshots)"
    )
  end

  defp fmt_cost(f), do: :erlang.float_to_binary(f, decimals: 6)

  defp phase(name), do: IO.puts(:stderr, "\n\e[36m[#{name}]\e[0m")

  defp done(t0, msg),
    do: IO.puts(:stderr, "  \e[32m✓\e[0m #{msg} \e[2m(#{elapsed(t0)})\e[0m")

  defp log(msg), do: IO.puts(:stderr, "  #{msg}")

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

Screenshot.run(System.argv())
