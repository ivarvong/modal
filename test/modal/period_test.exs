defmodule Modal.PeriodTest do
  use ExUnit.Case, async: true

  test "each unit helper returns the right tuple shape" do
    assert Modal.Period.seconds(15) == {:period, [seconds: 15]}
    assert Modal.Period.minutes(5) == {:period, [minutes: 5]}
    assert Modal.Period.hours(1) == {:period, [hours: 1]}
    assert Modal.Period.days(7) == {:period, [days: 7]}
    assert Modal.Period.weeks(2) == {:period, [weeks: 2]}
  end

  test "compose/1 takes a keyword and tags it as :period" do
    assert Modal.Period.compose(hours: 1, minutes: 30) ==
             {:period, [hours: 1, minutes: 30]}
  end

  test "tuples flow through Modal.Function's :schedule validator" do
    # The whole point — make sure the tuples produced here are valid
    # inputs to Modal.Function (no need to remember tuple shape).
    assert {:ok, _} = Modal.Function.validate_schedule(Modal.Period.seconds(15))
    assert {:ok, _} = Modal.Function.validate_schedule(Modal.Period.minutes(5))

    assert {:ok, _} =
             Modal.Function.validate_schedule(Modal.Period.compose(hours: 1, minutes: 30))
  end
end
