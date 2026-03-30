defmodule Modal.TaskCommandRouter.TaskExecStderrConfig do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.task_command_router.TaskExecStderrConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TASK_EXEC_STDERR_CONFIG_DEVNULL, 0)
  field(:TASK_EXEC_STDERR_CONFIG_PIPE, 1)
  field(:TASK_EXEC_STDERR_CONFIG_STDOUT, 2)
end

defmodule Modal.TaskCommandRouter.TaskExecStdioFileDescriptor do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.task_command_router.TaskExecStdioFileDescriptor",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDOUT, 0)
  field(:TASK_EXEC_STDIO_FILE_DESCRIPTOR_STDERR, 1)
end

defmodule Modal.TaskCommandRouter.TaskExecStdoutConfig do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.task_command_router.TaskExecStdoutConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TASK_EXEC_STDOUT_CONFIG_DEVNULL, 0)
  field(:TASK_EXEC_STDOUT_CONFIG_PIPE, 1)
end

defmodule Modal.TaskCommandRouter.TaskContainerCreateRequest.EnvEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerCreateRequest.EnvEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.TaskCommandRouter.TaskContainerCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:container_name, 2, type: :string, json_name: "containerName")
  field(:image_id, 3, type: :string, json_name: "imageId")
  field(:args, 5, repeated: true, type: :string)

  field(:env, 6,
    repeated: true,
    type: Modal.TaskCommandRouter.TaskContainerCreateRequest.EnvEntry,
    map: true
  )

  field(:workdir, 7, type: :string)
  field(:secret_ids, 8, repeated: true, type: :string, json_name: "secretIds")
end

defmodule Modal.TaskCommandRouter.TaskContainerCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:container_id, 1, type: :string, json_name: "containerId")
  field(:container_name, 2, type: :string, json_name: "containerName")
end

defmodule Modal.TaskCommandRouter.TaskContainerGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:container_name, 2, type: :string, json_name: "containerName")
  field(:include_terminated, 3, type: :bool, json_name: "includeTerminated")
end

defmodule Modal.TaskCommandRouter.TaskContainerGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:container, 1, type: Modal.TaskCommandRouter.TaskContainerInfo)
end

defmodule Modal.TaskCommandRouter.TaskContainerInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:container_id, 1, type: :string, json_name: "containerId")
  field(:container_name, 2, type: :string, json_name: "containerName")
  field(:status, 3, type: :string)
  field(:result, 4, type: Modal.Client.GenericResult)
end

defmodule Modal.TaskCommandRouter.TaskContainerListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:include_terminated, 2, type: :bool, json_name: "includeTerminated")
end

defmodule Modal.TaskCommandRouter.TaskContainerListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:containers, 1, repeated: true, type: Modal.TaskCommandRouter.TaskContainerInfo)
end

defmodule Modal.TaskCommandRouter.TaskContainerTerminateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerTerminateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:container_id, 2, type: :string, json_name: "containerId")
end

defmodule Modal.TaskCommandRouter.TaskContainerTerminateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerTerminateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.TaskCommandRouter.TaskContainerWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:container_id, 2, type: :string, json_name: "containerId")
  field(:timeout, 3, type: :float)
end

defmodule Modal.TaskCommandRouter.TaskContainerWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskContainerWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
end

defmodule Modal.TaskCommandRouter.TaskExecPollRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecPollRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:exec_id, 2, type: :string, json_name: "execId")
end

defmodule Modal.TaskCommandRouter.TaskExecPollResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecPollResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:exit_status, 0)

  field(:code, 1, type: :int32, oneof: 0)
  field(:signal, 2, type: :int32, oneof: 0)
end

defmodule Modal.TaskCommandRouter.TaskExecStartRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStartRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:exec_id, 2, type: :string, json_name: "execId")
  field(:command_args, 3, repeated: true, type: :string, json_name: "commandArgs")

  field(:stdout_config, 4,
    type: Modal.TaskCommandRouter.TaskExecStdoutConfig,
    json_name: "stdoutConfig",
    enum: true
  )

  field(:stderr_config, 5,
    type: Modal.TaskCommandRouter.TaskExecStderrConfig,
    json_name: "stderrConfig",
    enum: true
  )

  field(:timeout_secs, 6, proto3_optional: true, type: :uint32, json_name: "timeoutSecs")
  field(:workdir, 7, proto3_optional: true, type: :string)
  field(:secret_ids, 8, repeated: true, type: :string, json_name: "secretIds")
  field(:pty_info, 9, proto3_optional: true, type: Modal.Client.PTYInfo, json_name: "ptyInfo")
  field(:runtime_debug, 10, type: :bool, json_name: "runtimeDebug")
  field(:container_id, 11, type: :string, json_name: "containerId")
end

defmodule Modal.TaskCommandRouter.TaskExecStartResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStartResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.TaskCommandRouter.TaskExecStdinWriteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStdinWriteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:exec_id, 2, type: :string, json_name: "execId")
  field(:offset, 3, type: :uint64)
  field(:data, 4, type: :bytes)
  field(:eof, 5, type: :bool)
end

defmodule Modal.TaskCommandRouter.TaskExecStdinWriteResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStdinWriteResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.TaskCommandRouter.TaskExecStdioReadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStdioReadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:exec_id, 2, type: :string, json_name: "execId")
  field(:offset, 3, type: :uint64)

  field(:file_descriptor, 4,
    type: Modal.TaskCommandRouter.TaskExecStdioFileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )
end

defmodule Modal.TaskCommandRouter.TaskExecStdioReadResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecStdioReadResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:data, 1, type: :bytes)
end

defmodule Modal.TaskCommandRouter.TaskExecWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:exec_id, 2, type: :string, json_name: "execId")
end

defmodule Modal.TaskCommandRouter.TaskExecWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskExecWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:exit_status, 0)

  field(:code, 1, type: :int32, oneof: 0)
  field(:signal, 2, type: :int32, oneof: 0)
end

defmodule Modal.TaskCommandRouter.TaskMountDirectoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskMountDirectoryRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:path, 2, type: :bytes)
  field(:image_id, 3, type: :string, json_name: "imageId")
end

defmodule Modal.TaskCommandRouter.TaskSnapshotDirectoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskSnapshotDirectoryRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:path, 2, type: :bytes)
end

defmodule Modal.TaskCommandRouter.TaskSnapshotDirectoryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.task_command_router.TaskSnapshotDirectoryResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
end

defmodule Modal.TaskCommandRouter.TaskCommandRouter.Service do
  @moduledoc false

  use GRPC.Service,
    name: "modal.task_command_router.TaskCommandRouter",
    protoc_gen_elixir_version: "0.16.0"

  rpc(
    :TaskContainerCreate,
    Modal.TaskCommandRouter.TaskContainerCreateRequest,
    Modal.TaskCommandRouter.TaskContainerCreateResponse
  )

  rpc(
    :TaskContainerGet,
    Modal.TaskCommandRouter.TaskContainerGetRequest,
    Modal.TaskCommandRouter.TaskContainerGetResponse
  )

  rpc(
    :TaskContainerList,
    Modal.TaskCommandRouter.TaskContainerListRequest,
    Modal.TaskCommandRouter.TaskContainerListResponse
  )

  rpc(
    :TaskContainerTerminate,
    Modal.TaskCommandRouter.TaskContainerTerminateRequest,
    Modal.TaskCommandRouter.TaskContainerTerminateResponse
  )

  rpc(
    :TaskContainerWait,
    Modal.TaskCommandRouter.TaskContainerWaitRequest,
    Modal.TaskCommandRouter.TaskContainerWaitResponse
  )

  rpc(
    :TaskExecPoll,
    Modal.TaskCommandRouter.TaskExecPollRequest,
    Modal.TaskCommandRouter.TaskExecPollResponse
  )

  rpc(
    :TaskExecStart,
    Modal.TaskCommandRouter.TaskExecStartRequest,
    Modal.TaskCommandRouter.TaskExecStartResponse
  )

  rpc(
    :TaskExecStdinWrite,
    Modal.TaskCommandRouter.TaskExecStdinWriteRequest,
    Modal.TaskCommandRouter.TaskExecStdinWriteResponse
  )

  rpc(
    :TaskExecStdioRead,
    Modal.TaskCommandRouter.TaskExecStdioReadRequest,
    stream(Modal.TaskCommandRouter.TaskExecStdioReadResponse)
  )

  rpc(
    :TaskExecWait,
    Modal.TaskCommandRouter.TaskExecWaitRequest,
    Modal.TaskCommandRouter.TaskExecWaitResponse
  )

  rpc(
    :TaskMountDirectory,
    Modal.TaskCommandRouter.TaskMountDirectoryRequest,
    Google.Protobuf.Empty
  )

  rpc(
    :TaskSnapshotDirectory,
    Modal.TaskCommandRouter.TaskSnapshotDirectoryRequest,
    Modal.TaskCommandRouter.TaskSnapshotDirectoryResponse
  )
end

defmodule Modal.TaskCommandRouter.TaskCommandRouter.Stub do
  @moduledoc false

  use GRPC.Stub, service: Modal.TaskCommandRouter.TaskCommandRouter.Service
end
