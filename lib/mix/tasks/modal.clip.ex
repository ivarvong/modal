defmodule Mix.Tasks.Modal.Clip do
  @moduledoc """
  Downloads a video, clips it, and resizes to 720p using ffmpeg in a Modal Sandbox.

  The source can be any public URL, or a presigned S3/R2 URL.

      mix modal.clip https://example.com/video.mp4 --start 10 --end 30
      mix modal.clip https://example.com/video.mp4 --start 00:01:15 --end 00:02:00

  Start/end accept either seconds (e.g. `90`) or HH:MM:SS (e.g. `00:01:30`).
  Output is written to `clip.mp4` in the current directory.

  ## Options

    * `--start`   - clip start (default: 0)
    * `--end`     - clip end, required
    * `--cpu`     - CPU cores (default: 2.0, more = faster encode)
    * `--memory`  - memory in MiB (default: 1024)
    * `--output`  - output filename (default: clip.mp4)
    * `--crf`     - ffmpeg CRF quality, 0–51, lower = better (default: 23)
  """
  @shortdoc "Clip + resize a video to 720p via ffmpeg on Modal"
  use Mix.Task

  import Modal.MixHelpers

  @app_name "elixir-clip"
  @default_output "clip.mp4"

  @cpu_cost_per_core_sec 0.0000131
  @mem_cost_per_gib_sec 0.00000222

  @dockerfile [
    "FROM ubuntu:22.04",
    "RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg curl ca-certificates && rm -rf /var/lib/apt/lists/*"
  ]

  @switches [
    start: :string,
    end: :string,
    cpu: :float,
    memory: :integer,
    output: :string,
    crf: :integer
  ]
  @aliases [s: :start, e: :end, o: :output]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    :logger.set_application_level(:grpc, :warning)
    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    url = List.first(argv) || Mix.raise("Usage: mix modal.clip URL --start T --end T")
    start = Keyword.get(opts, :start, "0")
    stop = Keyword.get(opts, :end) || Mix.raise("--end is required")
    cpu = Keyword.get(opts, :cpu, 2.0)
    mem_mb = Keyword.get(opts, :memory, 1024)
    output = Keyword.get(opts, :output, @default_output)
    crf = Keyword.get(opts, :crf, 23)

    duration_secs = to_seconds(stop) - to_seconds(start)
    if duration_secs <= 0, do: Mix.raise("--end must be after --start")

    {token_id, token_secret} = credentials!()
    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    {:ok, app_id} = Modal.App.lookup(client, @app_name)

    # ── Phase 1: Image ───────────────────────────────────────────────
    phase("image")
    t = now()
    {:ok, image_id, status} = Modal.Image.get_or_create(client, @dockerfile, app_id: app_id)

    case status do
      :cached -> done(t, "cached")
      :built -> done(t, "built (ffmpeg + curl)")
    end

    # ── Phase 2: Sandbox boot ────────────────────────────────────────
    phase("sandbox boot")
    sandbox_t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app_id: app_id,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        cpu: cpu,
        memory_mb: mem_mb,
        timeout: 600,
        idle_timeout: 60
      )

    {:ok, _, sandbox} = Modal.Sandbox.get_task_id(sandbox)
    done(sandbox_t, "ready — #{cpu} vCPU, #{mem_mb} MiB")

    # ── Phase 3: Download ────────────────────────────────────────────
    # Fetch the source video inside the sandbox — avoids shuttling
    # potentially large files through the local machine.
    phase("download")
    t = now()
    run!(sandbox, ~s(curl -fSL --progress-bar -o /tmp/input.mp4 "#{url}" 2>&1))
    %{stdout: size_out} = run!(sandbox, "wc -c < /tmp/input.mp4")
    bytes = size_out |> String.trim() |> String.to_integer()
    done(t, "#{fmt_bytes(bytes)} fetched")

    # ── Phase 4: Clip + resize ───────────────────────────────────────
    # -ss before -i = fast input seek (no decode of skipped frames).
    # scale=-2:720  = 720p, width auto-calculated, divisible by 2.
    # -movflags +faststart = moov atom at front, streamable immediately.
    phase("ffmpeg")
    t = now()

    ffmpeg_cmd =
      Enum.join(
        [
          "ffmpeg -y",
          "-ss #{start}",
          "-i /tmp/input.mp4",
          "-t #{duration_secs}",
          ~s(-vf "scale=-2:720"),
          "-c:v libx264 -crf #{crf} -preset fast",
          "-c:a aac",
          "-movflags +faststart",
          "/tmp/output.mp4",
          "2>&1"
        ],
        " "
      )

    run!(sandbox, ffmpeg_cmd)

    %{stdout: out_size_str} = run!(sandbox, "wc -c < /tmp/output.mp4")
    out_bytes = out_size_str |> String.trim() |> String.to_integer()
    done(t, "#{Float.round(duration_secs * 1.0, 1)}s clip → #{fmt_bytes(out_bytes)}")

    # ── Phase 5: Download result ─────────────────────────────────────
    phase("export")
    t = now()
    {:ok, mp4} = Modal.Sandbox.read_file(sandbox, "/tmp/output.mp4")
    File.write!(output, mp4)
    done(t, "#{fmt_bytes(byte_size(mp4))} → #{output}")

    # ── Cleanup + cost ───────────────────────────────────────────────
    Modal.Sandbox.terminate(sandbox)
    sandbox_secs = (now() - sandbox_t) / 1000

    phase("cost")
    print_cost(cpu, mem_mb, sandbox_secs)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp run!(sandbox, cmd) do
    proc = Modal.Sandbox.exec!(sandbox, ["bash", "-c", cmd])
    {:ok, result} = Modal.ContainerProcess.await(proc)
    Modal.ContainerProcess.close(proc)

    if result.code != 0 do
      # Truncate stdout to avoid dumping megabytes (e.g. curl output) into the error.
      preview = result.stdout |> String.slice(0, 500) |> String.trim()
      suffix = if byte_size(result.stdout) > 500, do: "\n  [... truncated]", else: ""
      Mix.raise("Command failed (exit #{result.code}):\n  $ #{cmd}\n#{preview}#{suffix}")
    end

    result
  end

  # Accept "90", "1:30", "00:01:30". Raises with a clear message on bad input.
  defp to_seconds(t) do
    parts = String.split(t, ":")

    parsed =
      Enum.map(parts, fn p ->
        case Integer.parse(p) do
          {n, ""} -> n
          _ -> Mix.raise("Invalid time '#{t}'. Use seconds (90) or HH:MM:SS (00:01:30).")
        end
      end)

    case parsed do
      [s] -> s * 1.0
      [m, s] -> m * 60 + s * 1.0
      [h, m, s] -> h * 3600 + m * 60 + s * 1.0
      _ -> Mix.raise("Invalid time '#{t}'. Use seconds (90) or HH:MM:SS (00:01:30).")
    end
  end

  defp fmt_bytes(b) when b < 1_048_576, do: "#{Float.round(b / 1024, 1)} KiB"
  defp fmt_bytes(b), do: "#{Float.round(b / 1_048_576, 1)} MiB"

  defp print_cost(cpu_cores, mem_mb, secs) do
    mem_gib = mem_mb / 1024
    cpu_cost = cpu_cores * @cpu_cost_per_core_sec * secs
    mem_cost = mem_gib * @mem_cost_per_gib_sec * secs
    total = cpu_cost + mem_cost
    log("sandbox lifetime:  #{Float.round(secs, 1)}s")

    log(
      "cpu  #{cpu_cores} cores × $#{@cpu_cost_per_core_sec}/core/s × #{Float.round(secs, 1)}s = $#{fmt_cost(cpu_cost)}"
    )

    log(
      "mem  #{mem_mb} MiB   × $#{@mem_cost_per_gib_sec}/GiB/s  × #{Float.round(secs, 1)}s = $#{fmt_cost(mem_cost)}"
    )

    log("total: \e[1m$#{fmt_cost(total)}\e[0m")
  end

  defp phase(name), do: Mix.shell().info("\n\e[36m[#{name}]\e[0m")
  defp done(t0, msg), do: Mix.shell().info("  \e[32m✓\e[0m #{msg} \e[2m(#{elapsed(t0)})\e[0m")
  defp log(msg), do: Mix.shell().info("  #{msg}")
end
