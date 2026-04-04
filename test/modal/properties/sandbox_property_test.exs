defmodule Modal.Properties.SandboxTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Mox

  setup :verify_on_exit!

  @client :mock
  @sandbox_id "sb-prop"

  defp stub_create do
    Modal.Client.Mock
    |> stub(:rpc, fn @client, :sandbox_create, _req, _timeout ->
      {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
    end)
  end

  describe "create/2 NimbleOptions validation" do
    # For any float in the valid CPU range, NimbleOptions accepts it and the
    # value is converted to millicores correctly (trunc(cpu * 1000)).
    property "accepts any cpu float in 0..64 and converts to millicores" do
      check all(cpu <- float(min: 0.0, max: 64.0)) do
        stub_create()

        Modal.Client.Mock
        |> stub(:rpc, fn @client, :sandbox_create, req, _timeout ->
          expected_milli = trunc(cpu * 1000)
          resources = req.definition.resources
          # resources may be nil when cpu == 0.0
          if expected_milli > 0 do
            assert resources.milli_cpu == expected_milli
          end

          {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
        end)

        assert {:ok, _} = Modal.Sandbox.create(@client, app_id: "ap-x", cpu: cpu)
      end
    end

    # Integer cpu values are also valid — NimbleOptions type is {:or, [:float, :integer]}.
    property "accepts integer cpu values" do
      check all(cpu <- integer(0..64)) do
        stub_create()
        assert {:ok, _} = Modal.Sandbox.create(@client, app_id: "ap-x", cpu: cpu)
      end
    end

    # Any positive memory value is accepted.
    property "accepts any non-negative memory_mb" do
      check all(mem <- non_negative_integer()) do
        stub_create()
        assert {:ok, _} = Modal.Sandbox.create(@client, app_id: "ap-x", memory_mb: mem)
      end
    end

    # A single region string is coerced to a list — the request must contain
    # exactly that region in a list regardless of what string was passed.
    property "coerces a single region string to [region]" do
      check all(region <- string(:alphanumeric, min_length: 1)) do
        Modal.Client.Mock
        |> stub(:rpc, fn @client, :sandbox_create, req, _timeout ->
          assert req.definition.scheduler_placement.regions == [region]
          {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
        end)

        assert {:ok, _} = Modal.Sandbox.create(@client, app_id: "ap-x", regions: region)
      end
    end

    # A list of regions is passed through unchanged.
    property "passes a list of regions through unchanged" do
      check all(regions <- list_of(string(:alphanumeric, min_length: 1), min_length: 1)) do
        Modal.Client.Mock
        |> stub(:rpc, fn @client, :sandbox_create, req, _timeout ->
          assert req.definition.scheduler_placement.regions == regions
          {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: @sandbox_id}}
        end)

        assert {:ok, _} = Modal.Sandbox.create(@client, app_id: "ap-x", regions: regions)
      end
    end

    # Missing app_id always fails NimbleOptions validation — no RPC is made.
    property "always fails validation without app_id, regardless of other opts" do
      check all(timeout <- positive_integer()) do
        # No mock expectations — any RPC would fail verify_on_exit!
        assert {:error, %NimbleOptions.ValidationError{}} =
                 Modal.Sandbox.create(@client, timeout: timeout)
      end
    end
  end
end
