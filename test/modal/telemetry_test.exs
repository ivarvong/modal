defmodule Modal.TelemetryTest do
  @moduledoc """
  Smoke tests for the `Modal.Telemetry` convenience surface. The
  metadata contract itself is tested in `Modal.RPCTest` and
  `Modal.ContainerProcessTest` (where the events actually originate).
  """
  use ExUnit.Case, async: false

  describe "events/0" do
    test "enumerates both event families × start/stop/exception" do
      events = Modal.Telemetry.events()

      assert length(events) == 6

      for family <- [:rpc, :worker_rpc],
          phase <- [:start, :stop, :exception] do
        assert [:modal, family, phase] in events,
               "expected [:modal, #{inspect(family)}, #{inspect(phase)}] in events()"
      end
    end
  end

  describe "attach_default_logger/1" do
    test "attaches and detaches cleanly with a custom handler id" do
      handler_id = "modal-telemetry-test-#{System.unique_integer([:positive])}"

      assert :ok = Modal.Telemetry.attach_default_logger(handler_id: handler_id, level: :debug)

      # Re-attach should fail with :already_exists (telemetry's contract).
      assert {:error, :already_exists} =
               Modal.Telemetry.attach_default_logger(handler_id: handler_id, level: :debug)

      assert :ok = Modal.Telemetry.detach_default_logger(handler_id)
      assert {:error, :not_found} = Modal.Telemetry.detach_default_logger(handler_id)
    end

    test "default handler id reads as 'modal-default-logger'" do
      assert :ok = Modal.Telemetry.attach_default_logger()

      handlers = :telemetry.list_handlers([:modal, :rpc, :stop])

      assert Enum.any?(handlers, fn h -> h.id == "modal-default-logger" end),
             "default handler not attached under expected id"

      :ok = Modal.Telemetry.detach_default_logger()
    end
  end
end
