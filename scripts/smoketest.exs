# Smallest possible end-to-end check: boot a Python sandbox, run a
# script, print the stdout, terminate. Use this as the "did Modal +
# the Elixir client work today?" sanity poke.
#
# **Start here** if you're new — this is the simplest demo. Then walk
# `calc.exs` (warm-sandbox lookup), `parallel_pi.exs` (fan-out +
# telemetry), `cloudflare_roundtrip.exs` (`Sandbox.run!/2` against a
# real workload), `coding_session.exs` (multi-turn), and the rest of
# `scripts/` for end-to-end patterns. The full suite is documented in
# the project README.

Mix.install([
  {:modal, path: Path.expand("..", __DIR__)}
])

defmodule Smoketest do
  def run do
    :logger.set_application_level(:grpc, :warning)

    {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
    {:ok, app} = Modal.App.lookup(client, "modal-elixir-smoketest")

    {:ok, image_id, _status} =
      Modal.Image.get_or_create(client, ["FROM python:3.14-slim"], app: app)

    IO.puts(:stderr, "image:   #{image_id}")

    script = """
    import math
    print(f"2 + 2 = {2 + 2}")
    print(f"sqrt(144) = {math.sqrt(144)}")
    print(f"2^10 = {2**10}")
    """

    # `Sandbox.run!/2` is the System.cmd/3 of Modal — create + exec +
    # await + terminate in one shot. Raises on non-zero exit.
    %{stdout: stdout, code: 0} =
      Modal.Sandbox.run!(client,
        app: app,
        image_id: image_id,
        cmd: ["python3", "-c", script],
        timeout_secs: 60
      )

    IO.puts(:stderr, "")
    IO.write(stdout)
  end
end

Smoketest.run()
