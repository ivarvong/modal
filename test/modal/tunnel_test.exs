defmodule Modal.TunnelTest do
  use ExUnit.Case, async: true

  describe "url/1" do
    test "omits the port when it's the HTTPS default 443" do
      tunnel = %Modal.Tunnel{host: "x.modal.host", port: 443, container_port: 8000}
      assert Modal.Tunnel.url(tunnel) == "https://x.modal.host"
    end

    test "includes the port when non-443" do
      tunnel = %Modal.Tunnel{host: "x.modal.host", port: 8443, container_port: 8000}
      assert Modal.Tunnel.url(tunnel) == "https://x.modal.host:8443"
    end
  end

  describe "tcp_url/1" do
    test "returns nil when no unencrypted tunnel exists" do
      tunnel = %Modal.Tunnel{host: "x", port: 443, container_port: 8000}
      assert Modal.Tunnel.tcp_url(tunnel) == nil
    end

    test "builds tcp:// URL when an unencrypted variant is configured" do
      tunnel = %Modal.Tunnel{
        host: "x",
        port: 443,
        container_port: 8000,
        unencrypted_host: "tcp.modal.host",
        unencrypted_port: 12_345
      }

      assert Modal.Tunnel.tcp_url(tunnel) == "tcp://tcp.modal.host:12345"
    end
  end

  describe "Inspect" do
    test "shows the container_port and the URL, hides unencrypted variant" do
      out =
        inspect(%Modal.Tunnel{host: "x.modal.host", port: 443, container_port: 8000})

      assert out =~ "container_port: 8000"
      assert out =~ "https://x.modal.host"
    end
  end
end
