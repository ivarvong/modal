defmodule Modal.Backoff do
  @moduledoc false

  @doc """
  Compute a retry delay with exponential backoff and jitter.

  Returns a delay in milliseconds: `min(base_ms * 2^attempt, max_ms)`,
  randomised uniformly from 1..delay to avoid thundering-herd effects.

  When `base_ms` is 0 (test config), always returns 0.
  """
  @spec delay(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def delay(attempt, base_ms, max_ms \\ 30_000)
  def delay(_attempt, 0, _max_ms), do: 0

  def delay(attempt, base_ms, max_ms) do
    raw = min(base_ms * Integer.pow(2, attempt), max_ms)
    :rand.uniform(max(raw, 1))
  end
end
