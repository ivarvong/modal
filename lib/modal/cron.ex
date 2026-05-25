defmodule Modal.Cron do
  @moduledoc """
  Tiny helpers that build the `:schedule` tuple
  `Modal.Function.deploy_*` accepts for cron expressions. Equivalent
  to Python's `modal.Cron("...")`.

      # Top of every minute, UTC.
      Modal.Function.deploy_function(client,
        schedule: Modal.Cron.utc("* * * * *"),
        ...
      )

      # 9am every weekday, New York time.
      Modal.Function.deploy_function(client,
        schedule: Modal.Cron.in_timezone("0 9 * * 1-5", "America/New_York"),
        ...
      )

  ## When to use Cron vs `Modal.Period`

  Use `Modal.Cron` when you want **wall-clock alignment** — top of
  every minute, every weekday at 9am, etc. Use `Modal.Period` for
  "every N units" cadences without clock-alignment.

  ## Cron expression syntax

  Standard 5-field cron (`minute hour day-of-month month day-of-week`)
  or 6-field with seconds (`second minute hour day-of-month month day-of-week`).
  Modal parses both. See Modal's docs for the exact grammar.
  """

  @doc """
  Cron expression evaluated in UTC. The most common case.

      Modal.Cron.utc("*/15 * * * * *")   # every 15s, top-aligned
      Modal.Cron.utc("0 0 * * *")        # daily at midnight UTC
  """
  @spec utc(String.t()) :: {:cron, String.t()}
  def utc(expr) when is_binary(expr), do: {:cron, expr}

  @doc """
  Cron expression evaluated in a named timezone (IANA tz database,
  e.g. `"America/New_York"`, `"Europe/London"`).

      Modal.Cron.in_timezone("0 9 * * *", "America/New_York")
  """
  @spec in_timezone(String.t(), String.t()) :: {:cron, String.t(), keyword()}
  def in_timezone(expr, tz) when is_binary(expr) and is_binary(tz) do
    {:cron, expr, [timezone: tz]}
  end
end
