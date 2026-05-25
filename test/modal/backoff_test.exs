defmodule Modal.BackoffTest do
  @moduledoc """
  Tests for `Modal.Backoff.delay/3` — the retry-curve foundation under
  `Modal.ContainerProcess.wait_loop/2` and `Modal.Filesystem.fs_wait/3`.

  The production tests pass `wait_retry_delay: 0` / `fs_retry_delay: 0`
  to short-circuit sleeping during fast unit runs, which means the
  actual curve was never exercised. These tests pin the contract.
  """
  use ExUnit.Case, async: true

  describe "delay/3 — fast-path" do
    test "returns 0 when base_ms is 0 (test-config short-circuit)" do
      for attempt <- 0..20 do
        assert Modal.Backoff.delay(attempt, 0) == 0
        assert Modal.Backoff.delay(attempt, 0, 5_000) == 0
      end
    end
  end

  describe "delay/3 — bounded curve" do
    test "first attempt is at most base_ms (with jitter)" do
      # base = 100ms, attempt = 0 → raw = min(100 * 1, max) = 100
      # delay = :rand.uniform(100) ∈ 1..100
      for _ <- 1..100 do
        d = Modal.Backoff.delay(0, 100)
        assert d in 1..100, "expected 1..100, got #{d}"
      end
    end

    test "curve grows exponentially up to the cap (attempt=3, base=100, cap=10_000)" do
      # attempt 3 → raw = min(100 * 8, 10_000) = 800
      # delay = :rand.uniform(800) ∈ 1..800
      for _ <- 1..100 do
        d = Modal.Backoff.delay(3, 100, 10_000)
        assert d in 1..800
      end
    end

    test "caps at max_ms for high attempts" do
      # attempt 20 → raw = min(100 * 2^20, 5_000) = 5_000
      # delay = :rand.uniform(5_000) ∈ 1..5_000
      for _ <- 1..100 do
        d = Modal.Backoff.delay(20, 100, 5_000)
        assert d in 1..5_000
      end
    end

    test "never returns 0 once base > 0 (jitter floor is 1)" do
      # Defends against a `:rand.uniform(0)` regression — that crashes,
      # but a future `max(raw, 0)` instead of `max(raw, 1)` would
      # silently produce non-positive sleeps.
      for attempt <- 0..30 do
        d = Modal.Backoff.delay(attempt, 50)
        assert d >= 1
      end
    end
  end

  describe "delay/3 — property: result is always in 1..max_ms when base > 0" do
    # 5-line property covering the whole input space — catches the
    # arithmetic edge cases (Integer.pow overflow, min/max ordering,
    # jitter range).
    use ExUnitProperties

    property "delay ∈ 1..max_ms for any (attempt, base>0, max>=base)" do
      check all(
              attempt <- integer(0..30),
              base <- integer(1..1_000),
              extra <- integer(0..30_000)
            ) do
        max = base + extra
        d = Modal.Backoff.delay(attempt, base, max)
        assert d >= 1
        assert d <= max
      end
    end
  end
end
