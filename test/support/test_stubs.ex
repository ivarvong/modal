defmodule Modal.Test.SlowStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A stub that records metadata used per-call and sleeps to simulate a slow
  # RPC. Used to prove that Modal.Client dispatches requests concurrently.

  @impl true
  def call(_channel, _method, _request, _opts) do
    Process.sleep(50)
    {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    {:ok, []}
  end
end

defmodule Modal.Test.CredentialSpyStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # Records the token-id used in each call so credential isolation can be
  # verified: client A's credential must never appear in client B's RPCs.
  # The recorder PID is stored in :persistent_term under :modal_spy_recorder.

  @impl true
  def call(_channel, _method, _request, opts) do
    token_id = get_in(opts, [:metadata, "x-modal-token-id"])

    case :persistent_term.get(:modal_spy_recorder, nil) do
      nil -> :ok
      recorder -> send(recorder, {:spy_token, token_id})
    end

    {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
  end

  @impl true
  def stream(_channel, _method, _request, _opts), do: {:ok, []}
end

defmodule Modal.Test.RaisingStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A stub whose `call/4` and `stream/4` raise. Used to verify that
  # `Modal.Client`'s dispatch task survives crashes: the caller's GenServer
  # call must receive `{:error, {:task_crashed, ...}}` promptly, `:inflight`
  # must reset, and `:max_concurrency` must not wedge.

  @impl true
  def call(_channel, _method, _request, _opts) do
    raise "intentional RaisingStub.call crash"
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    raise "intentional RaisingStub.stream crash"
  end
end

defmodule Modal.Test.SwitchableStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # Switches between :crash and :ok based on the value at
  # :persistent_term.get(:modal_switchable_mode, :crash). Used by the
  # task-crash regression suite to prove that subsequent successful RPCs
  # land cleanly after earlier crashing ones.

  @impl true
  def call(_channel, _method, _request, _opts) do
    case :persistent_term.get(:modal_switchable_mode, :crash) do
      :crash -> raise "intentional SwitchableStub.call crash"
      :ok -> {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
    end
  end

  @impl true
  def stream(_channel, _method, _request, _opts), do: {:ok, []}
end

defmodule Modal.Test.NetworkErrorStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A stub whose calls return `{:error, :closed}` (an opaque transport
  # failure). `Modal.Client.exec_rpc` wraps that into a Modal.Error with
  # kind :network, which trips `network_error?/1` in dispatch and casts
  # `:connection_failed`.

  @impl true
  def call(_channel, _method, _request, _opts) do
    {:error, :closed}
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    {:error, :closed}
  end
end

defmodule Modal.Test.BarrierNetworkErrorStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A NetworkErrorStub variant that synchronizes with a test barrier
  # before returning. Lets the reconnect-stampede regression test
  # guarantee that *all* N task bodies have captured the same epoch
  # before any of them fires a `:connection_failed` cast.
  #
  # The test stores its own pid at :persistent_term key
  # :modal_barrier_pid. Each task body, when it runs, sends
  # `{:arrived, self()}` to that pid and then `receive` waits for
  # `:release`. Once the test has collected N arrivals it broadcasts
  # `:release` to all arrived pids, and they each return the network
  # error, which then races into the `:connection_failed` cast queue.

  @impl true
  def call(_channel, _method, _request, _opts) do
    sync_with_barrier()
    {:error, :closed}
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    sync_with_barrier()
    {:error, :closed}
  end

  defp sync_with_barrier do
    case :persistent_term.get(:modal_barrier_pid, nil) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        send(pid, {:arrived, self()})

        receive do
          :release -> :ok
        after
          # 10s hard ceiling — release-not-sent is a test bug, not an
          # opportunity for the suite to hang.
          10_000 -> :ok
        end
    end
  end
end

defmodule Modal.Test.ScriptedStreamStub do
  @moduledoc false
  @behaviour Modal.ModalStub.Behaviour

  # A stub that yields a scripted sequence of stream items, set via
  # :persistent_term key :modal_scripted_stream_items. Each item is yielded
  # verbatim — including {:error, ...} tuples and surprise shapes — so the
  # client can be probed for how it handles mid-stream transport failures.
  #
  # call/4 isn't used by the streaming tests; left as a benign stub.

  @impl true
  def call(_channel, _method, _request, _opts) do
    {:ok, %Modal.Client.SandboxListResponse{sandboxes: []}}
  end

  @impl true
  def stream(_channel, _method, _request, _opts) do
    items = :persistent_term.get(:modal_scripted_stream_items, [])
    {:ok, items}
  end
end
