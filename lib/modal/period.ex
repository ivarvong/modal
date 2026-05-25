defmodule Modal.Period do
  @moduledoc """
  Tiny helpers that build the `:schedule` tuple
  `Modal.Function.deploy_*` accepts. Equivalent to Python's
  `modal.Period(seconds=N)` / `modal.Period(minutes=N)` / etc.

  Each helper returns `{:period, [unit: n, ...]}` — you can pass
  the result directly as the `:schedule` option, or compose units:

      Modal.Function.deploy_function(client, schedule: Modal.Period.seconds(15), ...)
      Modal.Function.deploy_function(client, schedule: Modal.Period.minutes(5), ...)

      # Compose by passing a keyword to `compose/1`:
      Modal.Function.deploy_function(client,
        schedule: Modal.Period.compose(hours: 1, minutes: 30),
        ...
      )

  ## When to use Period vs `Modal.Cron`

  Use `Modal.Period` for "every N units, no skew" cadences (15s
  polling, hourly aggregation). Use `Modal.Cron` when you want
  wall-clock alignment (top of every minute, every weekday at 9am
  in a specific timezone).
  """

  @doc "Run every N seconds. `Modal.Period.seconds(15)`."
  @spec seconds(number()) :: {:period, keyword()}
  def seconds(n) when is_number(n), do: {:period, [seconds: n]}

  @doc "Run every N minutes."
  @spec minutes(number()) :: {:period, keyword()}
  def minutes(n) when is_number(n), do: {:period, [minutes: n]}

  @doc "Run every N hours."
  @spec hours(number()) :: {:period, keyword()}
  def hours(n) when is_number(n), do: {:period, [hours: n]}

  @doc "Run every N days."
  @spec days(number()) :: {:period, keyword()}
  def days(n) when is_number(n), do: {:period, [days: n]}

  @doc "Run every N weeks."
  @spec weeks(number()) :: {:period, keyword()}
  def weeks(n) when is_number(n), do: {:period, [weeks: n]}

  @doc """
  Compose multiple units into one period. Pass any combination of
  `:years`, `:months`, `:weeks`, `:days`, `:hours`, `:minutes`,
  `:seconds`.

      Modal.Period.compose(hours: 1, minutes: 30)
      # → {:period, [hours: 1, minutes: 30]}
  """
  @spec compose(keyword()) :: {:period, keyword()}
  def compose(opts) when is_list(opts), do: {:period, opts}
end
