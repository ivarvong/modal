defmodule Modal.FunctionCall do
  @moduledoc """
  Handle for an in-flight Modal Function invocation. Returned by
  `Modal.Function.spawn/4`; pass to `Modal.Function.await/2` to
  collect the result.

  The struct is small (id + back-pointers) and cheap to pass between
  processes — fan out N spawns, send the handles wherever you want,
  await them on a different process if needed. Each handle is single-
  use; awaiting twice on the same handle returns the cached result
  the first time and the wire response the second.
  """

  defstruct [:id, :function, :client]

  @type t :: %__MODULE__{
          id: String.t(),
          function: Modal.Function.t(),
          client: GenServer.server()
        }

  defimpl Inspect do
    def inspect(%Modal.FunctionCall{id: id, function: f}, _opts) do
      "#Modal.FunctionCall<id: #{id}, function: #{inspect(f.name)}>"
    end
  end
end
