defmodule Modal.CronTest do
  use ExUnit.Case, async: true

  test "utc/1 returns the 2-tuple :schedule form" do
    assert Modal.Cron.utc("* * * * *") == {:cron, "* * * * *"}
    assert Modal.Cron.utc("*/15 * * * * *") == {:cron, "*/15 * * * * *"}
  end

  test "in_timezone/2 returns the 3-tuple form with the timezone" do
    assert Modal.Cron.in_timezone("0 9 * * 1-5", "America/New_York") ==
             {:cron, "0 9 * * 1-5", [timezone: "America/New_York"]}
  end

  test "tuples flow through Modal.Function's :schedule validator" do
    assert {:ok, _} = Modal.Function.validate_schedule(Modal.Cron.utc("* * * * *"))

    assert {:ok, _} =
             Modal.Function.validate_schedule(
               Modal.Cron.in_timezone("0 9 * * *", "America/New_York")
             )
  end
end
