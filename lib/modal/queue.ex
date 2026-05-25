defmodule Modal.Queue do
  @moduledoc """
  Modal Queue — a distributed, persistent FIFO queue hosted by
  Modal. Same general shape as a SQS / Redis-list / RabbitMQ queue,
  but lives natively in Modal alongside your Functions and
  Sandboxes.

  ## When to reach for Modal.Queue

  Pick it when:

    * An Elixir orchestrator pushes work; a Modal Function (or
      Sandbox) consumes it. The autoscaling pattern: Function scales
      up containers as the queue grows.
    * Producer and consumer have independent lifetimes — neither
      needs the other up to enqueue/dequeue.
    * You want partitioned ordered consumption (one partition per
      tenant / per user / per shard).

  Skip it when:

    * The work fits inside one process — `Task.async_stream` is
      simpler, lower-latency, no RPC.

  ## Cross-language value encoding

  Same story as `Modal.Dict`: raw bytes on the wire, JSON by default
  for cross-language friendliness, `encoding: :raw` to opt out.
  Maps, lists, strings, numbers, booleans, nil round-trip cleanly
  to/from a Python Function that does `json.loads(item)` /
  `json.dumps(value)`.

  ## Quick start

      {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())
      {:ok, app}    = Modal.App.lookup(client, "my-svc")
      {:ok, q}      = Modal.Queue.get_or_create(client, "work", app: app)

      # Producer side — push jobs
      Modal.Queue.put_many(q, [%{job: 1}, %{job: 2}, %{job: 3}])

      # Consumer side — block until item available
      {:ok, item} = Modal.Queue.get(q, timeout_secs: 30)

      # From Python:
      #   import json, modal
      #   q = modal.Queue.from_name("work")
      #   item = json.loads(q.get())

  ## Surface

  Lifecycle: `get_or_create/3`, `delete/1`, `clear/2`.
  Producer: `put/3`.
  Consumer: `get/2`, `len/2`.

  ## Partitions

  Modal Queues support named partitions: items pushed with one
  `:partition` are consumed only by callers reading from that
  partition. Useful for "one ordered stream per tenant" patterns —
  worker N processes partition N, no cross-contamination. Pass
  `:partition` on `put/3` and `get/2` to opt in; default is the
  unnamed default partition.
  """

  alias Modal.RPC

  defstruct [:id, :name, :client]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          client: GenServer.server()
        }

  @type encoding :: :json | :pickle | :raw
  @type value :: term()

  # ── Lifecycle ───────────────────────────────────────────────────

  @doc """
  Look up a Queue by name, creating if missing. Returns a
  `%Modal.Queue{}` handle.

  ## Options

    * `:app` — the `%Modal.App{}` to scope the queue to.
    * `:environment_name` — Modal environment (default: workspace default).
  """
  @spec get_or_create(GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def get_or_create(client, name, opts \\ []) when is_binary(name) do
    request = %Modal.Client.QueueGetOrCreateRequest{
      deployment_name: name,
      environment_name: Keyword.get(opts, :environment_name, ""),
      object_creation_type: :OBJECT_CREATION_TYPE_CREATE_IF_MISSING
    }

    with {:ok, resp} <- RPC.call(client, :QueueGetOrCreate, request) do
      {:ok, %__MODULE__{id: resp.queue_id, name: name, client: client}}
    end
  end

  @doc "Delete the Queue on Modal's side. Idempotent."
  @spec delete(t()) :: :ok | {:error, Modal.Error.t()}
  def delete(%__MODULE__{} = q) do
    request = %Modal.Client.QueueDeleteRequest{queue_id: q.id}
    with {:ok, _} <- RPC.call(q.client, :QueueDelete, request), do: :ok
  end

  @doc """
  Drop all items in the queue. Items remain in any partition not
  named here unless `:all_partitions` is set.

  ## Options

    * `:partition` — clear only this named partition (default: unnamed).
    * `:all_partitions` — `true` to clear every partition.
  """
  @spec clear(t(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def clear(%__MODULE__{} = q, opts \\ []) do
    request = %Modal.Client.QueueClearRequest{
      queue_id: q.id,
      partition_key: to_partition(Keyword.get(opts, :partition)),
      all_partitions: Keyword.get(opts, :all_partitions, false)
    }

    with {:ok, _} <- RPC.call(q.client, :QueueClear, request), do: :ok
  end

  # ── Producer ────────────────────────────────────────────────────

  @doc """
  Enqueue one value. To push a list-typed value, this is what you
  want — `put_many/3` would interpret the list as multiple values.

  ## Options

    * `:encoding` — `:json` (default; Jason-encode the value),
      `:pickle` (Modal.Pickle for Python interop), or `:raw`
      (value must be a binary already).
    * `:partition` — named partition (default: unnamed).
    * `:partition_ttl_secs` — auto-delete the partition after N
      seconds of inactivity (Modal default).
  """
  @spec put(t(), value(), keyword()) :: :ok | {:error, Modal.Error.t()}
  def put(%__MODULE__{} = q, value, opts \\ []) do
    put_many(q, [value], opts)
  end

  @doc """
  Enqueue a list of values atomically. Use this when you have many
  values to push at once; for a single value (especially a list-typed
  one), use `put/3`.

  Same `:encoding` / `:partition` / `:partition_ttl_secs` options
  as `put/3`.
  """
  @spec put_many(t(), [value()], keyword()) :: :ok | {:error, Modal.Error.t()}
  def put_many(%__MODULE__{} = q, values, opts \\ []) when is_list(values) do
    encoding = Keyword.get(opts, :encoding, :json)

    request = %Modal.Client.QueuePutRequest{
      queue_id: q.id,
      values: Enum.map(values, &encode(&1, encoding)),
      partition_key: to_partition(Keyword.get(opts, :partition)),
      partition_ttl_seconds: Keyword.get(opts, :partition_ttl_secs, 0)
    }

    with {:ok, _} <- RPC.call(q.client, :QueuePut, request), do: :ok
  end

  # ── Consumer ────────────────────────────────────────────────────

  @doc """
  Dequeue one or more values. Returns `{:ok, value}` (or `{:ok, [values]}`
  if `:n > 1`), `:empty` when nothing arrives before `:timeout_secs`,
  or `{:error, err}`.

  Defaults to a 60-second blocking wait — long enough that polling
  loops feel cheap, short enough that a producer pause is visible.

  ## Options

    * `:timeout_secs` — float; server-side blocking wait. `0` =
      non-blocking. Default `60.0`.
    * `:n` — number of values to fetch in one call (default `1`).
      Returns a list when `n > 1`; single value otherwise.
    * `:encoding` — `:json` (default) or `:raw`.
    * `:partition` — named partition (default: unnamed).
  """
  @spec get(t(), keyword()) ::
          {:ok, value()} | {:ok, [value()]} | :empty | {:error, Modal.Error.t()}
  def get(%__MODULE__{} = q, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :json)
    n = Keyword.get(opts, :n, 1)

    request = %Modal.Client.QueueGetRequest{
      queue_id: q.id,
      timeout: Keyword.get(opts, :timeout_secs, 60.0),
      n_values: n,
      partition_key: to_partition(Keyword.get(opts, :partition))
    }

    with {:ok, resp} <- RPC.call(q.client, :QueueGet, request) do
      case {resp.values, n} do
        {[], _} -> :empty
        {values, 1} -> {:ok, decode(hd(values), encoding)}
        {values, _} -> {:ok, Enum.map(values, &decode(&1, encoding))}
      end
    end
  end

  @doc """
  Number of items currently queued. Counts only the named partition
  unless `:total` is set.

  ## Options

    * `:partition` — named partition (default: unnamed).
    * `:total` — `true` to count across all partitions.
  """
  @spec len(t(), keyword()) :: integer()
  def len(%__MODULE__{} = q, opts \\ []) do
    request = %Modal.Client.QueueLenRequest{
      queue_id: q.id,
      partition_key: to_partition(Keyword.get(opts, :partition)),
      total: Keyword.get(opts, :total, false)
    }

    case RPC.call(q.client, :QueueLen, request) do
      {:ok, resp} -> resp.len
      _ -> 0
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp to_partition(nil), do: ""
  defp to_partition(p) when is_binary(p), do: p

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
    def inspect(%Modal.Queue{id: id, name: nil}, _), do: "#Modal.Queue<id: #{id}>"

    def inspect(%Modal.Queue{id: id, name: name}, _),
      do: "#Modal.Queue<id: #{id}, name: #{inspect(name)}>"
  end
end
