defmodule Modal.Dict do
  @moduledoc """
  Modal Dict — a distributed, persistent key/value store hosted by
  Modal. The kind of thing you'd reach for Redis for: shared state
  across containers, results coordination, leaderboards, config.

  ## When to reach for Modal.Dict

  Pick it when:

    * State needs to outlive a single container (caches, jobs results,
      coordination flags).
    * Both an Elixir orchestrator and a Modal Function need to read /
      write the same state.
    * You don't want to operate Redis or pay for a separate KV.

  Skip it when:

    * State lives inside one BEAM process — ETS / GenServer is
      cheaper, lower-latency, simpler.
    * Throughput exceeds ~10k ops/sec — Modal's Dict isn't tuned for
      that; use Redis.

  ## Cross-language value encoding

  Modal's Dict stores raw bytes; serialization is the caller's job.
  Python's `modal.Dict` cloudpickles values by default — that's
  unreadable from Elixir. To stay cross-language-friendly:

    * **`encoding: :json` (default, recommended)**: this module
      Jason-encodes values on `put/3` and Jason-decodes on `get/2`.
      Maps, lists, strings, numbers, booleans, nil round-trip cleanly
      to/from Python via `json.dumps` / `json.loads`.
    * **`encoding: :pickle`**: match Python's native `modal.Dict`
      default. Values are encoded with `Modal.Pickle` (protocol 4,
      byte-equivalent to CPython's `pickle.dumps`) and keys are
      pickle-encoded too — so a Python `d[key]` / `d.get(key)` finds
      entries this library wrote, and vice versa, with no `json` shim
      on the Python side.
    * **`encoding: :raw`**: opt-out for when you've got bytes already
      (a serialized protobuf, a binary blob). You handle encoding;
      we just pass bytes through.

  Keys under `:json` / `:raw` are sent as UTF-8 bytes; under `:pickle`
  they are pickle-encoded to match Python's lookup. Pass any string.

  ## Quick start

      {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
      {:ok, app}    = Modal.App.lookup(client, "my-svc")
      {:ok, d}      = Modal.Dict.get_or_create(client, "results", app: app)

      :ok = Modal.Dict.put(d, "job_42", %{status: "done", value: 100})

      {:ok, value} = Modal.Dict.get(d, "job_42")
      # %{"status" => "done", "value" => 100}

      :not_found = Modal.Dict.get(d, "job_999")

      # From Python (in a Modal Function, reading the same Dict):
      #   import json, modal
      #   d = modal.Dict.from_name("results")
      #   value = json.loads(d["job_42"])

  ## Surface

  Lifecycle: `get_or_create/3`, `delete/1`.
  Read: `get/3`, `pop/3`, `contains?/2`, `len/1`.
  Write: `put/4`, `put_many/3`, `clear/1`.
  """

  alias Modal.RPC

  defstruct [:id, :name, :client]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          client: GenServer.server()
        }

  @type encoding :: :json | :pickle | :raw
  @type key :: String.t() | binary()
  @type value :: term()

  # ── Lifecycle ───────────────────────────────────────────────────

  @doc """
  Look up a Dict by name, creating if missing. Returns a
  `%Modal.Dict{}` handle.

  ## Options

    * `:app` — the `%Modal.App{}` to scope the dict to (recommended).
    * `:environment_name` — Modal environment (default: workspace default).
  """
  @spec get_or_create(GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def get_or_create(client, name, opts \\ []) when is_binary(name) do
    request = %Modal.Client.DictGetOrCreateRequest{
      deployment_name: name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
    }

    with {:ok, resp} <- RPC.call(client, :DictGetOrCreate, request) do
      {:ok, %__MODULE__{id: resp.dict_id, name: name, client: client}}
    end
  end

  @doc "Delete the entire Dict on Modal's side. Idempotent."
  @spec delete(t()) :: :ok | {:error, Modal.Error.t()}
  def delete(%__MODULE__{} = d) do
    request = %Modal.Client.DictDeleteRequest{dict_id: d.id}
    with {:ok, _} <- RPC.call(d.client, :DictDelete, request), do: :ok
  end

  # ── Read ────────────────────────────────────────────────────────

  @doc """
  Read a key. Returns `{:ok, value}`, `:not_found`, or `{:error, err}`.

  ## Options

    * `:encoding` — `:json` (default; Jason.decode! on the bytes) or
      `:raw` (return the bytes unchanged).
  """
  @spec get(t(), key(), keyword()) :: {:ok, value()} | :not_found | {:error, Modal.Error.t()}
  def get(%__MODULE__{} = d, key, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :json)
    request = %Modal.Client.DictGetRequest{dict_id: d.id, key: encode_key(key, encoding)}

    with {:ok, resp} <- RPC.call(d.client, :DictGet, request) do
      if resp.found do
        {:ok, decode(resp.value, encoding)}
      else
        :not_found
      end
    end
  end

  @doc """
  Atomic get + delete. Returns `{:ok, value}`, `:not_found`, or
  `{:error, err}`. Same `:encoding` option as `get/3`.
  """
  @spec pop(t(), key(), keyword()) :: {:ok, value()} | :not_found | {:error, Modal.Error.t()}
  def pop(%__MODULE__{} = d, key, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :json)
    request = %Modal.Client.DictPopRequest{dict_id: d.id, key: encode_key(key, encoding)}

    with {:ok, resp} <- RPC.call(d.client, :DictPop, request) do
      if resp.found do
        {:ok, decode(resp.value, encoding)}
      else
        :not_found
      end
    end
  end

  @doc """
  Key existence check.

  ## Options

    * `:encoding` — same `:json` (default) / `:pickle` / `:raw` as
      `get/3`. Controls how the lookup key is serialized on the wire,
      so cross-runtime callers (e.g. a Python `modal.Dict.put(...)`
      that pickle-encodes its key) match what you wrote.
  """
  @spec contains?(t(), key(), keyword()) :: boolean()
  def contains?(%__MODULE__{} = d, key, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :json)
    request = %Modal.Client.DictContainsRequest{dict_id: d.id, key: encode_key(key, encoding)}

    case RPC.call(d.client, :DictContains, request) do
      {:ok, resp} -> resp.found
      _ -> false
    end
  end

  @doc "Total number of keys."
  @spec len(t()) :: integer()
  def len(%__MODULE__{} = d) do
    request = %Modal.Client.DictLenRequest{dict_id: d.id}

    case RPC.call(d.client, :DictLen, request) do
      {:ok, resp} -> resp.len
      _ -> 0
    end
  end

  # ── Write ───────────────────────────────────────────────────────

  @doc """
  Store one key/value. Returns `:ok` or `{:error, err}`.

  ## Options

    * `:encoding` — `:json` (default; Jason.encode! the value) or
      `:raw` (value must be a binary, sent as-is).
    * `:if_not_exists` — `true` to make this a no-op if the key
      already exists (default `false` — overwrite).
  """
  @spec put(t(), key(), value(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def put(%__MODULE__{} = d, key, value, opts \\ []) do
    put_many(d, %{key => value}, opts)
  end

  @doc """
  Store many key/value pairs atomically. Same options as `put/4`.
  """
  @spec put_many(t(), %{optional(key()) => value()}, keyword()) ::
          :ok | {:error, Modal.Error.t()}
  def put_many(%__MODULE__{} = d, entries, opts \\ []) when is_map(entries) do
    encoding = Keyword.get(opts, :encoding, :json)
    if_not_exists = Keyword.get(opts, :if_not_exists, false)

    request = %Modal.Client.DictUpdateRequest{
      dict_id: d.id,
      if_not_exists: if_not_exists,
      updates:
        Enum.map(entries, fn {k, v} ->
          %Modal.Client.DictEntry{key: encode_key(k, encoding), value: encode(v, encoding)}
        end)
    }

    with {:ok, _} <- RPC.call(d.client, :DictUpdate, request), do: :ok
  end

  @doc "Remove all entries; the Dict itself stays around."
  @spec clear(t()) :: :ok | {:error, Modal.Error.t()}
  def clear(%__MODULE__{} = d) do
    request = %Modal.Client.DictClearRequest{dict_id: d.id}
    with {:ok, _} <- RPC.call(d.client, :DictClear, request), do: :ok
  end

  # ── Encoding helpers ────────────────────────────────────────────

  defp to_bytes(s) when is_binary(s), do: s

  # Keys: under :pickle, pickle-encode so a Python `d.get(key)` (which
  # pickle-encodes the lookup key) finds what we wrote. Under :json
  # and :raw, pass through as bytes — those modes don't claim Python
  # native interop.
  defp encode_key(k, :pickle), do: Modal.Pickle.encode(k)
  defp encode_key(k, _other), do: to_bytes(k)

  defp encode(value, :json), do: Jason.encode!(value)
  defp encode(value, :pickle), do: Modal.Pickle.encode(value)

  defp encode(value, :raw) when is_binary(value), do: value

  defp encode(value, :raw),
    do: raise(ArgumentError, "encoding: :raw requires a binary value, got #{inspect(value)}")

  defp decode(bytes, :json), do: Jason.decode!(bytes)
  defp decode(bytes, :pickle), do: Modal.Pickle.decode!(bytes)
  defp decode(bytes, :raw), do: bytes

  # ── Inspect ─────────────────────────────────────────────────────

  defimpl Inspect do
    def inspect(%Modal.Dict{id: id, name: nil}, _), do: "#Modal.Dict<id: #{id}>"

    def inspect(%Modal.Dict{id: id, name: name}, _),
      do: "#Modal.Dict<id: #{id}, name: #{inspect(name)}>"
  end
end
