defmodule Modal.Proxy do
  @moduledoc """
  Modal Proxies — outbound static IPs for sandboxes and functions.

  The inverse of `Modal.Sandbox`'s `:network_access` allowlist. Use
  `:network_access` when **you** want to restrict where your sandbox
  can reach. Use `Modal.Proxy` when the **target service** wants to
  restrict who can reach it — e.g. a customer's database that
  allowlists by source IP. Modal allocates a stable elastic IP for
  the proxy; outbound traffic from the attached sandbox/function
  egresses through that IP.

  ## Dashboard-provisioned

  Unlike most Modal primitives, **proxies cannot be created from
  code** — Modal's API returns `gRPC INVALID_ARGUMENT: "Creation
  method not supported"`. Provision in the Modal dashboard at
  https://modal.com/settings/proxies, then look up by name.

  ## Quick start

      # In the Modal dashboard: create a proxy named "customer-db-proxy".
      {:ok, proxy} = Modal.Proxy.get(client, "customer-db-proxy")

      {:ok, sandbox} =
        Modal.Sandbox.create(client,
          app_id: app.id,
          image_id: image_id,
          proxy_id: proxy.id,
          cmd: ["psql", "postgres://..."]
        )

      # Tell your customer to allowlist the proxy's IPs:
      Enum.each(proxy.ips, &IO.puts/1)
  """

  alias Modal.RPC

  alias Modal.Client.{
    Proxy,
    ProxyGetRequest
  }

  defstruct [:id, :name, :region, :ips]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          region: String.t() | nil,
          ips: [String.t()]
        }

  # ── Lookup ─────────────────────────────────────────────────────

  @doc """
  Look up a dashboard-provisioned proxy by name. Returns
  `{:error, %Modal.Error{kind: :grpc, code: 5}}` if no proxy with
  that name exists.

  ## Options

    * `:environment_name` — Modal environment (default: workspace
      default).
  """
  @spec get(GenServer.server(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Modal.Error.t()}
  def get(client, name, opts \\ []) when is_binary(name) do
    request = %ProxyGetRequest{
      name: name,
      environment_name: Keyword.get(opts, :environment_name, "")
    }

    with {:ok, resp} <- RPC.call(client, :ProxyGet, request) do
      {:ok, from_proto(resp.proxy)}
    end
  end

  @doc "Like `get/3` but raises on error."
  @spec get!(GenServer.server(), String.t(), keyword()) :: t()
  def get!(client, name, opts \\ []) do
    case get(client, name, opts) do
      {:ok, proxy} -> proxy
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── Internal ───────────────────────────────────────────────────

  defp from_proto(%Proxy{} = p) do
    %__MODULE__{
      id: p.proxy_id,
      name: p.name,
      region: p.region,
      ips: Enum.map(p.proxy_ips, & &1.proxy_ip)
    }
  end

  # ── Inspect ────────────────────────────────────────────────────

  defimpl Inspect do
    def inspect(%Modal.Proxy{id: id, name: name, ips: ips}, _opts) do
      "#Modal.Proxy<id: #{id}, name: #{inspect(name)}, ips: #{inspect(ips)}>"
    end
  end
end
