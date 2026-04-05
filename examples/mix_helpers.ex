defmodule Modal.MixHelpers do
  @moduledoc false

  @doc false
  def credentials! do
    id = System.get_env("MODAL_TOKEN_ID")
    secret = System.get_env("MODAL_TOKEN_SECRET")
    unless id && secret, do: Mix.raise("Set MODAL_TOKEN_ID and MODAL_TOKEN_SECRET")
    {id, secret}
  end

  @doc false
  def now, do: System.monotonic_time(:millisecond)

  @doc false
  def elapsed(t0) do
    ms = System.monotonic_time(:millisecond) - t0
    if ms < 1000, do: "#{ms}ms", else: "#{Float.round(ms / 1000, 1)}s"
  end

  @doc false
  def fmt_cost(f), do: :erlang.float_to_binary(f, decimals: 6)
end
