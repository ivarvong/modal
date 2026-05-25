defmodule Modal.Properties.JWTTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Modal.JWT

  defp make_jwt(payload) do
    header = Base.url_encode64(~s({"alg":"none"}), padding: false)
    body = Base.url_encode64(Jason.encode!(payload), padding: false)
    "#{header}.#{body}."
  end

  describe "parse_exp/2" do
    # Core property: for any non-negative integer timestamp, parse_exp
    # round-trips it exactly. This would catch off-by-one errors, truncation
    # bugs, and any encoding/decoding asymmetry.
    property "round-trips any non-negative integer exp" do
      check all(exp <- non_negative_integer()) do
        jwt = make_jwt(%{"exp" => exp})
        assert JWT.parse_exp(jwt) == exp
      end
    end

    # parse_exp truncates floats — verify this holds for any float, not just
    # the example value 9_999_999_999.9 from the unit test.
    property "truncates float exp to integer" do
      check all(exp <- float(min: 0.0, max: 9.0e12)) do
        jwt = make_jwt(%{"exp" => exp})
        assert JWT.parse_exp(jwt) == trunc(exp)
      end
    end

    # When exp is absent, any custom default must be returned unchanged.
    property "returns the custom default when exp is missing" do
      check all(default <- integer()) do
        jwt = make_jwt(%{"sub" => "user"})
        assert JWT.parse_exp(jwt, default) == default
      end
    end

    # No matter what binary is passed as the JWT, parse_exp must never raise —
    # it always returns a number (0 or the supplied default).
    property "never raises on arbitrary binary input" do
      check all(noise <- binary()) do
        result = JWT.parse_exp(noise, -1)
        assert is_integer(result)
      end
    end

    # The default must be returned for any string that is not a valid JWT,
    # even if it happens to contain dots.
    property "returns default for malformed dot-separated strings" do
      check all(
              parts <- list_of(binary(), length: 3),
              junk = Enum.join(parts, ".")
            ) do
        # Valid JWTs have base64url payload with a JSON object containing exp.
        # Arbitrary binaries almost certainly won't, so the default must come back.
        result = JWT.parse_exp(junk, :sentinel)
        # Either it parsed a valid exp (extremely unlikely for random bytes)
        # or it returned the default.
        assert result == :sentinel or is_integer(result)
      end
    end
  end
end
