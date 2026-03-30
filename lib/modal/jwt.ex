defmodule Modal.JWT do
  @moduledoc false

  @doc "Parse the `exp` claim from a JWT. Returns unix timestamp or `default`."
  def parse_exp(jwt, default \\ 0) when is_binary(jwt) do
    with [_, payload, _] <- String.split(jwt, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_number(exp) <- Jason.decode(json) do
      trunc(exp)
    else
      _ -> default
    end
  end
end
