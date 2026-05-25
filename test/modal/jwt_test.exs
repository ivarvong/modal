defmodule Modal.JWTTest do
  use ExUnit.Case, async: true

  alias Modal.JWT

  # Build a minimal JWT with the given payload map.
  defp make_jwt(payload) do
    header = Base.url_encode64(~s({"alg":"HS256","typ":"JWT"}), padding: false)
    body = Base.url_encode64(Jason.encode!(payload), padding: false)
    "#{header}.#{body}.sig"
  end

  describe "parse_exp/2" do
    test "returns the exp claim as an integer" do
      jwt = make_jwt(%{"exp" => 9_999_999_999})
      assert JWT.parse_exp(jwt) == 9_999_999_999
    end

    test "truncates float exp to integer" do
      jwt = make_jwt(%{"exp" => 9_999_999_999.9})
      assert JWT.parse_exp(jwt) == 9_999_999_999
    end

    test "returns default when exp is missing" do
      jwt = make_jwt(%{"sub" => "user"})
      assert JWT.parse_exp(jwt) == 0
      assert JWT.parse_exp(jwt, 42) == 42
    end

    test "returns default for a malformed JWT" do
      assert JWT.parse_exp("not.a.jwt") == 0
      assert JWT.parse_exp("", 99) == 99
    end

    test "returns default when payload is not valid base64" do
      assert JWT.parse_exp("header.!!!.sig") == 0
    end

    test "returns default when payload is valid base64 but not JSON" do
      bad = Base.url_encode64("not json", padding: false)
      assert JWT.parse_exp("h.#{bad}.s") == 0
    end
  end
end
