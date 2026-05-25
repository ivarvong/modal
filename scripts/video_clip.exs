# Clip + resize a video to 720p via ffmpeg in a Modal sandbox.
# The source can be any public URL or a presigned S3/R2 URL.
#
#     elixir scripts/video_clip.exs https://example.com/video.mp4 0 30
#     elixir scripts/video_clip.exs https://example.com/video.mp4 00:01:15 00:02:00
#
# Args:
#   1. URL (required)
#   2. start time — seconds (90) or HH:MM:SS (00:01:30); default "0"
#   3. end time   — required
#   4. CPU cores (default 2.0)
#   5. memory MiB (default 1024)
#   6. output filename (default clip.mp4)
#   7. CRF quality 0-51 (default 23, lower = better)
#
# Demonstrates the "heavy CPU workload that doesn't fit on the
# laptop" pattern — Modal sandboxes get cheap multicore for the
# minute it takes ffmpeg to encode, then go away.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule VideoClip do
  @app_name "modal-elixir-video-clip"
  @default_output "clip.mp4"

  @cpu_cost_per_core_sec 0.0000131
  @mem_cost_per_gib_sec 0.00000222

  @dockerfile [
    "FROM ubuntu:22.04",
    "RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg curl ca-certificates && rm -rf /var/lib/apt/lists/*"
  ]

  def run(args) do
    :logger.set_application_level(:grpc, :warning)

    url = Enum.at(args, 0) || raise "usage: video_clip.exs URL START END [CPU MEM OUTPUT CRF]"
    start = Enum.at(args, 1, "0")
    stop = Enum.at(args, 2) || raise "end time required"
    cpu = args |> Enum.at(3, "2.0") |> String.to_float()
    mem_mb = args |> Enum.at(4, "1024") |> String.to_integer()
    output = Enum.at(args, 5, @default_output)
    crf = args |> Enum.at(6, "23") |> String.to_integer()

    duration_secs = to_seconds(stop) - to_seconds(start)
    if duration_secs <= 0, do: raise("end must be after start")

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, @app_name)

    phase("image")
    t = now()
    {:ok, image_id, status} = Modal.Image.get_or_create(client, @dockerfile, app: app)

    case status do
      :cached -> done(t, "cached")
      :built -> done(t, "built (ffmpeg + curl)")
    end

    phase("sandbox boot")
    sandbox_t = now()

    sandbox =
      Modal.Sandbox.create!(client,
        app: app,
        image_id: image_id,
        cmd: ["sleep", "infinity"],
        cpu: cpu,
        memory_mb: mem_mb,
        timeout_secs: 600,
        idle_timeout_secs: 60,
        terminate_on_caller_exit: :silent
      )

    {:ok, _task_id} = Modal.Sandbox.get_task_id(sandbox)
    done(sandbox_t, "ready — #{cpu} vCPU, #{mem_mb} MiB")

    # Fetch the source video inside the sandbox so it doesn't shuttle
    # through this machine.
    phase("download")
    t = now()
    run!(sandbox, ~s(curl -fSL --progress-bar -o /tmp/input.mp4 "#{url}" 2>&1))
    %{stdout: size_out} = run!(sandbox, "wc -c < /tmp/input.mp4")
    bytes = size_out |> String.trim() |> String.to_integer()
    done(t, "#{fmt_bytes(bytes)} fetched")

    # `-ss` before `-i` = fast input seek (no decode of skipped
    # frames). `scale=-2:720` = 720p, width auto, divisible by 2.
    # `+faststart` puts the moov atom up front for instant streaming.
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

    phase("export")
    t = now()
    {:ok, mp4} = Modal.Filesystem.read_file(sandbox, "/tmp/output.mp4")
    File.write!(output, mp4)
    done(t, "#{fmt_bytes(byte_size(mp4))} → #{output}")

    Modal.Sandbox.terminate(sandbox)
    sandbox_secs = (now() - sandbox_t) / 1000

    phase("cost")
    print_cost(cpu, mem_mb, sandbox_secs)
  end

  defp run!(sandbox, cmd) do
    result = Modal.Sandbox.exec_streaming!(sandbox, ["bash", "-c", cmd])
    result
  end

  defp to_seconds(t) do
    parts = String.split(t, ":")

    parsed =
      Enum.map(parts, fn p ->
        case Integer.parse(p) do
          {n, ""} -> n
          _ -> raise("invalid time '#{t}'. Use seconds (90) or HH:MM:SS (00:01:30).")
        end
      end)

    case parsed do
      [s] -> s * 1.0
      [m, s] -> m * 60 + s * 1.0
      [h, m, s] -> h * 3600 + m * 60 + s * 1.0
      _ -> raise("invalid time '#{t}'. Use seconds (90) or HH:MM:SS (00:01:30).")
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

  defp fmt_cost(f), do: :erlang.float_to_binary(f, decimals: 6)

  defp phase(name), do: IO.puts(:stderr, "\n\e[36m[#{name}]\e[0m")

  defp done(t0, msg),
    do: IO.puts(:stderr, "  \e[32m✓\e[0m #{msg} \e[2m(#{elapsed(t0)})\e[0m")

  defp log(msg), do: IO.puts(:stderr, "  #{msg}")

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(t), do: "#{now() - t}ms"
end

VideoClip.run(System.argv())
