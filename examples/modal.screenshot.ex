defmodule Mix.Tasks.Modal.Screenshot do
  @moduledoc """
  Takes a screenshot of a URL using headless Chromium running in a Modal Sandbox.

      mix modal.screenshot https://nytimes.com
      mix modal.screenshot https://nytimes.com --cpu 1 --memory 1024

  Saves the result to `screenshot.png` in the current directory.

  ## Options

    * `--cpu`     - number of CPU cores (default: 1)
    * `--memory`  - memory in MiB (default: 1024)

  ## Performance notes

  The image (Python + Playwright + Chromium) is content-addressed and cached by Modal.
  The first run builds it (~2 minutes). Every subsequent run skips the build entirely.
  Sandbox boot and script execution are always paid per-run.
  """
  @shortdoc "Screenshot a URL with headless Chromium on Modal"
  use Mix.Task

  import Modal.MixHelpers

  @default_url "https://nytimes.com"
  @output_path "screenshot.png"
  @app_name "elixir-screenshot"

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

  @switches [cpu: :integer, memory: :integer]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {opts, argv} = OptionParser.parse!(args, strict: @switches)
    url = List.first(argv) || @default_url
    cpu_cores = Keyword.get(opts, :cpu, 1)
    memory_mb = Keyword.get(opts, :memory, 1024)

    {token_id, token_secret} = credentials!()
    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    {:ok, app_id} = Modal.App.lookup(client, @app_name)

    phase("image")
    t = now()
    {:ok, image_id, image_status} = Modal.Image.get_or_create(client, @dockerfile, app_id: app_id)

    case image_status do
      :cached -> done(t, "cached")
      :built -> done(t, "built (Playwright + Chromium installed)")
    end

    phase("sandbox boot")
    sandbox_t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        timeout: 300,
        idle_timeout: 60,
        cpu: cpu_cores * 1.0,
        memory_mb: memory_mb
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    done(sandbox_t, "ready — #{cpu_cores} vCPU, #{memory_mb} MiB (id: #{sandbox.id})")

    phase("screenshot")
    t = now()
    :ok = Modal.Sandbox.write_file(sandbox, "/tmp/screenshot.py", @screenshot_script)

    proc =
      Modal.Sandbox.exec!(sandbox, [
        "bash",
        "-c",
        "python3 /tmp/screenshot.py \"$1\" 2>&1",
        "--",
        url
      ])

    {:ok, result} = Modal.ContainerProcess.await(proc)
    Modal.ContainerProcess.close(proc)

    if result.code != 0 do
      if result.stdout != "", do: log("output: #{String.trim(result.stdout)}")
      Mix.raise("Screenshot failed (exit #{result.code})")
    end

    done(t, url)

    phase("download")
    t = now()
    {:ok, png_bytes} = Modal.Sandbox.read_file(sandbox, "/tmp/screenshot.png")
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

  defp phase(name), do: Mix.shell().info("\n\e[36m[#{name}]\e[0m")
  defp done(t0, msg), do: Mix.shell().info("  \e[32m✓\e[0m #{msg} \e[2m(#{elapsed(t0)})\e[0m")
  defp log(msg), do: Mix.shell().info("  #{msg}")
end
