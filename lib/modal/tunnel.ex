defmodule Modal.Tunnel do
  @moduledoc """
  An HTTPS (and optionally TCP) tunnel from outside Modal into a
  container port of a running sandbox.

  `Modal.Sandbox.tunnels/1` returns a `%{container_port => %Modal.Tunnel{}}`
  map, so the common case is `tunnels[8000]`:

      sandbox = Modal.Sandbox.create!(client, ports: [8000], ...)
      {:ok, tunnels} = Modal.Sandbox.tunnels(sandbox)
      tunnel = tunnels[8000]
      Modal.Tunnel.url(tunnel)
      #=> "https://ta-01ksacs097ypyrza1nhsm35gfe-8000-z3qbyvoly0nqpk4001h6p0kgl.w.modal.host"

  ## Fields

    * `:host` — encrypted hostname (always HTTPS via the host's
      assigned cert).
    * `:port` — port for the HTTPS-encrypted tunnel; typically 443.
    * `:container_port` — the port inside the sandbox container that
      this tunnel maps to.
    * `:unencrypted_host` / `:unencrypted_port` — only set when the
      sandbox was created with the unencrypted variant; `nil`
      otherwise. Use only when you specifically need plaintext TCP.

  The shape mirrors Python's `Sandbox.tunnels()` (which returns a
  `dict[int, Tunnel]` keyed by container_port since v0.64.153).
  """

  @enforce_keys [:host, :port, :container_port]
  defstruct [:host, :port, :container_port, :unencrypted_host, :unencrypted_port]

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          container_port: pos_integer(),
          unencrypted_host: String.t() | nil,
          unencrypted_port: pos_integer() | nil
        }

  @doc """
  Build the HTTPS URL for this tunnel. Omits the port when it's the
  default 443 so the URL looks the way browsers and `curl` print it.

      iex> Modal.Tunnel.url(%Modal.Tunnel{host: "x.modal.host", port: 443, container_port: 8000})
      "https://x.modal.host"

      iex> Modal.Tunnel.url(%Modal.Tunnel{host: "x.modal.host", port: 8443, container_port: 8000})
      "https://x.modal.host:8443"
  """
  @spec url(t()) :: String.t()
  def url(%__MODULE__{host: host, port: 443}), do: "https://#{host}"
  def url(%__MODULE__{host: host, port: port}), do: "https://#{host}:#{port}"

  @doc """
  Build the unencrypted TCP URL for this tunnel, if it was set up
  with one. Returns `nil` if no unencrypted variant exists — most
  sandboxes don't have one.

      iex> Modal.Tunnel.tcp_url(%Modal.Tunnel{host: "x", port: 443,
      ...>   unencrypted_host: "tcp.modal.host", unencrypted_port: 12345,
      ...>   container_port: 8000})
      "tcp://tcp.modal.host:12345"
  """
  @spec tcp_url(t()) :: String.t() | nil
  def tcp_url(%__MODULE__{unencrypted_host: nil}), do: nil

  def tcp_url(%__MODULE__{unencrypted_host: host, unencrypted_port: port}),
    do: "tcp://#{host}:#{port}"

  # ── Inspect — terse, host + container_port only ─────────────────

  defimpl Inspect do
    def inspect(%Modal.Tunnel{container_port: cp} = tunnel, _opts) do
      ~s|#Modal.Tunnel<container_port: #{cp}, url: "#{Modal.Tunnel.url(tunnel)}">|
    end
  end
end
