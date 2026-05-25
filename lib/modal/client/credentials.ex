defmodule Modal.Client.Credentials do
  @moduledoc false
  @enforce_keys [:metadata]
  defstruct [:metadata]

  defimpl Inspect do
    def inspect(%Modal.Client.Credentials{}, _opts) do
      "#Modal.Client.Credentials<redacted>"
    end
  end
end
