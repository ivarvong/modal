defmodule Modal.DataPlane.StdioStream do
  @moduledoc false

  @doc "Pull the next chunk. Returns `{:ok, binary}` or `:done`."
  def next(pid) do
    send(pid, {:pull, self()})

    receive do
      {:chunk, data} -> {:ok, data}
      :done -> :done
    after
      60_000 -> :done
    end
  end

  @doc false
  def start_link(channel, task_id, exec_id, auth_meta) do
    caller = self()

    pid =
      spawn_link(fn ->
        run(channel, task_id, exec_id, auth_meta, caller)
      end)

    {:ok, pid}
  end

  defp run(channel, task_id, exec_id, auth_meta, _caller) do
    alias Modal.TaskCommandRouter, as: TCR
    alias Modal.TaskCommandRouter.TaskCommandRouter.Stub, as: TCRStub

    request = %TCR.TaskExecStdioReadRequest{
      task_id: task_id,
      exec_id: exec_id,
      offset: 0
    }

    case TCRStub.task_exec_stdio_read(channel, request, metadata: auth_meta) do
      {:ok, enum} ->
        Enum.each(enum, fn
          {:ok, %{data: data}} when byte_size(data) > 0 ->
            receive do
              {:pull, from} -> send(from, {:chunk, data})
            end

          _ ->
            :ok
        end)

        receive do
          {:pull, from} -> send(from, :done)
        after
          5_000 -> :ok
        end

      {:error, _} ->
        receive do
          {:pull, from} -> send(from, :done)
        after
          5_000 -> :ok
        end
    end
  end
end
