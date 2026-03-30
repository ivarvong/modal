defmodule Modal.Client.AppDeployVisibility do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.AppDeployVisibility",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:APP_DEPLOY_VISIBILITY_UNSPECIFIED, 0)
  field(:APP_DEPLOY_VISIBILITY_WORKSPACE, 1)
  field(:APP_DEPLOY_VISIBILITY_PUBLIC, 2)
end

defmodule Modal.Client.AppDisconnectReason do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.AppDisconnectReason",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:APP_DISCONNECT_REASON_UNSPECIFIED, 0)
  field(:APP_DISCONNECT_REASON_LOCAL_EXCEPTION, 1)
  field(:APP_DISCONNECT_REASON_KEYBOARD_INTERRUPT, 2)
  field(:APP_DISCONNECT_REASON_ENTRYPOINT_COMPLETED, 3)
  field(:APP_DISCONNECT_REASON_DEPLOYMENT_EXCEPTION, 4)
  field(:APP_DISCONNECT_REASON_REMOTE_EXCEPTION, 5)
end

defmodule Modal.Client.AppState do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.AppState",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:APP_STATE_UNSPECIFIED, 0)
  field(:APP_STATE_EPHEMERAL, 1)
  field(:APP_STATE_DETACHED, 2)
  field(:APP_STATE_DEPLOYED, 3)
  field(:APP_STATE_STOPPING, 4)
  field(:APP_STATE_STOPPED, 5)
  field(:APP_STATE_INITIALIZING, 6)
  field(:APP_STATE_DISABLED, 7)
  field(:APP_STATE_DETACHED_DISCONNECTED, 8)
  field(:APP_STATE_DERIVED, 9)
end

defmodule Modal.Client.AppStopSource do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.AppStopSource",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:APP_STOP_SOURCE_UNSPECIFIED, 0)
  field(:APP_STOP_SOURCE_CLI, 1)
  field(:APP_STOP_SOURCE_PYTHON_CLIENT, 2)
  field(:APP_STOP_SOURCE_WEB, 3)
end

defmodule Modal.Client.CertificateStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.CertificateStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:CERTIFICATE_STATUS_PENDING, 0)
  field(:CERTIFICATE_STATUS_ISSUED, 1)
  field(:CERTIFICATE_STATUS_FAILED, 2)
  field(:CERTIFICATE_STATUS_REVOKED, 3)
end

defmodule Modal.Client.CheckpointStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.CheckpointStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:CHECKPOINT_STATUS_UNSPECIFIED, 0)
  field(:CHECKPOINT_STATUS_PENDING, 1)
  field(:CHECKPOINT_STATUS_PROCESSING, 2)
  field(:CHECKPOINT_STATUS_READY, 3)
  field(:CHECKPOINT_STATUS_FAILED, 4)
end

defmodule Modal.Client.ClientType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ClientType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:CLIENT_TYPE_UNSPECIFIED, 0)
  field(:CLIENT_TYPE_CLIENT, 1)
  field(:CLIENT_TYPE_WORKER, 2)
  field(:CLIENT_TYPE_CONTAINER, 3)
  field(:CLIENT_TYPE_WEB_SERVER, 5)
  field(:CLIENT_TYPE_NOTEBOOK_KERNEL, 6)
  field(:CLIENT_TYPE_LIBMODAL, 7)
  field(:CLIENT_TYPE_LIBMODAL_JS, 8)
  field(:CLIENT_TYPE_LIBMODAL_GO, 9)
end

defmodule Modal.Client.CloudProvider do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.CloudProvider",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:CLOUD_PROVIDER_UNSPECIFIED, 0)
  field(:CLOUD_PROVIDER_AWS, 1)
  field(:CLOUD_PROVIDER_GCP, 2)
  field(:CLOUD_PROVIDER_AUTO, 3)
  field(:CLOUD_PROVIDER_OCI, 4)
end

defmodule Modal.Client.DNSRecordType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.DNSRecordType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:DNS_RECORD_TYPE_A, 0)
  field(:DNS_RECORD_TYPE_TXT, 1)
  field(:DNS_RECORD_TYPE_CNAME, 2)
end

defmodule Modal.Client.DataFormat do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.DataFormat",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:DATA_FORMAT_UNSPECIFIED, 0)
  field(:DATA_FORMAT_PICKLE, 1)
  field(:DATA_FORMAT_ASGI, 2)
  field(:DATA_FORMAT_GENERATOR_DONE, 3)
  field(:DATA_FORMAT_CBOR, 4)
end

defmodule Modal.Client.DeploymentNamespace do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.DeploymentNamespace",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:DEPLOYMENT_NAMESPACE_UNSPECIFIED, 0)
  field(:DEPLOYMENT_NAMESPACE_WORKSPACE, 1)
  field(:DEPLOYMENT_NAMESPACE_GLOBAL, 3)
end

defmodule Modal.Client.ExecOutputOption do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ExecOutputOption",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:EXEC_OUTPUT_OPTION_UNSPECIFIED, 0)
  field(:EXEC_OUTPUT_OPTION_DEVNULL, 1)
  field(:EXEC_OUTPUT_OPTION_PIPE, 2)
  field(:EXEC_OUTPUT_OPTION_STDOUT, 3)
end

defmodule Modal.Client.FileDescriptor do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.FileDescriptor",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:FILE_DESCRIPTOR_UNSPECIFIED, 0)
  field(:FILE_DESCRIPTOR_STDOUT, 1)
  field(:FILE_DESCRIPTOR_STDERR, 2)
  field(:FILE_DESCRIPTOR_INFO, 3)
end

defmodule Modal.Client.FunctionCallInvocationType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.FunctionCallInvocationType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:FUNCTION_CALL_INVOCATION_TYPE_UNSPECIFIED, 0)
  field(:FUNCTION_CALL_INVOCATION_TYPE_SYNC_LEGACY, 1)
  field(:FUNCTION_CALL_INVOCATION_TYPE_ASYNC_LEGACY, 2)
  field(:FUNCTION_CALL_INVOCATION_TYPE_ASYNC, 3)
  field(:FUNCTION_CALL_INVOCATION_TYPE_SYNC, 4)
end

defmodule Modal.Client.FunctionCallType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.FunctionCallType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:FUNCTION_CALL_TYPE_UNSPECIFIED, 0)
  field(:FUNCTION_CALL_TYPE_UNARY, 1)
  field(:FUNCTION_CALL_TYPE_MAP, 2)
end

defmodule Modal.Client.GPUType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.GPUType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:GPU_TYPE_UNSPECIFIED, 0)
  field(:GPU_TYPE_T4, 1)
  field(:GPU_TYPE_A100, 2)
  field(:GPU_TYPE_A10G, 3)
  field(:GPU_TYPE_ANY, 4)
  field(:GPU_TYPE_A100_80GB, 8)
  field(:GPU_TYPE_L4, 9)
  field(:GPU_TYPE_H100, 10)
  field(:GPU_TYPE_L40S, 11)
  field(:GPU_TYPE_H200, 12)
end

defmodule Modal.Client.ObjectCreationType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ObjectCreationType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:OBJECT_CREATION_TYPE_UNSPECIFIED, 0)
  field(:OBJECT_CREATION_TYPE_CREATE_IF_MISSING, 1)
  field(:OBJECT_CREATION_TYPE_CREATE_FAIL_IF_EXISTS, 2)
  field(:OBJECT_CREATION_TYPE_CREATE_OVERWRITE_IF_EXISTS, 3)
  field(:OBJECT_CREATION_TYPE_ANONYMOUS_OWNED_BY_APP, 4)
  field(:OBJECT_CREATION_TYPE_EPHEMERAL, 5)
end

defmodule Modal.Client.ParameterType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ParameterType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:PARAM_TYPE_UNSPECIFIED, 0)
  field(:PARAM_TYPE_STRING, 1)
  field(:PARAM_TYPE_INT, 2)
  field(:PARAM_TYPE_PICKLE, 3)
  field(:PARAM_TYPE_BYTES, 4)
  field(:PARAM_TYPE_UNKNOWN, 5)
  field(:PARAM_TYPE_LIST, 6)
  field(:PARAM_TYPE_DICT, 7)
  field(:PARAM_TYPE_NONE, 8)
  field(:PARAM_TYPE_BOOL, 9)
end

defmodule Modal.Client.ProgressType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ProgressType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:IMAGE_SNAPSHOT_UPLOAD, 0)
  field(:FUNCTION_QUEUED, 1)
end

defmodule Modal.Client.ProxyIpStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ProxyIpStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:PROXY_IP_STATUS_UNSPECIFIED, 0)
  field(:PROXY_IP_STATUS_CREATING, 1)
  field(:PROXY_IP_STATUS_ONLINE, 2)
  field(:PROXY_IP_STATUS_TERMINATED, 3)
  field(:PROXY_IP_STATUS_UNHEALTHY, 4)
end

defmodule Modal.Client.ProxyType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ProxyType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:PROXY_TYPE_UNSPECIFIED, 0)
  field(:PROXY_TYPE_LEGACY, 1)
  field(:PROXY_TYPE_VPROX, 2)
end

defmodule Modal.Client.RateLimitInterval do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.RateLimitInterval",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:RATE_LIMIT_INTERVAL_UNSPECIFIED, 0)
  field(:RATE_LIMIT_INTERVAL_SECOND, 1)
  field(:RATE_LIMIT_INTERVAL_MINUTE, 2)
end

defmodule Modal.Client.RegistryAuthType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.RegistryAuthType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:REGISTRY_AUTH_TYPE_UNSPECIFIED, 0)
  field(:REGISTRY_AUTH_TYPE_AWS, 1)
  field(:REGISTRY_AUTH_TYPE_GCP, 2)
  field(:REGISTRY_AUTH_TYPE_PUBLIC, 3)
  field(:REGISTRY_AUTH_TYPE_STATIC_CREDS, 4)
end

defmodule Modal.Client.SeekWhence do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.SeekWhence",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:SEEK_SET, 0)
  field(:SEEK_CUR, 1)
  field(:SEEK_END, 2)
end

defmodule Modal.Client.SystemErrorCode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.SystemErrorCode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:SYSTEM_ERROR_CODE_UNSPECIFIED, 0)
  field(:SYSTEM_ERROR_CODE_PERM, 1)
  field(:SYSTEM_ERROR_CODE_NOENT, 2)
  field(:SYSTEM_ERROR_CODE_IO, 5)
  field(:SYSTEM_ERROR_CODE_NXIO, 6)
  field(:SYSTEM_ERROR_CODE_NOMEM, 12)
  field(:SYSTEM_ERROR_CODE_ACCES, 13)
  field(:SYSTEM_ERROR_CODE_EXIST, 17)
  field(:SYSTEM_ERROR_CODE_NOTDIR, 20)
  field(:SYSTEM_ERROR_CODE_ISDIR, 21)
  field(:SYSTEM_ERROR_CODE_INVAL, 22)
  field(:SYSTEM_ERROR_CODE_MFILE, 24)
  field(:SYSTEM_ERROR_CODE_FBIG, 27)
  field(:SYSTEM_ERROR_CODE_NOSPC, 28)
end

defmodule Modal.Client.TaskSnapshotBehavior do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.TaskSnapshotBehavior",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TASK_SNAPSHOT_BEHAVIOR_UNSPECIFIED, 0)
  field(:TASK_SNAPSHOT_BEHAVIOR_SNAPSHOT, 1)
  field(:TASK_SNAPSHOT_BEHAVIOR_RESTORE, 2)
  field(:TASK_SNAPSHOT_BEHAVIOR_NONE, 3)
end

defmodule Modal.Client.TaskState do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.TaskState",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TASK_STATE_UNSPECIFIED, 0)
  field(:TASK_STATE_CREATED, 6)
  field(:TASK_STATE_QUEUED, 1)
  field(:TASK_STATE_WORKER_ASSIGNED, 2)
  field(:TASK_STATE_LOADING_IMAGE, 3)
  field(:TASK_STATE_ACTIVE, 4)
  field(:TASK_STATE_COMPLETED, 5)
  field(:TASK_STATE_CREATING_CONTAINER, 7)
  field(:TASK_STATE_IDLE, 8)
  field(:TASK_STATE_PREEMPTIBLE, 9)
  field(:TASK_STATE_PREEMPTED, 10)
  field(:TASK_STATE_LOADING_CHECKPOINT_IMAGE, 11)
end

defmodule Modal.Client.TunnelType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.TunnelType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:TUNNEL_TYPE_UNSPECIFIED, 0)
  field(:TUNNEL_TYPE_H2, 1)
end

defmodule Modal.Client.VolumeFsVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.VolumeFsVersion",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:VOLUME_FS_VERSION_UNSPECIFIED, 0)
  field(:VOLUME_FS_VERSION_V1, 1)
  field(:VOLUME_FS_VERSION_V2, 2)
end

defmodule Modal.Client.WebhookAsyncMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.WebhookAsyncMode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:WEBHOOK_ASYNC_MODE_UNSPECIFIED, 0)
  field(:WEBHOOK_ASYNC_MODE_DISABLED, 2)
  field(:WEBHOOK_ASYNC_MODE_TRIGGER, 3)
  field(:WEBHOOK_ASYNC_MODE_AUTO, 4)
end

defmodule Modal.Client.WebhookType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.WebhookType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:WEBHOOK_TYPE_UNSPECIFIED, 0)
  field(:WEBHOOK_TYPE_ASGI_APP, 1)
  field(:WEBHOOK_TYPE_FUNCTION, 2)
  field(:WEBHOOK_TYPE_WSGI_APP, 3)
  field(:WEBHOOK_TYPE_WEB_SERVER, 4)
end

defmodule Modal.Client.ClassParameterInfo.ParameterSerializationFormat do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.ClassParameterInfo.ParameterSerializationFormat",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:PARAM_SERIALIZATION_FORMAT_UNSPECIFIED, 0)
  field(:PARAM_SERIALIZATION_FORMAT_PICKLE, 1)
  field(:PARAM_SERIALIZATION_FORMAT_PROTO, 2)
end

defmodule Modal.Client.CloudBucketMount.BucketType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.CloudBucketMount.BucketType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:UNSPECIFIED, 0)
  field(:S3, 1)
  field(:R2, 2)
  field(:GCP, 3)
end

defmodule Modal.Client.CloudBucketMount.MetadataTTLType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.CloudBucketMount.MetadataTTLType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:METADATA_TTL_TYPE_UNSPECIFIED, 0)
  field(:METADATA_TTL_TYPE_MINIMAL, 1)
  field(:METADATA_TTL_TYPE_INDEFINITE, 2)
end

defmodule Modal.Client.FileEntry.FileType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.FileEntry.FileType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:UNSPECIFIED, 0)
  field(:FILE, 1)
  field(:DIRECTORY, 2)
  field(:SYMLINK, 3)
  field(:FIFO, 4)
  field(:SOCKET, 5)
end

defmodule Modal.Client.Function.DefinitionType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.Function.DefinitionType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:DEFINITION_TYPE_UNSPECIFIED, 0)
  field(:DEFINITION_TYPE_SERIALIZED, 1)
  field(:DEFINITION_TYPE_FILE, 2)
end

defmodule Modal.Client.Function.FunctionType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.Function.FunctionType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:FUNCTION_TYPE_UNSPECIFIED, 0)
  field(:FUNCTION_TYPE_GENERATOR, 1)
  field(:FUNCTION_TYPE_FUNCTION, 2)
end

defmodule Modal.Client.FunctionSchema.FunctionSchemaType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.FunctionSchema.FunctionSchemaType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:FUNCTION_SCHEMA_UNSPECIFIED, 0)
  field(:FUNCTION_SCHEMA_V1, 1)
end

defmodule Modal.Client.GenericResult.GenericStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.GenericResult.GenericStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:GENERIC_STATUS_UNSPECIFIED, 0)
  field(:GENERIC_STATUS_SUCCESS, 1)
  field(:GENERIC_STATUS_FAILURE, 2)
  field(:GENERIC_STATUS_TERMINATED, 3)
  field(:GENERIC_STATUS_TIMEOUT, 4)
  field(:GENERIC_STATUS_INIT_FAILURE, 5)
  field(:GENERIC_STATUS_INTERNAL_FAILURE, 6)
  field(:GENERIC_STATUS_IDLE_TIMEOUT, 7)
end

defmodule Modal.Client.NetworkAccess.NetworkAccessType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.NetworkAccess.NetworkAccessType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:UNSPECIFIED, 0)
  field(:OPEN, 1)
  field(:BLOCKED, 2)
  field(:ALLOWLIST, 3)
end

defmodule Modal.Client.PTYInfo.PTYType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.PTYInfo.PTYType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:PTY_TYPE_UNSPECIFIED, 0)
  field(:PTY_TYPE_FUNCTION, 1)
  field(:PTY_TYPE_SHELL, 2)
end

defmodule Modal.Client.SandboxRestoreRequest.SandboxNameOverrideType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.SandboxRestoreRequest.SandboxNameOverrideType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:SANDBOX_NAME_OVERRIDE_TYPE_UNSPECIFIED, 0)
  field(:SANDBOX_NAME_OVERRIDE_TYPE_NONE, 1)
  field(:SANDBOX_NAME_OVERRIDE_TYPE_STRING, 2)
end

defmodule Modal.Client.Warning.WarningType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "modal.client.Warning.WarningType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:WARNING_TYPE_UNSPECIFIED, 0)
  field(:WARNING_TYPE_CLIENT_DEPRECATION, 1)
  field(:WARNING_TYPE_RESOURCE_LIMIT, 2)
  field(:WARNING_TYPE_FUNCTION_CONFIGURATION, 3)
end

defmodule Modal.Client.AppClientDisconnectRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppClientDisconnectRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:reason, 2, type: Modal.Client.AppDisconnectReason, enum: true)
  field(:exception, 3, type: :string)
end

defmodule Modal.Client.AppCountLogsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCountLogsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:task_id, 2, type: :string, json_name: "taskId")
  field(:function_id, 3, type: :string, json_name: "functionId")
  field(:function_call_id, 4, type: :string, json_name: "functionCallId")
  field(:sandbox_id, 5, type: :string, json_name: "sandboxId")
  field(:search_text, 6, type: :string, json_name: "searchText")
  field(:since, 7, type: Google.Protobuf.Timestamp)
  field(:until, 8, type: Google.Protobuf.Timestamp)
  field(:bucket_secs, 9, type: :uint32, json_name: "bucketSecs")
  field(:source, 10, type: Modal.Client.FileDescriptor, enum: true)
end

defmodule Modal.Client.AppCountLogsResponse.LogBucket do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCountLogsResponse.LogBucket",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:bucket_start_at, 1, type: Google.Protobuf.Timestamp, json_name: "bucketStartAt")
  field(:stdout_logs, 2, type: :uint64, json_name: "stdoutLogs")
  field(:stderr_logs, 3, type: :uint64, json_name: "stderrLogs")
  field(:system_logs, 4, type: :uint64, json_name: "systemLogs")
end

defmodule Modal.Client.AppCountLogsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCountLogsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:buckets, 2, repeated: true, type: Modal.Client.AppCountLogsResponse.LogBucket)
end

defmodule Modal.Client.AppCreateRequest.TagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCreateRequest.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:client_id, 1, type: :string, json_name: "clientId")
  field(:description, 2, type: :string)
  field(:environment_name, 5, type: :string, json_name: "environmentName")
  field(:app_state, 6, type: Modal.Client.AppState, json_name: "appState", enum: true)
  field(:tags, 7, repeated: true, type: Modal.Client.AppCreateRequest.TagsEntry, map: true)
end

defmodule Modal.Client.AppCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:app_page_url, 2, type: :string, json_name: "appPageUrl")
  field(:app_logs_url, 3, type: :string, json_name: "appLogsUrl")
end

defmodule Modal.Client.AppDeployRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppDeployRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:name, 3, type: :string)
  field(:object_entity, 4, type: :string, json_name: "objectEntity")
  field(:visibility, 5, type: Modal.Client.AppDeployVisibility, enum: true)
  field(:tag, 6, type: :string)
end

defmodule Modal.Client.AppDeployResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppDeployResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)
end

defmodule Modal.Client.AppDeploymentHistory do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppDeploymentHistory",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:version, 2, type: :uint32)
  field(:client_version, 3, type: :string, json_name: "clientVersion")
  field(:deployed_at, 4, type: :double, json_name: "deployedAt")
  field(:deployed_by, 5, type: :string, json_name: "deployedBy")
  field(:deployed_by_avatar_url, 9, type: :string, json_name: "deployedByAvatarUrl")
  field(:tag, 6, type: :string)
  field(:rollback_version, 7, type: :uint32, json_name: "rollbackVersion")
  field(:rollback_allowed, 8, type: :bool, json_name: "rollbackAllowed")

  field(:commit_info, 10,
    proto3_optional: true,
    type: Modal.Client.CommitInfo,
    json_name: "commitInfo"
  )
end

defmodule Modal.Client.AppDeploymentHistoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppDeploymentHistoryRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppDeploymentHistoryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppDeploymentHistoryResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_deployment_histories, 1,
    repeated: true,
    type: Modal.Client.AppDeploymentHistory,
    json_name: "appDeploymentHistories"
  )
end

defmodule Modal.Client.AppFetchLogsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppFetchLogsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:since, 2, type: Google.Protobuf.Timestamp)
  field(:until, 3, type: Google.Protobuf.Timestamp)
  field(:limit, 4, type: :uint32)
  field(:source, 5, type: Modal.Client.FileDescriptor, enum: true)
  field(:function_id, 6, type: :string, json_name: "functionId")
  field(:function_call_id, 7, type: :string, json_name: "functionCallId")
  field(:task_id, 8, type: :string, json_name: "taskId")
  field(:sandbox_id, 9, type: :string, json_name: "sandboxId")
  field(:search_text, 10, type: :string, json_name: "searchText")
end

defmodule Modal.Client.AppFetchLogsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppFetchLogsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:batches, 1, repeated: true, type: Modal.Client.TaskLogsBatch)
end

defmodule Modal.Client.AppGetByDeploymentNameRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetByDeploymentNameRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 2, type: :string)
  field(:environment_name, 4, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.AppGetByDeploymentNameResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetByDeploymentNameResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppGetLayoutRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetLayoutRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppGetLayoutResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetLayoutResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_layout, 1, type: Modal.Client.AppLayout, json_name: "appLayout")
end

defmodule Modal.Client.AppGetLogsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetLogsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:timeout, 2, type: :float)
  field(:last_entry_id, 4, type: :string, json_name: "lastEntryId")
  field(:function_id, 5, type: :string, json_name: "functionId")
  field(:parametrized_function_id, 11, type: :string, json_name: "parametrizedFunctionId")
  field(:input_id, 6, type: :string, json_name: "inputId")
  field(:task_id, 7, type: :string, json_name: "taskId")
  field(:function_call_id, 9, type: :string, json_name: "functionCallId")

  field(:file_descriptor, 8,
    type: Modal.Client.FileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )

  field(:sandbox_id, 10, type: :string, json_name: "sandboxId")
  field(:search_text, 12, type: :string, json_name: "searchText")
end

defmodule Modal.Client.AppGetObjectsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetObjectsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:tag, 1, type: :string)
  field(:object, 6, type: Modal.Client.Object)
end

defmodule Modal.Client.AppGetObjectsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetObjectsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:include_unindexed, 2, type: :bool, json_name: "includeUnindexed")
  field(:only_class_function, 3, type: :bool, json_name: "onlyClassFunction")
end

defmodule Modal.Client.AppGetObjectsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetObjectsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 2, repeated: true, type: Modal.Client.AppGetObjectsItem)
end

defmodule Modal.Client.AppGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_name, 1, type: :string, json_name: "appName")
  field(:environment_name, 2, type: :string, json_name: "environmentName")

  field(:object_creation_type, 3,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )
end

defmodule Modal.Client.AppGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppGetTagsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetTagsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppGetTagsResponse.TagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetTagsResponse.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppGetTagsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppGetTagsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:tags, 1, repeated: true, type: Modal.Client.AppGetTagsResponse.TagsEntry, map: true)
end

defmodule Modal.Client.AppHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppLayout.FunctionIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppLayout.FunctionIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppLayout.ClassIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppLayout.ClassIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppLayout do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppLayout",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:objects, 1, repeated: true, type: Modal.Client.Object)

  field(:function_ids, 2,
    repeated: true,
    type: Modal.Client.AppLayout.FunctionIdsEntry,
    json_name: "functionIds",
    map: true
  )

  field(:class_ids, 3,
    repeated: true,
    type: Modal.Client.AppLayout.ClassIdsEntry,
    json_name: "classIds",
    map: true
  )
end

defmodule Modal.Client.AppListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.AppListResponse.AppListItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppListResponse.AppListItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:description, 3, type: :string)
  field(:state, 4, type: Modal.Client.AppState, enum: true)
  field(:created_at, 5, type: :double, json_name: "createdAt")
  field(:stopped_at, 6, type: :double, json_name: "stoppedAt")
  field(:n_running_tasks, 8, type: :int32, json_name: "nRunningTasks")
  field(:name, 10, type: :string)
end

defmodule Modal.Client.AppListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:apps, 1, repeated: true, type: Modal.Client.AppListResponse.AppListItem)
end

defmodule Modal.Client.AppLookupRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppLookupRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_name, 2, type: :string, json_name: "appName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.AppLookupResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppLookupResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
end

defmodule Modal.Client.AppPublishRequest.FunctionIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishRequest.FunctionIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppPublishRequest.ClassIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishRequest.ClassIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppPublishRequest.DefinitionIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishRequest.DefinitionIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppPublishRequest.TagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishRequest.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppPublishRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:name, 2, type: :string)
  field(:deployment_tag, 3, type: :string, json_name: "deploymentTag")
  field(:app_state, 4, type: Modal.Client.AppState, json_name: "appState", enum: true)

  field(:function_ids, 5,
    repeated: true,
    type: Modal.Client.AppPublishRequest.FunctionIdsEntry,
    json_name: "functionIds",
    map: true
  )

  field(:class_ids, 6,
    repeated: true,
    type: Modal.Client.AppPublishRequest.ClassIdsEntry,
    json_name: "classIds",
    map: true
  )

  field(:definition_ids, 7,
    repeated: true,
    type: Modal.Client.AppPublishRequest.DefinitionIdsEntry,
    json_name: "definitionIds",
    map: true
  )

  field(:rollback_version, 8, type: :uint32, json_name: "rollbackVersion")
  field(:client_version, 9, type: :string, json_name: "clientVersion")
  field(:commit_info, 10, type: Modal.Client.CommitInfo, json_name: "commitInfo")
  field(:tags, 11, repeated: true, type: Modal.Client.AppPublishRequest.TagsEntry, map: true)
end

defmodule Modal.Client.AppPublishResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppPublishResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)

  field(:server_warnings, 3,
    repeated: true,
    type: Modal.Client.Warning,
    json_name: "serverWarnings"
  )

  field(:deployed_at, 4, type: :double, json_name: "deployedAt")
end

defmodule Modal.Client.AppRollbackRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppRollbackRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:version, 2, type: :int32)
end

defmodule Modal.Client.AppSetObjectsRequest.IndexedObjectIdsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppSetObjectsRequest.IndexedObjectIdsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppSetObjectsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppSetObjectsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")

  field(:indexed_object_ids, 2,
    repeated: true,
    type: Modal.Client.AppSetObjectsRequest.IndexedObjectIdsEntry,
    json_name: "indexedObjectIds",
    map: true
  )

  field(:client_id, 3, type: :string, json_name: "clientId")
  field(:unindexed_object_ids, 4, repeated: true, type: :string, json_name: "unindexedObjectIds")
  field(:new_app_state, 5, type: Modal.Client.AppState, json_name: "newAppState", enum: true)
end

defmodule Modal.Client.AppSetTagsRequest.TagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppSetTagsRequest.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.AppSetTagsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppSetTagsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:tags, 2, repeated: true, type: Modal.Client.AppSetTagsRequest.TagsEntry, map: true)
end

defmodule Modal.Client.AppStopRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AppStopRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:source, 2, type: Modal.Client.AppStopSource, enum: true)
end

defmodule Modal.Client.Asgi.Http do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.Http",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:http_version, 1, type: :string, json_name: "httpVersion")
  field(:method, 2, type: :string)
  field(:scheme, 3, type: :string)
  field(:path, 4, type: :string)
  field(:query_string, 5, type: :bytes, json_name: "queryString")
  field(:headers, 6, repeated: true, type: :bytes)
  field(:client_host, 7, proto3_optional: true, type: :string, json_name: "clientHost")
  field(:client_port, 8, proto3_optional: true, type: :uint32, json_name: "clientPort")
end

defmodule Modal.Client.Asgi.HttpRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.HttpRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:body, 1, type: :bytes)
  field(:more_body, 2, type: :bool, json_name: "moreBody")
end

defmodule Modal.Client.Asgi.HttpResponseStart do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.HttpResponseStart",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:status, 1, type: :uint32)
  field(:headers, 2, repeated: true, type: :bytes)
  field(:trailers, 3, type: :bool)
end

defmodule Modal.Client.Asgi.HttpResponseBody do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.HttpResponseBody",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:body, 1, type: :bytes)
  field(:more_body, 2, type: :bool, json_name: "moreBody")
end

defmodule Modal.Client.Asgi.HttpResponseTrailers do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.HttpResponseTrailers",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:headers, 1, repeated: true, type: :bytes)
  field(:more_trailers, 2, type: :bool, json_name: "moreTrailers")
end

defmodule Modal.Client.Asgi.HttpDisconnect do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.HttpDisconnect",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.Asgi.Websocket do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.Websocket",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:http_version, 1, type: :string, json_name: "httpVersion")
  field(:scheme, 2, type: :string)
  field(:path, 3, type: :string)
  field(:query_string, 4, type: :bytes, json_name: "queryString")
  field(:headers, 5, repeated: true, type: :bytes)
  field(:client_host, 6, proto3_optional: true, type: :string, json_name: "clientHost")
  field(:client_port, 7, proto3_optional: true, type: :uint32, json_name: "clientPort")
  field(:subprotocols, 8, repeated: true, type: :string)
end

defmodule Modal.Client.Asgi.WebsocketConnect do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketConnect",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.Asgi.WebsocketAccept do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketAccept",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:subprotocol, 1, proto3_optional: true, type: :string)
  field(:headers, 2, repeated: true, type: :bytes)
end

defmodule Modal.Client.Asgi.WebsocketReceive do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketReceive",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:content, 0)

  field(:bytes, 1, type: :bytes, oneof: 0)
  field(:text, 2, type: :string, oneof: 0)
end

defmodule Modal.Client.Asgi.WebsocketSend do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketSend",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:content, 0)

  field(:bytes, 1, type: :bytes, oneof: 0)
  field(:text, 2, type: :string, oneof: 0)
end

defmodule Modal.Client.Asgi.WebsocketDisconnect do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketDisconnect",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:code, 1, proto3_optional: true, type: :uint32)
end

defmodule Modal.Client.Asgi.WebsocketClose do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi.WebsocketClose",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:code, 1, proto3_optional: true, type: :uint32)
  field(:reason, 2, type: :string)
end

defmodule Modal.Client.Asgi do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Asgi",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:type, 0)

  field(:http, 1, type: Modal.Client.Asgi.Http, oneof: 0)
  field(:http_request, 2, type: Modal.Client.Asgi.HttpRequest, json_name: "httpRequest", oneof: 0)

  field(:http_response_start, 3,
    type: Modal.Client.Asgi.HttpResponseStart,
    json_name: "httpResponseStart",
    oneof: 0
  )

  field(:http_response_body, 4,
    type: Modal.Client.Asgi.HttpResponseBody,
    json_name: "httpResponseBody",
    oneof: 0
  )

  field(:http_response_trailers, 5,
    type: Modal.Client.Asgi.HttpResponseTrailers,
    json_name: "httpResponseTrailers",
    oneof: 0
  )

  field(:http_disconnect, 6,
    type: Modal.Client.Asgi.HttpDisconnect,
    json_name: "httpDisconnect",
    oneof: 0
  )

  field(:websocket, 7, type: Modal.Client.Asgi.Websocket, oneof: 0)

  field(:websocket_connect, 8,
    type: Modal.Client.Asgi.WebsocketConnect,
    json_name: "websocketConnect",
    oneof: 0
  )

  field(:websocket_accept, 9,
    type: Modal.Client.Asgi.WebsocketAccept,
    json_name: "websocketAccept",
    oneof: 0
  )

  field(:websocket_receive, 10,
    type: Modal.Client.Asgi.WebsocketReceive,
    json_name: "websocketReceive",
    oneof: 0
  )

  field(:websocket_send, 11,
    type: Modal.Client.Asgi.WebsocketSend,
    json_name: "websocketSend",
    oneof: 0
  )

  field(:websocket_disconnect, 12,
    type: Modal.Client.Asgi.WebsocketDisconnect,
    json_name: "websocketDisconnect",
    oneof: 0
  )

  field(:websocket_close, 13,
    type: Modal.Client.Asgi.WebsocketClose,
    json_name: "websocketClose",
    oneof: 0
  )
end

defmodule Modal.Client.AttemptAwaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptAwaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:attempt_token, 1, type: :string, json_name: "attemptToken")
  field(:requested_at, 2, type: :double, json_name: "requestedAt")
  field(:timeout_secs, 3, type: :float, json_name: "timeoutSecs")
end

defmodule Modal.Client.AttemptAwaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptAwaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:output, 1, proto3_optional: true, type: Modal.Client.FunctionGetOutputsItem)
end

defmodule Modal.Client.AttemptRetryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptRetryRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:input, 3, type: Modal.Client.FunctionPutInputsItem)
  field(:attempt_token, 4, type: :string, json_name: "attemptToken")
end

defmodule Modal.Client.AttemptRetryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptRetryResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:attempt_token, 1, type: :string, json_name: "attemptToken")
end

defmodule Modal.Client.AttemptStartRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptStartRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:input, 3, type: Modal.Client.FunctionPutInputsItem)
end

defmodule Modal.Client.AttemptStartResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AttemptStartResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:attempt_token, 1, type: :string, json_name: "attemptToken")
  field(:retry_policy, 2, type: Modal.Client.FunctionRetryPolicy, json_name: "retryPolicy")
end

defmodule Modal.Client.AuthTokenGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AuthTokenGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.AuthTokenGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AuthTokenGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:token, 1, type: :string)
end

defmodule Modal.Client.AutoscalerConfiguration.OverrideEventsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AutoscalerConfiguration.OverrideEventsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Modal.Client.UserActionInfo)
end

defmodule Modal.Client.AutoscalerConfiguration do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AutoscalerConfiguration",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:settings, 1, type: Modal.Client.AutoscalerSettings)

  field(:override_events, 2,
    repeated: true,
    type: Modal.Client.AutoscalerConfiguration.OverrideEventsEntry,
    json_name: "overrideEvents",
    map: true
  )

  field(:default_settings, 3, type: Modal.Client.AutoscalerSettings, json_name: "defaultSettings")
  field(:static_settings, 4, type: Modal.Client.AutoscalerSettings, json_name: "staticSettings")

  field(:override_settings, 5,
    type: Modal.Client.AutoscalerSettings,
    json_name: "overrideSettings"
  )
end

defmodule Modal.Client.AutoscalerSettings do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AutoscalerSettings",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:min_containers, 1, proto3_optional: true, type: :uint32, json_name: "minContainers")
  field(:max_containers, 2, proto3_optional: true, type: :uint32, json_name: "maxContainers")

  field(:buffer_containers, 3,
    proto3_optional: true,
    type: :uint32,
    json_name: "bufferContainers"
  )

  field(:scaleup_window, 4, proto3_optional: true, type: :uint32, json_name: "scaleupWindow")
  field(:scaledown_window, 5, proto3_optional: true, type: :uint32, json_name: "scaledownWindow")
end

defmodule Modal.Client.AutoscalingMetrics do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.AutoscalingMetrics",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cpu_usage_percent, 1, type: :double, json_name: "cpuUsagePercent")
  field(:memory_usage_percent, 2, type: :double, json_name: "memoryUsagePercent")
  field(:concurrent_requests, 3, type: :uint32, json_name: "concurrentRequests")
  field(:timestamp, 4, type: :double)
end

defmodule Modal.Client.BaseImage do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BaseImage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:docker_tag, 2, type: :string, json_name: "dockerTag")
end

defmodule Modal.Client.BlobCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BlobCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:content_md5, 1, type: :string, json_name: "contentMd5")
  field(:content_sha256_base64, 2, type: :string, json_name: "contentSha256Base64")
  field(:content_length, 3, type: :int64, json_name: "contentLength")
end

defmodule Modal.Client.BlobCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BlobCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:upload_type_oneof, 0)

  oneof(:upload_types_oneof, 1)

  field(:blob_id, 2, type: :string, json_name: "blobId")
  field(:upload_url, 1, type: :string, json_name: "uploadUrl", oneof: 0)
  field(:multipart, 3, type: Modal.Client.MultiPartUpload, oneof: 0)
  field(:blob_ids, 4, repeated: true, type: :string, json_name: "blobIds")
  field(:upload_urls, 5, type: Modal.Client.UploadUrlList, json_name: "uploadUrls", oneof: 1)
  field(:multiparts, 6, type: Modal.Client.MultiPartUploadList, oneof: 1)
end

defmodule Modal.Client.BlobGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BlobGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:blob_id, 1, type: :string, json_name: "blobId")
end

defmodule Modal.Client.BlobGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BlobGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:download_url, 1, type: :string, json_name: "downloadUrl")
end

defmodule Modal.Client.BuildFunction do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.BuildFunction",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:definition, 1, type: :string)
  field(:globals, 2, type: :bytes)
  field(:input, 3, type: Modal.Client.FunctionInput)
end

defmodule Modal.Client.CancelInputEvent do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CancelInputEvent",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_ids, 1, repeated: true, type: :string, json_name: "inputIds")
  field(:terminate_containers, 2, type: :bool, json_name: "terminateContainers")
  field(:cancellation_reason, 3, type: :string, json_name: "cancellationReason")
end

defmodule Modal.Client.CheckpointInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CheckpointInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:checksum, 1, type: :string)
  field(:status, 2, type: Modal.Client.CheckpointStatus, enum: true)
  field(:checkpoint_id, 3, type: :string, json_name: "checkpointId")
  field(:runtime_fingerprint, 4, type: :string, json_name: "runtimeFingerprint")
  field(:size, 5, type: :int64)
  field(:checksum_is_file_index, 6, type: :bool, json_name: "checksumIsFileIndex")
  field(:original_task_id, 7, type: :string, json_name: "originalTaskId")
  field(:runsc_runtime_version, 9, type: :string, json_name: "runscRuntimeVersion")
end

defmodule Modal.Client.ClassCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:existing_class_id, 2, type: :string, json_name: "existingClassId")
  field(:methods, 3, repeated: true, type: Modal.Client.ClassMethod)
  field(:only_class_function, 5, type: :bool, json_name: "onlyClassFunction")
end

defmodule Modal.Client.ClassCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:class_id, 1, type: :string, json_name: "classId")
  field(:handle_metadata, 2, type: Modal.Client.ClassHandleMetadata, json_name: "handleMetadata")
end

defmodule Modal.Client.ClassGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_name, 1, type: :string, json_name: "appName")
  field(:object_tag, 2, type: :string, json_name: "objectTag")
  field(:environment_name, 4, type: :string, json_name: "environmentName")
  field(:only_class_function, 10, type: :bool, json_name: "onlyClassFunction")
end

defmodule Modal.Client.ClassGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:class_id, 1, type: :string, json_name: "classId")
  field(:handle_metadata, 2, type: Modal.Client.ClassHandleMetadata, json_name: "handleMetadata")

  field(:server_warnings, 3,
    repeated: true,
    type: Modal.Client.Warning,
    json_name: "serverWarnings"
  )
end

defmodule Modal.Client.ClassHandleMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassHandleMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:methods, 1, repeated: true, type: Modal.Client.ClassMethod)
  field(:class_function_id, 2, type: :string, json_name: "classFunctionId")

  field(:class_function_metadata, 3,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "classFunctionMetadata"
  )
end

defmodule Modal.Client.ClassMethod do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassMethod",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_name, 1, type: :string, json_name: "functionName")
  field(:function_id, 2, type: :string, json_name: "functionId")

  field(:function_handle_metadata, 3,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "functionHandleMetadata"
  )
end

defmodule Modal.Client.ClassParameterInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassParameterInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:format, 1,
    type: Modal.Client.ClassParameterInfo.ParameterSerializationFormat,
    enum: true
  )

  field(:schema, 2, repeated: true, type: Modal.Client.ClassParameterSpec)
end

defmodule Modal.Client.ClassParameterSet do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassParameterSet",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:parameters, 1, repeated: true, type: Modal.Client.ClassParameterValue)
end

defmodule Modal.Client.ClassParameterSpec do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassParameterSpec",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:default_oneof, 0)

  field(:name, 1, type: :string)
  field(:type, 2, type: Modal.Client.ParameterType, enum: true)
  field(:has_default, 3, type: :bool, json_name: "hasDefault")
  field(:string_default, 4, type: :string, json_name: "stringDefault", oneof: 0)
  field(:int_default, 5, type: :int64, json_name: "intDefault", oneof: 0)
  field(:pickle_default, 6, type: :bytes, json_name: "pickleDefault", oneof: 0)
  field(:bytes_default, 7, type: :bytes, json_name: "bytesDefault", oneof: 0)
  field(:bool_default, 9, type: :bool, json_name: "boolDefault", oneof: 0)
  field(:full_type, 8, type: Modal.Client.GenericPayloadType, json_name: "fullType")
end

defmodule Modal.Client.ClassParameterValue do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClassParameterValue",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:value_oneof, 0)

  field(:name, 1, type: :string)
  field(:type, 2, type: Modal.Client.ParameterType, enum: true)
  field(:string_value, 3, type: :string, json_name: "stringValue", oneof: 0)
  field(:int_value, 4, type: :int64, json_name: "intValue", oneof: 0)
  field(:pickle_value, 5, type: :bytes, json_name: "pickleValue", oneof: 0)
  field(:bytes_value, 6, type: :bytes, json_name: "bytesValue", oneof: 0)
  field(:bool_value, 7, type: :bool, json_name: "boolValue", oneof: 0)
end

defmodule Modal.Client.ClientHelloResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClientHelloResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:warning, 1, type: :string)
  field(:image_builder_version, 2, type: :string, json_name: "imageBuilderVersion")

  field(:server_warnings, 4,
    repeated: true,
    type: Modal.Client.Warning,
    json_name: "serverWarnings"
  )
end

defmodule Modal.Client.CloudBucketMount do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CloudBucketMount",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:metadata_ttl_oneof, 0)

  field(:bucket_name, 1, type: :string, json_name: "bucketName")
  field(:mount_path, 2, type: :string, json_name: "mountPath")
  field(:credentials_secret_id, 3, type: :string, json_name: "credentialsSecretId")
  field(:read_only, 4, type: :bool, json_name: "readOnly")

  field(:bucket_type, 5,
    type: Modal.Client.CloudBucketMount.BucketType,
    json_name: "bucketType",
    enum: true
  )

  field(:requester_pays, 6, type: :bool, json_name: "requesterPays")

  field(:bucket_endpoint_url, 7,
    proto3_optional: true,
    type: :string,
    json_name: "bucketEndpointUrl"
  )

  field(:key_prefix, 8, proto3_optional: true, type: :string, json_name: "keyPrefix")

  field(:oidc_auth_role_arn, 9,
    proto3_optional: true,
    type: :string,
    json_name: "oidcAuthRoleArn"
  )

  field(:force_path_style, 10, type: :bool, json_name: "forcePathStyle")

  field(:metadata_ttl_type, 11,
    type: Modal.Client.CloudBucketMount.MetadataTTLType,
    json_name: "metadataTtlType",
    enum: true,
    oneof: 0
  )

  field(:metadata_ttl_seconds, 12, type: :uint64, json_name: "metadataTtlSeconds", oneof: 0)
end

defmodule Modal.Client.ClusterGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClusterGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cluster_id, 1, type: :string, json_name: "clusterId")
end

defmodule Modal.Client.ClusterGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClusterGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cluster, 1, type: Modal.Client.ClusterStats)
end

defmodule Modal.Client.ClusterListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClusterListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.ClusterListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClusterListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:clusters, 1, repeated: true, type: Modal.Client.ClusterStats)
end

defmodule Modal.Client.ClusterStats do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ClusterStats",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:task_ids, 2, repeated: true, type: :string, json_name: "taskIds")
  field(:cluster_id, 3, type: :string, json_name: "clusterId")
  field(:started_at, 4, type: :double, json_name: "startedAt")
end

defmodule Modal.Client.CommitInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CommitInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:vcs, 1, type: :string)
  field(:branch, 2, type: :string)
  field(:commit_hash, 3, type: :string, json_name: "commitHash")
  field(:commit_timestamp, 4, type: :int64, json_name: "commitTimestamp")
  field(:dirty, 5, type: :bool)
  field(:author_name, 6, type: :string, json_name: "authorName")
  field(:author_email, 7, type: :string, json_name: "authorEmail")
  field(:repo_url, 8, type: :string, json_name: "repoUrl")
end

defmodule Modal.Client.ContainerArguments.TracingContextEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerArguments.TracingContextEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.ContainerArguments do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerArguments",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:function_id, 2, type: :string, json_name: "functionId")
  field(:app_id, 4, type: :string, json_name: "appId")
  field(:function_def, 7, type: Modal.Client.Function, json_name: "functionDef")
  field(:proxy_info, 8, type: Modal.Client.ProxyInfo, json_name: "proxyInfo")

  field(:tracing_context, 9,
    repeated: true,
    type: Modal.Client.ContainerArguments.TracingContextEntry,
    json_name: "tracingContext",
    map: true
  )

  field(:serialized_params, 10, type: :bytes, json_name: "serializedParams")
  field(:runtime, 11, type: :string)
  field(:environment_name, 13, type: :string, json_name: "environmentName")
  field(:checkpoint_id, 14, proto3_optional: true, type: :string, json_name: "checkpointId")
  field(:app_layout, 15, type: Modal.Client.AppLayout, json_name: "appLayout")
  field(:input_plane_server_url, 16, type: :string, json_name: "inputPlaneServerUrl")
end

defmodule Modal.Client.ContainerCheckpointRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerCheckpointRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:checkpoint_id, 1, type: :string, json_name: "checkpointId")
end

defmodule Modal.Client.ContainerExecGetOutputRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecGetOutputRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
  field(:timeout, 2, type: :float)
  field(:last_batch_index, 3, type: :uint64, json_name: "lastBatchIndex")

  field(:file_descriptor, 4,
    type: Modal.Client.FileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )

  field(:get_raw_bytes, 5, type: :bool, json_name: "getRawBytes")
end

defmodule Modal.Client.ContainerExecPutInputRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecPutInputRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
  field(:input, 2, type: Modal.Client.RuntimeInputMessage)
end

defmodule Modal.Client.ContainerExecRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:command, 2, repeated: true, type: :string)
  field(:pty_info, 3, proto3_optional: true, type: Modal.Client.PTYInfo, json_name: "ptyInfo")

  field(:terminate_container_on_exit, 4,
    type: :bool,
    json_name: "terminateContainerOnExit",
    deprecated: true
  )

  field(:runtime_debug, 5, type: :bool, json_name: "runtimeDebug")

  field(:stdout_output, 6,
    type: Modal.Client.ExecOutputOption,
    json_name: "stdoutOutput",
    enum: true
  )

  field(:stderr_output, 7,
    type: Modal.Client.ExecOutputOption,
    json_name: "stderrOutput",
    enum: true
  )

  field(:timeout_secs, 8, type: :uint32, json_name: "timeoutSecs")
  field(:workdir, 9, proto3_optional: true, type: :string)
  field(:secret_ids, 10, repeated: true, type: :string, json_name: "secretIds")
end

defmodule Modal.Client.ContainerExecResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
end

defmodule Modal.Client.ContainerExecWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.ContainerExecWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerExecWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exit_code, 1, proto3_optional: true, type: :int32, json_name: "exitCode")
  field(:completed, 2, type: :bool)
end

defmodule Modal.Client.ContainerFileCloseRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileCloseRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
end

defmodule Modal.Client.ContainerFileDeleteBytesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileDeleteBytesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
  field(:start_inclusive, 2, proto3_optional: true, type: :uint32, json_name: "startInclusive")
  field(:end_exclusive, 3, proto3_optional: true, type: :uint32, json_name: "endExclusive")
end

defmodule Modal.Client.ContainerFileFlushRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileFlushRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
end

defmodule Modal.Client.ContainerFileLsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileLsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
end

defmodule Modal.Client.ContainerFileMkdirRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileMkdirRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
  field(:make_parents, 2, type: :bool, json_name: "makeParents")
end

defmodule Modal.Client.ContainerFileOpenRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileOpenRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, proto3_optional: true, type: :string, json_name: "fileDescriptor")
  field(:path, 2, type: :string)
  field(:mode, 3, type: :string)
end

defmodule Modal.Client.ContainerFileReadLineRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileReadLineRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
end

defmodule Modal.Client.ContainerFileReadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileReadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
  field(:n, 2, proto3_optional: true, type: :uint32)
end

defmodule Modal.Client.ContainerFileRmRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileRmRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
  field(:recursive, 2, type: :bool)
end

defmodule Modal.Client.ContainerFileSeekRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileSeekRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
  field(:offset, 2, type: :int32)
  field(:whence, 3, type: Modal.Client.SeekWhence, enum: true)
end

defmodule Modal.Client.ContainerFileWatchRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileWatchRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
  field(:recursive, 2, type: :bool)
  field(:timeout_secs, 3, proto3_optional: true, type: :uint64, json_name: "timeoutSecs")
end

defmodule Modal.Client.ContainerFileWriteReplaceBytesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileWriteReplaceBytesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
  field(:data, 2, type: :bytes)
  field(:start_inclusive, 3, proto3_optional: true, type: :uint32, json_name: "startInclusive")
  field(:end_exclusive, 4, proto3_optional: true, type: :uint32, json_name: "endExclusive")
end

defmodule Modal.Client.ContainerFileWriteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFileWriteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1, type: :string, json_name: "fileDescriptor")
  field(:data, 2, type: :bytes)
end

defmodule Modal.Client.ContainerFilesystemExecGetOutputRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFilesystemExecGetOutputRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.ContainerFilesystemExecRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFilesystemExecRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:file_exec_request_oneof, 0)

  field(:file_open_request, 1,
    type: Modal.Client.ContainerFileOpenRequest,
    json_name: "fileOpenRequest",
    oneof: 0
  )

  field(:file_write_request, 2,
    type: Modal.Client.ContainerFileWriteRequest,
    json_name: "fileWriteRequest",
    oneof: 0
  )

  field(:file_read_request, 3,
    type: Modal.Client.ContainerFileReadRequest,
    json_name: "fileReadRequest",
    oneof: 0
  )

  field(:file_flush_request, 4,
    type: Modal.Client.ContainerFileFlushRequest,
    json_name: "fileFlushRequest",
    oneof: 0
  )

  field(:file_read_line_request, 5,
    type: Modal.Client.ContainerFileReadLineRequest,
    json_name: "fileReadLineRequest",
    oneof: 0
  )

  field(:file_seek_request, 6,
    type: Modal.Client.ContainerFileSeekRequest,
    json_name: "fileSeekRequest",
    oneof: 0
  )

  field(:file_delete_bytes_request, 7,
    type: Modal.Client.ContainerFileDeleteBytesRequest,
    json_name: "fileDeleteBytesRequest",
    oneof: 0
  )

  field(:file_write_replace_bytes_request, 8,
    type: Modal.Client.ContainerFileWriteReplaceBytesRequest,
    json_name: "fileWriteReplaceBytesRequest",
    oneof: 0
  )

  field(:file_close_request, 9,
    type: Modal.Client.ContainerFileCloseRequest,
    json_name: "fileCloseRequest",
    oneof: 0
  )

  field(:file_ls_request, 11,
    type: Modal.Client.ContainerFileLsRequest,
    json_name: "fileLsRequest",
    oneof: 0
  )

  field(:file_mkdir_request, 12,
    type: Modal.Client.ContainerFileMkdirRequest,
    json_name: "fileMkdirRequest",
    oneof: 0
  )

  field(:file_rm_request, 13,
    type: Modal.Client.ContainerFileRmRequest,
    json_name: "fileRmRequest",
    oneof: 0
  )

  field(:file_watch_request, 14,
    type: Modal.Client.ContainerFileWatchRequest,
    json_name: "fileWatchRequest",
    oneof: 0
  )

  field(:task_id, 10, type: :string, json_name: "taskId")
end

defmodule Modal.Client.ContainerFilesystemExecResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerFilesystemExecResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exec_id, 1, type: :string, json_name: "execId")
  field(:file_descriptor, 2, proto3_optional: true, type: :string, json_name: "fileDescriptor")
end

defmodule Modal.Client.ContainerHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:canceled_inputs_return_outputs, 4, type: :bool, json_name: "canceledInputsReturnOutputs")

  field(:canceled_inputs_return_outputs_v2, 5,
    type: :bool,
    json_name: "canceledInputsReturnOutputsV2"
  )
end

defmodule Modal.Client.ContainerHeartbeatResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerHeartbeatResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cancel_input_event, 1,
    proto3_optional: true,
    type: Modal.Client.CancelInputEvent,
    json_name: "cancelInputEvent"
  )
end

defmodule Modal.Client.ContainerLogRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerLogRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:logs, 3, repeated: true, type: Modal.Client.TaskLogs)
end

defmodule Modal.Client.ContainerReloadVolumesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerReloadVolumesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
end

defmodule Modal.Client.ContainerReloadVolumesResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerReloadVolumesResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.ContainerStopRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerStopRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
end

defmodule Modal.Client.ContainerStopResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ContainerStopResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.CreationInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CreationInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:created_at, 1, type: :double, json_name: "createdAt")
  field(:created_by, 2, type: :string, json_name: "createdBy")
end

defmodule Modal.Client.CustomDomainConfig do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CustomDomainConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
end

defmodule Modal.Client.CustomDomainInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.CustomDomainInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)
end

defmodule Modal.Client.DNSRecord do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DNSRecord",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:type, 1, type: Modal.Client.DNSRecordType, enum: true)
  field(:name, 2, type: :string)
  field(:value, 3, type: :string)
end

defmodule Modal.Client.DataChunk do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DataChunk",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:data_format, 1, type: Modal.Client.DataFormat, json_name: "dataFormat", enum: true)
  field(:data, 2, type: :bytes, oneof: 0)
  field(:data_blob_id, 3, type: :string, json_name: "dataBlobId", oneof: 0)
  field(:index, 4, type: :uint64)
end

defmodule Modal.Client.DictClearRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictClearRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
end

defmodule Modal.Client.DictContainsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictContainsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:key, 2, type: :bytes)
end

defmodule Modal.Client.DictContainsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictContainsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:found, 1, type: :bool)
end

defmodule Modal.Client.DictContentsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictContentsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:keys, 2, type: :bool)
  field(:values, 3, type: :bool)
end

defmodule Modal.Client.DictDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
end

defmodule Modal.Client.DictEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :bytes)
  field(:value, 2, type: :bytes)
end

defmodule Modal.Client.DictGetByIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetByIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
end

defmodule Modal.Client.DictGetByIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetByIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:metadata, 2, type: Modal.Client.DictMetadata)
end

defmodule Modal.Client.DictGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )

  field(:data, 5, repeated: true, type: Modal.Client.DictEntry)
end

defmodule Modal.Client.DictGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:metadata, 2, type: Modal.Client.DictMetadata)
end

defmodule Modal.Client.DictGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:key, 2, type: :bytes)
end

defmodule Modal.Client.DictGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:found, 1, type: :bool)
  field(:value, 2, proto3_optional: true, type: :bytes)
end

defmodule Modal.Client.DictHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
end

defmodule Modal.Client.DictLenRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictLenRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
end

defmodule Modal.Client.DictLenResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictLenResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:len, 1, type: :int32)
end

defmodule Modal.Client.DictListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:pagination, 2, type: Modal.Client.ListPagination)
end

defmodule Modal.Client.DictListResponse.DictInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictListResponse.DictInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:created_at, 2, type: :double, json_name: "createdAt")
  field(:dict_id, 3, type: :string, json_name: "dictId")
  field(:metadata, 4, type: Modal.Client.DictMetadata)
end

defmodule Modal.Client.DictListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dicts, 1, repeated: true, type: Modal.Client.DictListResponse.DictInfo)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.DictMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:creation_info, 2, type: Modal.Client.CreationInfo, json_name: "creationInfo")
end

defmodule Modal.Client.DictPopRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictPopRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:key, 2, type: :bytes)
end

defmodule Modal.Client.DictPopResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictPopResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:found, 1, type: :bool)
  field(:value, 2, proto3_optional: true, type: :bytes)
end

defmodule Modal.Client.DictUpdateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictUpdateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:dict_id, 1, type: :string, json_name: "dictId")
  field(:updates, 2, repeated: true, type: Modal.Client.DictEntry)
  field(:if_not_exists, 3, type: :bool, json_name: "ifNotExists")
end

defmodule Modal.Client.DictUpdateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DictUpdateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:created, 1, type: :bool)
end

defmodule Modal.Client.Domain do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Domain",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domain_id, 1, type: :string, json_name: "domainId")
  field(:domain_name, 2, type: :string, json_name: "domainName")
  field(:created_at, 3, type: :double, json_name: "createdAt")

  field(:certificate_status, 4,
    type: Modal.Client.CertificateStatus,
    json_name: "certificateStatus",
    enum: true
  )

  field(:dns_records, 5, repeated: true, type: Modal.Client.DNSRecord, json_name: "dnsRecords")
end

defmodule Modal.Client.DomainCertificateVerifyRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainCertificateVerifyRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domain_id, 1, type: :string, json_name: "domainId")
end

defmodule Modal.Client.DomainCertificateVerifyResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainCertificateVerifyResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domain, 1, type: Modal.Client.Domain)
end

defmodule Modal.Client.DomainCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domain_name, 1, type: :string, json_name: "domainName")
end

defmodule Modal.Client.DomainCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domain_id, 1, type: :string, json_name: "domainId")
  field(:dns_records, 2, repeated: true, type: Modal.Client.DNSRecord, json_name: "dnsRecords")
end

defmodule Modal.Client.DomainListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.DomainListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.DomainListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:domains, 1, repeated: true, type: Modal.Client.Domain)
end

defmodule Modal.Client.EnvironmentCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
end

defmodule Modal.Client.EnvironmentDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
end

defmodule Modal.Client.EnvironmentGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")

  field(:object_creation_type, 2,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )
end

defmodule Modal.Client.EnvironmentGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_id, 1, type: :string, json_name: "environmentId")
  field(:metadata, 2, type: Modal.Client.EnvironmentMetadata)
end

defmodule Modal.Client.EnvironmentListItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentListItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:webhook_suffix, 2, type: :string, json_name: "webhookSuffix")
  field(:created_at, 3, type: :double, json_name: "createdAt")
  field(:default, 4, type: :bool)
  field(:is_managed, 5, type: :bool, json_name: "isManaged")
  field(:environment_id, 6, type: :string, json_name: "environmentId")

  field(:max_concurrent_tasks, 7,
    proto3_optional: true,
    type: :int32,
    json_name: "maxConcurrentTasks"
  )

  field(:max_concurrent_gpus, 8,
    proto3_optional: true,
    type: :int32,
    json_name: "maxConcurrentGpus"
  )

  field(:current_concurrent_tasks, 9, type: :int32, json_name: "currentConcurrentTasks")
  field(:current_concurrent_gpus, 10, type: :int32, json_name: "currentConcurrentGpus")
end

defmodule Modal.Client.EnvironmentListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 2, repeated: true, type: Modal.Client.EnvironmentListItem)
end

defmodule Modal.Client.EnvironmentMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:settings, 2, type: Modal.Client.EnvironmentSettings)
end

defmodule Modal.Client.EnvironmentSettings do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentSettings",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_builder_version, 1, type: :string, json_name: "imageBuilderVersion")
  field(:webhook_suffix, 2, type: :string, json_name: "webhookSuffix")
end

defmodule Modal.Client.EnvironmentUpdateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.EnvironmentUpdateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:current_name, 1, type: :string, json_name: "currentName")
  field(:name, 2, type: Google.Protobuf.StringValue)
  field(:web_suffix, 3, type: Google.Protobuf.StringValue, json_name: "webSuffix")

  field(:max_concurrent_tasks, 4,
    proto3_optional: true,
    type: :int32,
    json_name: "maxConcurrentTasks"
  )

  field(:max_concurrent_gpus, 5,
    proto3_optional: true,
    type: :int32,
    json_name: "maxConcurrentGpus"
  )
end

defmodule Modal.Client.FileEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FileEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
  field(:type, 2, type: Modal.Client.FileEntry.FileType, enum: true)
  field(:mtime, 3, type: :uint64)
  field(:size, 4, type: :uint64)
end

defmodule Modal.Client.FilesystemRuntimeOutputBatch do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FilesystemRuntimeOutputBatch",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:output, 1, repeated: true, type: :bytes)
  field(:error, 2, proto3_optional: true, type: Modal.Client.SystemErrorMessage)
  field(:batch_index, 3, type: :uint64, json_name: "batchIndex")
  field(:eof, 4, type: :bool)
end

defmodule Modal.Client.FlashContainerDeregisterRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerDeregisterRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:service_name, 1, type: :string, json_name: "serviceName")
end

defmodule Modal.Client.FlashContainerListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
end

defmodule Modal.Client.FlashContainerListResponse.Container do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerListResponse.Container",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:host, 2, type: :string)
  field(:port, 3, type: :uint32)
end

defmodule Modal.Client.FlashContainerListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:containers, 1, repeated: true, type: Modal.Client.FlashContainerListResponse.Container)
end

defmodule Modal.Client.FlashContainerRegisterRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerRegisterRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:service_name, 1, type: :string, json_name: "serviceName")
  field(:priority, 2, type: :uint32)
  field(:weight, 3, type: :uint32)
  field(:host, 4, type: :string)
  field(:port, 5, type: :uint32)
end

defmodule Modal.Client.FlashContainerRegisterResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashContainerRegisterResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)
end

defmodule Modal.Client.FlashProxyUpstreamRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashProxyUpstreamRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:upstream_requests, 1, type: :uint32, json_name: "upstreamRequests")
  field(:timestamp, 2, type: :double)
end

defmodule Modal.Client.FlashSetTargetSlotsMetricsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashSetTargetSlotsMetricsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:target_slots, 2, type: :uint32, json_name: "targetSlots")
end

defmodule Modal.Client.FlashSetTargetSlotsMetricsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FlashSetTargetSlotsMetricsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.Function.MethodDefinitionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Function.MethodDefinitionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Modal.Client.MethodDefinition)
end

defmodule Modal.Client.Function.ExperimentalOptionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Function.ExperimentalOptionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.Function do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Function",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:X_experimental_proxy_ip, 3)

  field(:module_name, 1, type: :string, json_name: "moduleName")
  field(:function_name, 2, type: :string, json_name: "functionName")
  field(:mount_ids, 3, repeated: true, type: :string, json_name: "mountIds")
  field(:image_id, 4, type: :string, json_name: "imageId")
  field(:function_serialized, 6, type: :bytes, json_name: "functionSerialized")

  field(:definition_type, 7,
    type: Modal.Client.Function.DefinitionType,
    json_name: "definitionType",
    enum: true
  )

  field(:function_type, 8,
    type: Modal.Client.Function.FunctionType,
    json_name: "functionType",
    enum: true
  )

  field(:resources, 9, type: Modal.Client.Resources)
  field(:secret_ids, 10, repeated: true, type: :string, json_name: "secretIds")
  field(:rate_limit, 11, type: Modal.Client.RateLimit, json_name: "rateLimit")
  field(:webhook_config, 15, type: Modal.Client.WebhookConfig, json_name: "webhookConfig")

  field(:shared_volume_mounts, 16,
    repeated: true,
    type: Modal.Client.SharedVolumeMount,
    json_name: "sharedVolumeMounts"
  )

  field(:proxy_id, 17, proto3_optional: true, type: :string, json_name: "proxyId")
  field(:retry_policy, 18, type: Modal.Client.FunctionRetryPolicy, json_name: "retryPolicy")
  field(:concurrency_limit, 19, type: :uint32, json_name: "concurrencyLimit")
  field(:timeout_secs, 21, type: :uint32, json_name: "timeoutSecs")
  field(:pty_info, 22, type: Modal.Client.PTYInfo, json_name: "ptyInfo")
  field(:class_serialized, 23, type: :bytes, json_name: "classSerialized")
  field(:task_idle_timeout_secs, 25, type: :uint32, json_name: "taskIdleTimeoutSecs")

  field(:cloud_provider, 26,
    proto3_optional: true,
    type: Modal.Client.CloudProvider,
    json_name: "cloudProvider",
    enum: true
  )

  field(:warm_pool_size, 27, type: :uint32, json_name: "warmPoolSize")
  field(:web_url, 28, type: :string, json_name: "webUrl")
  field(:web_url_info, 29, type: Modal.Client.WebUrlInfo, json_name: "webUrlInfo")
  field(:runtime, 30, type: :string)
  field(:app_name, 31, type: :string, json_name: "appName")

  field(:volume_mounts, 33,
    repeated: true,
    type: Modal.Client.VolumeMount,
    json_name: "volumeMounts"
  )

  field(:max_concurrent_inputs, 34, type: :uint32, json_name: "maxConcurrentInputs")

  field(:custom_domain_info, 35,
    repeated: true,
    type: Modal.Client.CustomDomainInfo,
    json_name: "customDomainInfo"
  )

  field(:worker_id, 36, type: :string, json_name: "workerId")
  field(:runtime_debug, 37, type: :bool, json_name: "runtimeDebug")
  field(:is_builder_function, 32, type: :bool, json_name: "isBuilderFunction")
  field(:is_auto_snapshot, 38, type: :bool, json_name: "isAutoSnapshot")
  field(:is_method, 39, type: :bool, json_name: "isMethod")
  field(:is_checkpointing_function, 40, type: :bool, json_name: "isCheckpointingFunction")
  field(:checkpointing_enabled, 41, type: :bool, json_name: "checkpointingEnabled")
  field(:checkpoint, 42, type: Modal.Client.CheckpointInfo)

  field(:object_dependencies, 43,
    repeated: true,
    type: Modal.Client.ObjectDependency,
    json_name: "objectDependencies"
  )

  field(:block_network, 44, type: :bool, json_name: "blockNetwork")
  field(:max_inputs, 46, type: :uint32, json_name: "maxInputs")
  field(:s3_mounts, 47, repeated: true, type: Modal.Client.S3Mount, json_name: "s3Mounts")

  field(:cloud_bucket_mounts, 51,
    repeated: true,
    type: Modal.Client.CloudBucketMount,
    json_name: "cloudBucketMounts"
  )

  field(:scheduler_placement, 50,
    proto3_optional: true,
    type: Modal.Client.SchedulerPlacement,
    json_name: "schedulerPlacement"
  )

  field(:is_class, 53, type: :bool, json_name: "isClass")
  field(:use_function_id, 54, type: :string, json_name: "useFunctionId")
  field(:use_method_name, 55, type: :string, json_name: "useMethodName")

  field(:class_parameter_info, 56,
    type: Modal.Client.ClassParameterInfo,
    json_name: "classParameterInfo"
  )

  field(:batch_max_size, 60, type: :uint32, json_name: "batchMaxSize")
  field(:batch_linger_ms, 61, type: :uint64, json_name: "batchLingerMs")
  field(:i6pn_enabled, 62, type: :bool, json_name: "i6pnEnabled")

  field(:_experimental_concurrent_cancellations, 63,
    type: :bool,
    json_name: "ExperimentalConcurrentCancellations"
  )

  field(:target_concurrent_inputs, 64, type: :uint32, json_name: "targetConcurrentInputs")

  field(:_experimental_task_templates_enabled, 65,
    type: :bool,
    json_name: "ExperimentalTaskTemplatesEnabled"
  )

  field(:_experimental_task_templates, 66,
    repeated: true,
    type: Modal.Client.TaskTemplate,
    json_name: "ExperimentalTaskTemplates"
  )

  field(:_experimental_group_size, 67, type: :uint32, json_name: "ExperimentalGroupSize")
  field(:untrusted, 68, type: :bool)

  field(:_experimental_buffer_containers, 69,
    type: :uint32,
    json_name: "ExperimentalBufferContainers"
  )

  field(:_experimental_proxy_ip, 70,
    proto3_optional: true,
    type: :string,
    json_name: "ExperimentalProxyIp"
  )

  field(:runtime_perf_record, 71, type: :bool, json_name: "runtimePerfRecord")
  field(:schedule, 72, type: Modal.Client.Schedule)
  field(:snapshot_debug, 73, type: :bool, json_name: "snapshotDebug")

  field(:method_definitions, 74,
    repeated: true,
    type: Modal.Client.Function.MethodDefinitionsEntry,
    json_name: "methodDefinitions",
    map: true
  )

  field(:method_definitions_set, 75, type: :bool, json_name: "methodDefinitionsSet")
  field(:_experimental_custom_scaling, 76, type: :bool, json_name: "ExperimentalCustomScaling")
  field(:cloud_provider_str, 77, type: :string, json_name: "cloudProviderStr")

  field(:_experimental_enable_gpu_snapshot, 78,
    type: :bool,
    json_name: "ExperimentalEnableGpuSnapshot"
  )

  field(:autoscaler_settings, 79,
    type: Modal.Client.AutoscalerSettings,
    json_name: "autoscalerSettings"
  )

  field(:function_schema, 80, type: Modal.Client.FunctionSchema, json_name: "functionSchema")

  field(:experimental_options, 81,
    repeated: true,
    type: Modal.Client.Function.ExperimentalOptionsEntry,
    json_name: "experimentalOptions",
    map: true
  )

  field(:mount_client_dependencies, 82, type: :bool, json_name: "mountClientDependencies")
  field(:flash_service_urls, 83, repeated: true, type: :string, json_name: "flashServiceUrls")
  field(:flash_service_label, 84, type: :string, json_name: "flashServiceLabel")
  field(:enable_gpu_snapshot, 85, type: :bool, json_name: "enableGpuSnapshot")
  field(:startup_timeout_secs, 86, type: :uint32, json_name: "startupTimeoutSecs")

  field(:supported_input_formats, 87,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedInputFormats",
    enum: true
  )

  field(:supported_output_formats, 88,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedOutputFormats",
    enum: true
  )

  field(:http_config, 89,
    proto3_optional: true,
    type: Modal.Client.HTTPConfig,
    json_name: "httpConfig"
  )

  field(:implementation_name, 90, type: :string, json_name: "implementationName")
  field(:single_use_containers, 91, type: :bool, json_name: "singleUseContainers")
  field(:is_server, 92, type: :bool, json_name: "isServer")
end

defmodule Modal.Client.FunctionAsyncInvokeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionAsyncInvokeRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:input, 3, type: Modal.Client.FunctionInput)
end

defmodule Modal.Client.FunctionAsyncInvokeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionAsyncInvokeResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:retry_with_blob_upload, 1, type: :bool, json_name: "retryWithBlobUpload")
  field(:function_call_id, 2, type: :string, json_name: "functionCallId")
end

defmodule Modal.Client.FunctionBindParamsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionBindParamsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:serialized_params, 2, type: :bytes, json_name: "serializedParams")
  field(:function_options, 3, type: Modal.Client.FunctionOptions, json_name: "functionOptions")
  field(:environment_name, 4, type: :string, json_name: "environmentName")
  field(:auth_secret, 5, type: :string, json_name: "authSecret")
end

defmodule Modal.Client.FunctionBindParamsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionBindParamsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:bound_function_id, 1, type: :string, json_name: "boundFunctionId")

  field(:handle_metadata, 2,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "handleMetadata"
  )
end

defmodule Modal.Client.FunctionCallCallGraphInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallCallGraphInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:function_name, 3, type: :string, json_name: "functionName")
  field(:module_name, 4, type: :string, json_name: "moduleName")
end

defmodule Modal.Client.FunctionCallCancelRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallCancelRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
  field(:terminate_containers, 2, type: :bool, json_name: "terminateContainers")
  field(:function_id, 3, proto3_optional: true, type: :string, json_name: "functionId")
end

defmodule Modal.Client.FunctionCallFromIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallFromIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
end

defmodule Modal.Client.FunctionCallFromIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallFromIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
  field(:num_inputs, 2, type: :int32, json_name: "numInputs")
end

defmodule Modal.Client.FunctionCallGetDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallGetDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:call_info, 0)

  field(:function_call_id, 1, type: :string, json_name: "functionCallId", oneof: 0)
  field(:attempt_token, 3, type: :string, json_name: "attemptToken", oneof: 0)
  field(:last_index, 2, type: :uint64, json_name: "lastIndex")
  field(:use_gapless_read, 4, type: :bool, json_name: "useGaplessRead")
end

defmodule Modal.Client.FunctionCallInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
  field(:idx, 2, type: :int32)
  field(:created_at, 6, type: :double, json_name: "createdAt")
  field(:scheduled_at, 7, type: :double, json_name: "scheduledAt")
  field(:pending_inputs, 12, type: Modal.Client.InputCategoryInfo, json_name: "pendingInputs")
  field(:failed_inputs, 13, type: Modal.Client.InputCategoryInfo, json_name: "failedInputs")
  field(:succeeded_inputs, 14, type: Modal.Client.InputCategoryInfo, json_name: "succeededInputs")
  field(:timeout_inputs, 15, type: Modal.Client.InputCategoryInfo, json_name: "timeoutInputs")
  field(:cancelled_inputs, 16, type: Modal.Client.InputCategoryInfo, json_name: "cancelledInputs")
  field(:total_inputs, 17, type: :int32, json_name: "totalInputs")
end

defmodule Modal.Client.FunctionCallListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
end

defmodule Modal.Client.FunctionCallListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_calls, 1,
    repeated: true,
    type: Modal.Client.FunctionCallInfo,
    json_name: "functionCalls"
  )
end

defmodule Modal.Client.FunctionCallPutDataRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCallPutDataRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:call_info, 0)

  field(:function_call_id, 1, type: :string, json_name: "functionCallId", oneof: 0)
  field(:attempt_token, 3, type: :string, json_name: "attemptToken", oneof: 0)
  field(:data_chunks, 2, repeated: true, type: Modal.Client.DataChunk, json_name: "dataChunks")
end

defmodule Modal.Client.FunctionCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function, 1, type: Modal.Client.Function)
  field(:app_id, 2, type: :string, json_name: "appId")
  field(:schedule, 6, type: Modal.Client.Schedule, deprecated: true)
  field(:existing_function_id, 7, type: :string, json_name: "existingFunctionId")
  field(:function_data, 9, type: Modal.Client.FunctionData, json_name: "functionData")
end

defmodule Modal.Client.FunctionCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:__deprecated_web_url, 2, type: :string, json_name: "DeprecatedWebUrl", deprecated: true)
  field(:function, 4, type: Modal.Client.Function)

  field(:handle_metadata, 5,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "handleMetadata"
  )

  field(:server_warnings, 6,
    repeated: true,
    type: Modal.Client.Warning,
    json_name: "serverWarnings"
  )
end

defmodule Modal.Client.FunctionData.MethodDefinitionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionData.MethodDefinitionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Modal.Client.MethodDefinition)
end

defmodule Modal.Client.FunctionData.RankedFunction do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionData.RankedFunction",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:rank, 1, type: :uint32)
  field(:function, 2, type: Modal.Client.Function)
end

defmodule Modal.Client.FunctionData.ExperimentalOptionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionData.ExperimentalOptionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.FunctionData do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionData",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:X_experimental_proxy_ip, 0)

  field(:module_name, 1, type: :string, json_name: "moduleName")
  field(:function_name, 2, type: :string, json_name: "functionName")

  field(:function_type, 3,
    type: Modal.Client.Function.FunctionType,
    json_name: "functionType",
    enum: true
  )

  field(:warm_pool_size, 4, type: :uint32, json_name: "warmPoolSize")
  field(:concurrency_limit, 5, type: :uint32, json_name: "concurrencyLimit")
  field(:task_idle_timeout_secs, 6, type: :uint32, json_name: "taskIdleTimeoutSecs")
  field(:_experimental_group_size, 19, type: :uint32, json_name: "ExperimentalGroupSize")

  field(:_experimental_buffer_containers, 22,
    type: :uint32,
    json_name: "ExperimentalBufferContainers"
  )

  field(:_experimental_custom_scaling, 23, type: :bool, json_name: "ExperimentalCustomScaling")

  field(:_experimental_enable_gpu_snapshot, 30,
    type: :bool,
    json_name: "ExperimentalEnableGpuSnapshot"
  )

  field(:worker_id, 7, type: :string, json_name: "workerId")
  field(:timeout_secs, 8, type: :uint32, json_name: "timeoutSecs")
  field(:web_url, 9, type: :string, json_name: "webUrl")
  field(:web_url_info, 10, type: Modal.Client.WebUrlInfo, json_name: "webUrlInfo")
  field(:webhook_config, 11, type: Modal.Client.WebhookConfig, json_name: "webhookConfig")

  field(:custom_domain_info, 12,
    repeated: true,
    type: Modal.Client.CustomDomainInfo,
    json_name: "customDomainInfo"
  )

  field(:_experimental_proxy_ip, 24,
    proto3_optional: true,
    type: :string,
    json_name: "ExperimentalProxyIp"
  )

  field(:method_definitions, 25,
    repeated: true,
    type: Modal.Client.FunctionData.MethodDefinitionsEntry,
    json_name: "methodDefinitions",
    map: true
  )

  field(:method_definitions_set, 26, type: :bool, json_name: "methodDefinitionsSet")
  field(:is_class, 13, type: :bool, json_name: "isClass")

  field(:class_parameter_info, 14,
    type: Modal.Client.ClassParameterInfo,
    json_name: "classParameterInfo"
  )

  field(:is_method, 15, type: :bool, json_name: "isMethod")
  field(:use_function_id, 16, type: :string, json_name: "useFunctionId")
  field(:use_method_name, 17, type: :string, json_name: "useMethodName")

  field(:ranked_functions, 18,
    repeated: true,
    type: Modal.Client.FunctionData.RankedFunction,
    json_name: "rankedFunctions"
  )

  field(:schedule, 20, type: Modal.Client.Schedule)
  field(:untrusted, 27, type: :bool)
  field(:snapshot_debug, 28, type: :bool, json_name: "snapshotDebug")
  field(:runtime_perf_record, 29, type: :bool, json_name: "runtimePerfRecord")

  field(:autoscaler_settings, 31,
    type: Modal.Client.AutoscalerSettings,
    json_name: "autoscalerSettings"
  )

  field(:function_schema, 32, type: Modal.Client.FunctionSchema, json_name: "functionSchema")

  field(:experimental_options, 33,
    repeated: true,
    type: Modal.Client.FunctionData.ExperimentalOptionsEntry,
    json_name: "experimentalOptions",
    map: true
  )

  field(:flash_service_urls, 34, repeated: true, type: :string, json_name: "flashServiceUrls")
  field(:flash_service_label, 35, type: :string, json_name: "flashServiceLabel")
  field(:startup_timeout_secs, 36, type: :uint32, json_name: "startupTimeoutSecs")

  field(:supported_input_formats, 37,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedInputFormats",
    enum: true
  )

  field(:supported_output_formats, 38,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedOutputFormats",
    enum: true
  )

  field(:http_config, 39,
    proto3_optional: true,
    type: Modal.Client.HTTPConfig,
    json_name: "httpConfig"
  )

  field(:implementation_name, 40, type: :string, json_name: "implementationName")
  field(:is_server, 41, type: :bool, json_name: "isServer")
end

defmodule Modal.Client.FunctionExtended do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionExtended",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:function_extended, 0)

  field(:type_identifier, 1, type: :uint32, json_name: "typeIdentifier")

  field(:function_singleton, 2,
    type: Modal.Client.Function,
    json_name: "functionSingleton",
    oneof: 0
  )

  field(:function_data, 3, type: Modal.Client.FunctionData, json_name: "functionData", oneof: 0)
end

defmodule Modal.Client.FunctionFinishInputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionFinishInputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:function_call_id, 2, type: :string, json_name: "functionCallId")
  field(:num_inputs, 3, type: :uint32, json_name: "numInputs")
end

defmodule Modal.Client.FunctionGetCallGraphRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetCallGraphRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 2, type: :string, json_name: "functionCallId")
end

defmodule Modal.Client.FunctionGetCallGraphResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetCallGraphResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:inputs, 1, repeated: true, type: Modal.Client.InputCallGraphInfo)

  field(:function_calls, 2,
    repeated: true,
    type: Modal.Client.FunctionCallCallGraphInfo,
    json_name: "functionCalls"
  )
end

defmodule Modal.Client.FunctionGetCurrentStatsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetCurrentStatsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
end

defmodule Modal.Client.FunctionGetDynamicConcurrencyRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetDynamicConcurrencyRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:target_concurrency, 2, type: :uint32, json_name: "targetConcurrency")
  field(:max_concurrency, 3, type: :uint32, json_name: "maxConcurrency")
end

defmodule Modal.Client.FunctionGetDynamicConcurrencyResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetDynamicConcurrencyResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:concurrency, 1, type: :uint32)
end

defmodule Modal.Client.FunctionGetInputsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetInputsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_id, 1, type: :string, json_name: "inputId")
  field(:input, 2, type: Modal.Client.FunctionInput)
  field(:kill_switch, 3, type: :bool, json_name: "killSwitch")
  field(:function_call_id, 5, type: :string, json_name: "functionCallId")

  field(:function_call_invocation_type, 6,
    type: Modal.Client.FunctionCallInvocationType,
    json_name: "functionCallInvocationType",
    enum: true
  )

  field(:retry_count, 7, type: :uint32, json_name: "retryCount")
  field(:function_map_idx, 8, proto3_optional: true, type: :int32, json_name: "functionMapIdx")
  field(:attempt_token, 9, type: :string, json_name: "attemptToken")
end

defmodule Modal.Client.FunctionGetInputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetInputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:max_values, 3, type: :int32, json_name: "maxValues")
  field(:average_call_time, 5, type: :float, json_name: "averageCallTime")
  field(:input_concurrency, 6, type: :int32, json_name: "inputConcurrency")
  field(:batch_max_size, 11, type: :uint32, json_name: "batchMaxSize")
  field(:batch_linger_ms, 12, type: :uint64, json_name: "batchLingerMs")
end

defmodule Modal.Client.FunctionGetInputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetInputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:inputs, 3, repeated: true, type: Modal.Client.FunctionGetInputsItem)
  field(:rate_limit_sleep_duration, 4, type: :float, json_name: "rateLimitSleepDuration")
end

defmodule Modal.Client.FunctionGetOutputsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetOutputsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
  field(:idx, 2, type: :int32)
  field(:input_id, 3, type: :string, json_name: "inputId")
  field(:data_format, 5, type: Modal.Client.DataFormat, json_name: "dataFormat", enum: true)
  field(:task_id, 6, type: :string, json_name: "taskId")
  field(:input_started_at, 7, type: :double, json_name: "inputStartedAt")
  field(:output_created_at, 8, type: :double, json_name: "outputCreatedAt")
  field(:retry_count, 9, type: :uint32, json_name: "retryCount")
  field(:fc_trace_tag, 10, type: :string, json_name: "fcTraceTag")
end

defmodule Modal.Client.FunctionGetOutputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetOutputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")
  field(:max_values, 2, type: :int32, json_name: "maxValues")
  field(:timeout, 3, type: :float)
  field(:last_entry_id, 6, type: :string, json_name: "lastEntryId")
  field(:clear_on_success, 7, type: :bool, json_name: "clearOnSuccess")
  field(:requested_at, 8, type: :double, json_name: "requestedAt")
  field(:input_jwts, 9, repeated: true, type: :string, json_name: "inputJwts")
  field(:start_idx, 10, proto3_optional: true, type: :int32, json_name: "startIdx")
  field(:end_idx, 11, proto3_optional: true, type: :int32, json_name: "endIdx")
end

defmodule Modal.Client.FunctionGetOutputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetOutputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:idxs, 3, repeated: true, type: :int32)
  field(:outputs, 4, repeated: true, type: Modal.Client.FunctionGetOutputsItem)
  field(:last_entry_id, 5, type: :string, json_name: "lastEntryId")
  field(:num_unfinished_inputs, 6, type: :int32, json_name: "numUnfinishedInputs")
end

defmodule Modal.Client.FunctionGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_name, 1, type: :string, json_name: "appName")
  field(:object_tag, 2, type: :string, json_name: "objectTag")
  field(:environment_name, 4, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.FunctionGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")

  field(:handle_metadata, 2,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "handleMetadata"
  )

  field(:server_warnings, 4,
    repeated: true,
    type: Modal.Client.Warning,
    json_name: "serverWarnings"
  )
end

defmodule Modal.Client.FunctionGetSerializedRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetSerializedRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
end

defmodule Modal.Client.FunctionGetSerializedResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionGetSerializedResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_serialized, 1, type: :bytes, json_name: "functionSerialized")
  field(:class_serialized, 2, type: :bytes, json_name: "classSerialized")
end

defmodule Modal.Client.FunctionHandleMetadata.MethodHandleMetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionHandleMetadata.MethodHandleMetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Modal.Client.FunctionHandleMetadata)
end

defmodule Modal.Client.FunctionHandleMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionHandleMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_name, 2, type: :string, json_name: "functionName")

  field(:function_type, 8,
    type: Modal.Client.Function.FunctionType,
    json_name: "functionType",
    enum: true
  )

  field(:web_url, 28, type: :string, json_name: "webUrl")
  field(:is_method, 39, type: :bool, json_name: "isMethod")
  field(:use_function_id, 40, type: :string, json_name: "useFunctionId")
  field(:use_method_name, 41, type: :string, json_name: "useMethodName")
  field(:definition_id, 42, type: :string, json_name: "definitionId")

  field(:class_parameter_info, 43,
    type: Modal.Client.ClassParameterInfo,
    json_name: "classParameterInfo"
  )

  field(:method_handle_metadata, 44,
    repeated: true,
    type: Modal.Client.FunctionHandleMetadata.MethodHandleMetadataEntry,
    json_name: "methodHandleMetadata",
    map: true
  )

  field(:function_schema, 45, type: Modal.Client.FunctionSchema, json_name: "functionSchema")
  field(:input_plane_url, 46, proto3_optional: true, type: :string, json_name: "inputPlaneUrl")

  field(:input_plane_region, 47,
    proto3_optional: true,
    type: :string,
    json_name: "inputPlaneRegion"
  )

  field(:max_object_size_bytes, 48,
    proto3_optional: true,
    type: :uint64,
    json_name: "maxObjectSizeBytes"
  )

  field(:_experimental_flash_urls, 49,
    repeated: true,
    type: :string,
    json_name: "ExperimentalFlashUrls"
  )

  field(:supported_input_formats, 50,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedInputFormats",
    enum: true
  )

  field(:supported_output_formats, 51,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedOutputFormats",
    enum: true
  )
end

defmodule Modal.Client.FunctionInput do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionInput",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:args_oneof, 0)

  field(:args, 1, type: :bytes, oneof: 0)
  field(:args_blob_id, 7, type: :string, json_name: "argsBlobId", oneof: 0)
  field(:final_input, 9, type: :bool, json_name: "finalInput")
  field(:data_format, 10, type: Modal.Client.DataFormat, json_name: "dataFormat", enum: true)
  field(:method_name, 11, proto3_optional: true, type: :string, json_name: "methodName")
end

defmodule Modal.Client.FunctionMapRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionMapRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:return_exceptions, 3, type: :bool, json_name: "returnExceptions")

  field(:function_call_type, 4,
    type: Modal.Client.FunctionCallType,
    json_name: "functionCallType",
    enum: true
  )

  field(:pipelined_inputs, 5,
    repeated: true,
    type: Modal.Client.FunctionPutInputsItem,
    json_name: "pipelinedInputs"
  )

  field(:function_call_invocation_type, 6,
    type: Modal.Client.FunctionCallInvocationType,
    json_name: "functionCallInvocationType",
    enum: true
  )

  field(:from_spawn_map, 7, type: :bool, json_name: "fromSpawnMap")
end

defmodule Modal.Client.FunctionMapResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionMapResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_id, 1, type: :string, json_name: "functionCallId")

  field(:pipelined_inputs, 2,
    repeated: true,
    type: Modal.Client.FunctionPutInputsResponseItem,
    json_name: "pipelinedInputs"
  )

  field(:retry_policy, 3, type: Modal.Client.FunctionRetryPolicy, json_name: "retryPolicy")
  field(:function_call_jwt, 4, type: :string, json_name: "functionCallJwt")
  field(:sync_client_retries_enabled, 5, type: :bool, json_name: "syncClientRetriesEnabled")
  field(:max_inputs_outstanding, 6, type: :uint32, json_name: "maxInputsOutstanding")
end

defmodule Modal.Client.FunctionOptions do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:secret_ids, 1, repeated: true, type: :string, json_name: "secretIds")
  field(:mount_ids, 2, repeated: true, type: :string, json_name: "mountIds")
  field(:resources, 3, proto3_optional: true, type: Modal.Client.Resources)

  field(:retry_policy, 4,
    proto3_optional: true,
    type: Modal.Client.FunctionRetryPolicy,
    json_name: "retryPolicy"
  )

  field(:concurrency_limit, 5,
    proto3_optional: true,
    type: :uint32,
    json_name: "concurrencyLimit"
  )

  field(:timeout_secs, 6, proto3_optional: true, type: :uint32, json_name: "timeoutSecs")

  field(:task_idle_timeout_secs, 7,
    proto3_optional: true,
    type: :uint32,
    json_name: "taskIdleTimeoutSecs"
  )

  field(:warm_pool_size, 8, proto3_optional: true, type: :uint32, json_name: "warmPoolSize")

  field(:volume_mounts, 9,
    repeated: true,
    type: Modal.Client.VolumeMount,
    json_name: "volumeMounts"
  )

  field(:target_concurrent_inputs, 10,
    proto3_optional: true,
    type: :uint32,
    json_name: "targetConcurrentInputs"
  )

  field(:replace_volume_mounts, 11, type: :bool, json_name: "replaceVolumeMounts")
  field(:replace_secret_ids, 12, type: :bool, json_name: "replaceSecretIds")

  field(:buffer_containers, 13,
    proto3_optional: true,
    type: :uint32,
    json_name: "bufferContainers"
  )

  field(:max_concurrent_inputs, 14,
    proto3_optional: true,
    type: :uint32,
    json_name: "maxConcurrentInputs"
  )

  field(:batch_max_size, 15, proto3_optional: true, type: :uint32, json_name: "batchMaxSize")
  field(:batch_linger_ms, 16, proto3_optional: true, type: :uint64, json_name: "batchLingerMs")

  field(:scheduler_placement, 17,
    proto3_optional: true,
    type: Modal.Client.SchedulerPlacement,
    json_name: "schedulerPlacement"
  )

  field(:cloud_provider_str, 18,
    proto3_optional: true,
    type: :string,
    json_name: "cloudProviderStr"
  )

  field(:replace_cloud_bucket_mounts, 19, type: :bool, json_name: "replaceCloudBucketMounts")

  field(:cloud_bucket_mounts, 20,
    repeated: true,
    type: Modal.Client.CloudBucketMount,
    json_name: "cloudBucketMounts"
  )
end

defmodule Modal.Client.FunctionPrecreateRequest.MethodDefinitionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPrecreateRequest.MethodDefinitionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Modal.Client.MethodDefinition)
end

defmodule Modal.Client.FunctionPrecreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPrecreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:function_name, 2, type: :string, json_name: "functionName")
  field(:existing_function_id, 3, type: :string, json_name: "existingFunctionId")

  field(:function_type, 4,
    type: Modal.Client.Function.FunctionType,
    json_name: "functionType",
    enum: true
  )

  field(:webhook_config, 5, type: Modal.Client.WebhookConfig, json_name: "webhookConfig")
  field(:use_function_id, 6, type: :string, json_name: "useFunctionId")
  field(:use_method_name, 7, type: :string, json_name: "useMethodName")

  field(:method_definitions, 8,
    repeated: true,
    type: Modal.Client.FunctionPrecreateRequest.MethodDefinitionsEntry,
    json_name: "methodDefinitions",
    map: true
  )

  field(:function_schema, 9, type: Modal.Client.FunctionSchema, json_name: "functionSchema")

  field(:supported_input_formats, 10,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedInputFormats",
    enum: true
  )

  field(:supported_output_formats, 11,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedOutputFormats",
    enum: true
  )
end

defmodule Modal.Client.FunctionPrecreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPrecreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")

  field(:handle_metadata, 2,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "handleMetadata"
  )
end

defmodule Modal.Client.FunctionPutInputsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutInputsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:idx, 1, type: :int32)
  field(:input, 2, type: Modal.Client.FunctionInput)
  field(:r2_failed, 3, type: :bool, json_name: "r2Failed")
  field(:r2_throughput_bytes_s, 5, type: :uint64, json_name: "r2ThroughputBytesS")
end

defmodule Modal.Client.FunctionPutInputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutInputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:function_call_id, 3, type: :string, json_name: "functionCallId")
  field(:inputs, 4, repeated: true, type: Modal.Client.FunctionPutInputsItem)
end

defmodule Modal.Client.FunctionPutInputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutInputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:inputs, 1, repeated: true, type: Modal.Client.FunctionPutInputsResponseItem)
end

defmodule Modal.Client.FunctionPutInputsResponseItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutInputsResponseItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:idx, 1, type: :int32)
  field(:input_id, 2, type: :string, json_name: "inputId")
  field(:input_jwt, 3, type: :string, json_name: "inputJwt")
end

defmodule Modal.Client.FunctionPutOutputsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutOutputsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_id, 1, type: :string, json_name: "inputId")
  field(:result, 2, type: Modal.Client.GenericResult)
  field(:input_started_at, 3, type: :double, json_name: "inputStartedAt")
  field(:output_created_at, 4, type: :double, json_name: "outputCreatedAt")
  field(:data_format, 7, type: Modal.Client.DataFormat, json_name: "dataFormat", enum: true)
  field(:retry_count, 8, type: :uint32, json_name: "retryCount")
  field(:function_call_id, 9, type: :string, json_name: "functionCallId")
  field(:function_map_idx, 10, proto3_optional: true, type: :int32, json_name: "functionMapIdx")
end

defmodule Modal.Client.FunctionPutOutputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionPutOutputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:outputs, 4, repeated: true, type: Modal.Client.FunctionPutOutputsItem)
  field(:requested_at, 5, type: :double, json_name: "requestedAt")
end

defmodule Modal.Client.FunctionRetryInputsItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionRetryInputsItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_jwt, 1, type: :string, json_name: "inputJwt")
  field(:input, 2, type: Modal.Client.FunctionInput)
  field(:retry_count, 3, type: :uint32, json_name: "retryCount")
end

defmodule Modal.Client.FunctionRetryInputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionRetryInputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_call_jwt, 1, type: :string, json_name: "functionCallJwt")
  field(:inputs, 2, repeated: true, type: Modal.Client.FunctionRetryInputsItem)
end

defmodule Modal.Client.FunctionRetryInputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionRetryInputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_jwts, 1, repeated: true, type: :string, json_name: "inputJwts")
end

defmodule Modal.Client.FunctionRetryPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionRetryPolicy",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:backoff_coefficient, 1, type: :float, json_name: "backoffCoefficient")
  field(:initial_delay_ms, 2, type: :uint32, json_name: "initialDelayMs")
  field(:max_delay_ms, 3, type: :uint32, json_name: "maxDelayMs")
  field(:retries, 18, type: :uint32)
end

defmodule Modal.Client.FunctionSchema do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionSchema",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:schema_type, 1,
    type: Modal.Client.FunctionSchema.FunctionSchemaType,
    json_name: "schemaType",
    enum: true
  )

  field(:arguments, 2, repeated: true, type: Modal.Client.ClassParameterSpec)
  field(:return_type, 3, type: Modal.Client.GenericPayloadType, json_name: "returnType")
end

defmodule Modal.Client.FunctionStats do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionStats",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:backlog, 1, type: :uint32)
  field(:num_total_tasks, 3, type: :uint32, json_name: "numTotalTasks")
  field(:num_running_inputs, 4, type: :uint32, json_name: "numRunningInputs")
end

defmodule Modal.Client.FunctionUpdateSchedulingParamsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionUpdateSchedulingParamsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:warm_pool_size_override, 2, type: :uint32, json_name: "warmPoolSizeOverride")
  field(:settings, 3, type: Modal.Client.AutoscalerSettings)
end

defmodule Modal.Client.FunctionUpdateSchedulingParamsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.FunctionUpdateSchedulingParamsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.GPUConfig do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.GPUConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:type, 1, type: Modal.Client.GPUType, enum: true)
  field(:count, 2, type: :uint32)
  field(:gpu_type, 4, type: :string, json_name: "gpuType")
end

defmodule Modal.Client.GeneratorDone do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.GeneratorDone",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items_total, 1, type: :uint64, json_name: "itemsTotal")
end

defmodule Modal.Client.GenericPayloadType do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.GenericPayloadType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:base_type, 1, type: Modal.Client.ParameterType, json_name: "baseType", enum: true)

  field(:sub_types, 2,
    repeated: true,
    type: Modal.Client.GenericPayloadType,
    json_name: "subTypes"
  )
end

defmodule Modal.Client.GenericResult do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.GenericResult",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:status, 1, type: Modal.Client.GenericResult.GenericStatus, enum: true)
  field(:exception, 2, type: :string)
  field(:exitcode, 3, type: :int32)
  field(:traceback, 4, type: :string)
  field(:serialized_tb, 11, type: :bytes, json_name: "serializedTb")
  field(:tb_line_cache, 12, type: :bytes, json_name: "tbLineCache")
  field(:data, 5, type: :bytes, oneof: 0)
  field(:data_blob_id, 10, type: :string, json_name: "dataBlobId", oneof: 0)
  field(:propagation_reason, 13, type: :string, json_name: "propagationReason")
end

defmodule Modal.Client.HTTPConfig do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.HTTPConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:port, 1, type: :uint32)
  field(:proxy_regions, 2, repeated: true, type: :string, json_name: "proxyRegions")
  field(:startup_timeout, 3, type: :uint32, json_name: "startupTimeout")
  field(:exit_grace_period, 4, type: :uint32, json_name: "exitGracePeriod")
  field(:h2_enabled, 5, type: :bool, json_name: "h2Enabled")
  field(:target_concurrency, 6, type: :uint32, json_name: "targetConcurrency")
end

defmodule Modal.Client.Image.BuildArgsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Image.BuildArgsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.Image do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Image",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:base_images, 5, repeated: true, type: Modal.Client.BaseImage, json_name: "baseImages")
  field(:dockerfile_commands, 6, repeated: true, type: :string, json_name: "dockerfileCommands")

  field(:context_files, 7,
    repeated: true,
    type: Modal.Client.ImageContextFile,
    json_name: "contextFiles"
  )

  field(:version, 11, type: :string)
  field(:secret_ids, 12, repeated: true, type: :string, json_name: "secretIds")
  field(:context_mount_id, 15, type: :string, json_name: "contextMountId")
  field(:gpu_config, 16, type: Modal.Client.GPUConfig, json_name: "gpuConfig")

  field(:image_registry_config, 17,
    type: Modal.Client.ImageRegistryConfig,
    json_name: "imageRegistryConfig"
  )

  field(:build_function_def, 14, type: :string, json_name: "buildFunctionDef")
  field(:build_function_globals, 18, type: :bytes, json_name: "buildFunctionGlobals")
  field(:runtime, 19, type: :string)
  field(:runtime_debug, 20, type: :bool, json_name: "runtimeDebug")
  field(:build_function, 21, type: Modal.Client.BuildFunction, json_name: "buildFunction")

  field(:build_args, 22,
    repeated: true,
    type: Modal.Client.Image.BuildArgsEntry,
    json_name: "buildArgs",
    map: true
  )

  field(:volume_mounts, 23,
    repeated: true,
    type: Modal.Client.VolumeMount,
    json_name: "volumeMounts"
  )
end

defmodule Modal.Client.ImageContextFile do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageContextFile",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:filename, 1, type: :string)
  field(:data, 2, type: :bytes)
end

defmodule Modal.Client.ImageDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
end

defmodule Modal.Client.ImageFromIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageFromIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
end

defmodule Modal.Client.ImageFromIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageFromIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:metadata, 2, type: Modal.Client.ImageMetadata)
end

defmodule Modal.Client.ImageGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image, 2, type: Modal.Client.Image)
  field(:app_id, 4, type: :string, json_name: "appId")
  field(:existing_image_id, 5, type: :string, json_name: "existingImageId")
  field(:build_function_id, 6, type: :string, json_name: "buildFunctionId")
  field(:force_build, 7, type: :bool, json_name: "forceBuild")
  field(:namespace, 8, type: Modal.Client.DeploymentNamespace, enum: true)
  field(:builder_version, 9, type: :string, json_name: "builderVersion")
  field(:allow_global_deployment, 10, type: :bool, json_name: "allowGlobalDeployment")
  field(:ignore_cache, 11, type: :bool, json_name: "ignoreCache")
end

defmodule Modal.Client.ImageGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:result, 2, type: Modal.Client.GenericResult)
  field(:metadata, 3, type: Modal.Client.ImageMetadata)
end

defmodule Modal.Client.ImageJoinStreamingRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageJoinStreamingRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:timeout, 2, type: :float)
  field(:last_entry_id, 3, type: :string, json_name: "lastEntryId")
  field(:include_logs_for_finished, 4, type: :bool, json_name: "includeLogsForFinished")
end

defmodule Modal.Client.ImageJoinStreamingResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageJoinStreamingResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
  field(:task_logs, 2, repeated: true, type: Modal.Client.TaskLogs, json_name: "taskLogs")
  field(:entry_id, 3, type: :string, json_name: "entryId")
  field(:eof, 4, type: :bool)
  field(:metadata, 5, type: Modal.Client.ImageMetadata)
end

defmodule Modal.Client.ImageMetadata.PythonPackagesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageMetadata.PythonPackagesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.ImageMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:python_version_info, 1,
    proto3_optional: true,
    type: :string,
    json_name: "pythonVersionInfo"
  )

  field(:python_packages, 2,
    repeated: true,
    type: Modal.Client.ImageMetadata.PythonPackagesEntry,
    json_name: "pythonPackages",
    map: true
  )

  field(:workdir, 3, proto3_optional: true, type: :string)
  field(:libc_version_info, 4, proto3_optional: true, type: :string, json_name: "libcVersionInfo")

  field(:image_builder_version, 5,
    proto3_optional: true,
    type: :string,
    json_name: "imageBuilderVersion"
  )
end

defmodule Modal.Client.ImageRegistryConfig do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ImageRegistryConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:registry_auth_type, 1,
    type: Modal.Client.RegistryAuthType,
    json_name: "registryAuthType",
    enum: true
  )

  field(:secret_id, 2, type: :string, json_name: "secretId")
end

defmodule Modal.Client.InputCallGraphInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.InputCallGraphInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_id, 1, type: :string, json_name: "inputId")
  field(:status, 2, type: Modal.Client.GenericResult.GenericStatus, enum: true)
  field(:function_call_id, 3, type: :string, json_name: "functionCallId")
  field(:task_id, 4, type: :string, json_name: "taskId")
end

defmodule Modal.Client.InputCategoryInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.InputCategoryInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:total, 1, type: :int32)
  field(:latest, 2, repeated: true, type: Modal.Client.InputInfo)
end

defmodule Modal.Client.InputInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.InputInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_id, 1, type: :string, json_name: "inputId")
  field(:idx, 2, type: :int32)
  field(:task_id, 3, type: :string, json_name: "taskId")
  field(:started_at, 4, type: :double, json_name: "startedAt")
  field(:finished_at, 5, type: :double, json_name: "finishedAt")
  field(:task_startup_time, 6, type: :double, json_name: "taskStartupTime")
  field(:task_first_input, 7, type: :bool, json_name: "taskFirstInput")
end

defmodule Modal.Client.ListPagination do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ListPagination",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:max_objects, 1, type: :int32, json_name: "maxObjects")
  field(:created_before, 2, type: :double, json_name: "createdBefore")
end

defmodule Modal.Client.MapAwaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapAwaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:call_info, 0)

  field(:function_call_id, 1, type: :string, json_name: "functionCallId", oneof: 0)
  field(:map_token, 5, type: :string, json_name: "mapToken", oneof: 0)
  field(:last_entry_id, 2, type: :string, json_name: "lastEntryId")
  field(:requested_at, 3, type: :double, json_name: "requestedAt")
  field(:timeout, 4, type: :float)
end

defmodule Modal.Client.MapAwaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapAwaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:outputs, 1, repeated: true, type: Modal.Client.FunctionGetOutputsItem)
  field(:last_entry_id, 2, type: :string, json_name: "lastEntryId")
end

defmodule Modal.Client.MapCheckInputsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapCheckInputsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:last_entry_id, 1, type: :string, json_name: "lastEntryId")
  field(:timeout, 2, type: :float)
  field(:attempt_tokens, 3, repeated: true, type: :string, json_name: "attemptTokens")
end

defmodule Modal.Client.MapCheckInputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapCheckInputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:lost, 1, repeated: true, type: :bool)
end

defmodule Modal.Client.MapStartOrContinueItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapStartOrContinueItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input, 1, type: Modal.Client.FunctionPutInputsItem)
  field(:attempt_token, 2, proto3_optional: true, type: :string, json_name: "attemptToken")
end

defmodule Modal.Client.MapStartOrContinueRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapStartOrContinueRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:call_info, 0)

  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:parent_input_id, 2, type: :string, json_name: "parentInputId")
  field(:function_call_id, 3, type: :string, json_name: "functionCallId", oneof: 0)
  field(:map_token, 5, type: :string, json_name: "mapToken", oneof: 0)
  field(:items, 4, repeated: true, type: Modal.Client.MapStartOrContinueItem)
end

defmodule Modal.Client.MapStartOrContinueResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MapStartOrContinueResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:map_token, 6, type: :string, json_name: "mapToken")
  field(:function_id, 1, type: :string, json_name: "functionId")
  field(:function_call_id, 2, type: :string, json_name: "functionCallId")
  field(:max_inputs_outstanding, 3, type: :uint32, json_name: "maxInputsOutstanding")
  field(:attempt_tokens, 4, repeated: true, type: :string, json_name: "attemptTokens")
  field(:retry_policy, 5, type: Modal.Client.FunctionRetryPolicy, json_name: "retryPolicy")
end

defmodule Modal.Client.MethodDefinition do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MethodDefinition",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:function_name, 1, type: :string, json_name: "functionName")

  field(:function_type, 2,
    type: Modal.Client.Function.FunctionType,
    json_name: "functionType",
    enum: true
  )

  field(:webhook_config, 3, type: Modal.Client.WebhookConfig, json_name: "webhookConfig")
  field(:web_url, 4, type: :string, json_name: "webUrl")
  field(:web_url_info, 5, type: Modal.Client.WebUrlInfo, json_name: "webUrlInfo")

  field(:custom_domain_info, 6,
    repeated: true,
    type: Modal.Client.CustomDomainInfo,
    json_name: "customDomainInfo"
  )

  field(:function_schema, 7, type: Modal.Client.FunctionSchema, json_name: "functionSchema")

  field(:supported_input_formats, 8,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedInputFormats",
    enum: true
  )

  field(:supported_output_formats, 9,
    repeated: true,
    type: Modal.Client.DataFormat,
    json_name: "supportedOutputFormats",
    enum: true
  )
end

defmodule Modal.Client.MountFile do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountFile",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:filename, 1, type: :string)
  field(:sha256_hex, 3, type: :string, json_name: "sha256Hex")
  field(:size, 4, proto3_optional: true, type: :uint64)
  field(:mode, 5, proto3_optional: true, type: :uint32)
end

defmodule Modal.Client.MountGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:namespace, 2, type: Modal.Client.DeploymentNamespace, enum: true)
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )

  field(:files, 5, repeated: true, type: Modal.Client.MountFile)
  field(:app_id, 6, type: :string, json_name: "appId")
end

defmodule Modal.Client.MountGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:mount_id, 1, type: :string, json_name: "mountId")
  field(:handle_metadata, 2, type: Modal.Client.MountHandleMetadata, json_name: "handleMetadata")
end

defmodule Modal.Client.MountHandleMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountHandleMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:content_checksum_sha256_hex, 1, type: :string, json_name: "contentChecksumSha256Hex")
end

defmodule Modal.Client.MountPutFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountPutFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:sha256_hex, 2, type: :string, json_name: "sha256Hex")
  field(:data, 3, type: :bytes, oneof: 0)
  field(:data_blob_id, 5, type: :string, json_name: "dataBlobId", oneof: 0)
end

defmodule Modal.Client.MountPutFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MountPutFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exists, 2, type: :bool)
end

defmodule Modal.Client.MultiPartUpload do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MultiPartUpload",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:part_length, 1, type: :int64, json_name: "partLength")
  field(:upload_urls, 2, repeated: true, type: :string, json_name: "uploadUrls")
  field(:completion_url, 3, type: :string, json_name: "completionUrl")
end

defmodule Modal.Client.MultiPartUploadList do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.MultiPartUploadList",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.MultiPartUpload)
end

defmodule Modal.Client.NetworkAccess do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NetworkAccess",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:network_access_type, 1,
    type: Modal.Client.NetworkAccess.NetworkAccessType,
    json_name: "networkAccessType",
    enum: true
  )

  field(:allowed_cidrs, 2, repeated: true, type: :string, json_name: "allowedCidrs")
end

defmodule Modal.Client.NotebookKernelPublishResultsRequest.ExecuteReply do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookKernelPublishResultsRequest.ExecuteReply",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:status, 1, type: :string)
  field(:execution_count, 2, type: :uint32, json_name: "executionCount")
  field(:duration, 3, type: :double)
end

defmodule Modal.Client.NotebookKernelPublishResultsRequest.CellResult do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookKernelPublishResultsRequest.CellResult",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:result_type, 0)

  field(:cell_id, 1, type: :string, json_name: "cellId")
  field(:output, 2, type: Modal.Client.NotebookOutput, oneof: 0)
  field(:clear_output, 3, type: :bool, json_name: "clearOutput", oneof: 0)

  field(:execute_reply, 4,
    type: Modal.Client.NotebookKernelPublishResultsRequest.ExecuteReply,
    json_name: "executeReply",
    oneof: 0
  )
end

defmodule Modal.Client.NotebookKernelPublishResultsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookKernelPublishResultsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:notebook_id, 1, type: :string, json_name: "notebookId")

  field(:results, 2,
    repeated: true,
    type: Modal.Client.NotebookKernelPublishResultsRequest.CellResult
  )
end

defmodule Modal.Client.NotebookOutput.ExecuteResult do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookOutput.ExecuteResult",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:execution_count, 1, type: :uint32, json_name: "executionCount")
  field(:data, 2, type: Google.Protobuf.Struct)
  field(:metadata, 3, type: Google.Protobuf.Struct)
end

defmodule Modal.Client.NotebookOutput.DisplayData do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookOutput.DisplayData",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:data, 1, type: Google.Protobuf.Struct)
  field(:metadata, 2, type: Google.Protobuf.Struct)

  field(:transient_display_id, 3,
    proto3_optional: true,
    type: :string,
    json_name: "transientDisplayId"
  )
end

defmodule Modal.Client.NotebookOutput.Stream do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookOutput.Stream",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:text, 2, type: :string)
end

defmodule Modal.Client.NotebookOutput.Error do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookOutput.Error",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:ename, 1, type: :string)
  field(:evalue, 2, type: :string)
  field(:traceback, 3, repeated: true, type: :string)
end

defmodule Modal.Client.NotebookOutput do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.NotebookOutput",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:output_type, 0)

  field(:execute_result, 1,
    type: Modal.Client.NotebookOutput.ExecuteResult,
    json_name: "executeResult",
    oneof: 0
  )

  field(:display_data, 2,
    type: Modal.Client.NotebookOutput.DisplayData,
    json_name: "displayData",
    oneof: 0
  )

  field(:stream, 3, type: Modal.Client.NotebookOutput.Stream, oneof: 0)
  field(:error, 4, type: Modal.Client.NotebookOutput.Error, oneof: 0)
end

defmodule Modal.Client.Object do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Object",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:handle_metadata_oneof, 0)

  field(:object_id, 1, type: :string, json_name: "objectId")

  field(:function_handle_metadata, 3,
    type: Modal.Client.FunctionHandleMetadata,
    json_name: "functionHandleMetadata",
    oneof: 0
  )

  field(:mount_handle_metadata, 4,
    type: Modal.Client.MountHandleMetadata,
    json_name: "mountHandleMetadata",
    oneof: 0
  )

  field(:class_handle_metadata, 5,
    type: Modal.Client.ClassHandleMetadata,
    json_name: "classHandleMetadata",
    oneof: 0
  )

  field(:sandbox_handle_metadata, 6,
    type: Modal.Client.SandboxHandleMetadata,
    json_name: "sandboxHandleMetadata",
    oneof: 0
  )

  field(:volume_metadata, 7,
    type: Modal.Client.VolumeMetadata,
    json_name: "volumeMetadata",
    oneof: 0
  )
end

defmodule Modal.Client.ObjectDependency do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ObjectDependency",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:object_id, 1, type: :string, json_name: "objectId")
end

defmodule Modal.Client.PTYInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.PTYInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:enabled, 1, type: :bool)
  field(:winsz_rows, 2, type: :uint32, json_name: "winszRows")
  field(:winsz_cols, 3, type: :uint32, json_name: "winszCols")
  field(:env_term, 4, type: :string, json_name: "envTerm")
  field(:env_colorterm, 5, type: :string, json_name: "envColorterm")
  field(:env_term_program, 6, type: :string, json_name: "envTermProgram")
  field(:pty_type, 7, type: Modal.Client.PTYInfo.PTYType, json_name: "ptyType", enum: true)
  field(:no_terminate_on_idle_stdin, 8, type: :bool, json_name: "noTerminateOnIdleStdin")
end

defmodule Modal.Client.PortSpec do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.PortSpec",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:port, 1, type: :uint32)
  field(:unencrypted, 2, type: :bool)

  field(:tunnel_type, 3,
    proto3_optional: true,
    type: Modal.Client.TunnelType,
    json_name: "tunnelType",
    enum: true
  )
end

defmodule Modal.Client.PortSpecs do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.PortSpecs",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:ports, 1, repeated: true, type: Modal.Client.PortSpec)
end

defmodule Modal.Client.Probe.ExecCommand do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Probe.ExecCommand",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:argv, 1, repeated: true, type: :string)
end

defmodule Modal.Client.Probe do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Probe",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:probe_oneof, 0)

  field(:tcp_port, 1, type: :uint32, json_name: "tcpPort", oneof: 0)

  field(:exec_command, 2,
    type: Modal.Client.Probe.ExecCommand,
    json_name: "execCommand",
    oneof: 0
  )

  field(:interval_ms, 3, proto3_optional: true, type: :uint32, json_name: "intervalMs")
end

defmodule Modal.Client.Proxy do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Proxy",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:created_at, 2, type: :double, json_name: "createdAt")
  field(:environment_name, 3, type: :string, json_name: "environmentName")
  field(:proxy_ips, 4, repeated: true, type: Modal.Client.ProxyIp, json_name: "proxyIps")
  field(:proxy_id, 5, type: :string, json_name: "proxyId")
  field(:region, 6, type: :string)
end

defmodule Modal.Client.ProxyAddIpRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyAddIpRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_id, 1, type: :string, json_name: "proxyId")
end

defmodule Modal.Client.ProxyAddIpResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyAddIpResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_ip, 1, type: Modal.Client.ProxyIp, json_name: "proxyIp")
end

defmodule Modal.Client.ProxyCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
  field(:region, 3, type: :string)
end

defmodule Modal.Client.ProxyCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy, 1, type: Modal.Client.Proxy)
end

defmodule Modal.Client.ProxyDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_id, 1, type: :string, json_name: "proxyId")
end

defmodule Modal.Client.ProxyGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )
end

defmodule Modal.Client.ProxyGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_id, 1, type: :string, json_name: "proxyId")
end

defmodule Modal.Client.ProxyGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.ProxyGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy, 1, type: Modal.Client.Proxy)
end

defmodule Modal.Client.ProxyInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:elastic_ip, 1, type: :string, json_name: "elasticIp")
  field(:proxy_key, 2, type: :string, json_name: "proxyKey")
  field(:remote_addr, 3, type: :string, json_name: "remoteAddr")
  field(:remote_port, 4, type: :int32, json_name: "remotePort")
  field(:proxy_type, 5, type: Modal.Client.ProxyType, json_name: "proxyType", enum: true)
end

defmodule Modal.Client.ProxyIp do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyIp",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_ip, 1, type: :string, json_name: "proxyIp")
  field(:status, 2, type: Modal.Client.ProxyIpStatus, enum: true)
  field(:created_at, 3, type: :double, json_name: "createdAt")
  field(:environment_name, 4, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.ProxyListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxies, 1, repeated: true, type: Modal.Client.Proxy)
end

defmodule Modal.Client.ProxyRemoveIpRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ProxyRemoveIpRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:proxy_ip, 1, type: :string, json_name: "proxyIp")
end

defmodule Modal.Client.QueueClearRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueClearRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:partition_key, 2, type: :bytes, json_name: "partitionKey")
  field(:all_partitions, 3, type: :bool, json_name: "allPartitions")
end

defmodule Modal.Client.QueueDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
end

defmodule Modal.Client.QueueGetByIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetByIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
end

defmodule Modal.Client.QueueGetByIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetByIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:metadata, 2, type: Modal.Client.QueueMetadata)
end

defmodule Modal.Client.QueueGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )
end

defmodule Modal.Client.QueueGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:metadata, 2, type: Modal.Client.QueueMetadata)
end

defmodule Modal.Client.QueueGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:timeout, 3, type: :float)
  field(:n_values, 4, type: :int32, json_name: "nValues")
  field(:partition_key, 5, type: :bytes, json_name: "partitionKey")
end

defmodule Modal.Client.QueueGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:values, 2, repeated: true, type: :bytes)
end

defmodule Modal.Client.QueueHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
end

defmodule Modal.Client.QueueItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:value, 1, type: :bytes)
  field(:entry_id, 2, type: :string, json_name: "entryId")
end

defmodule Modal.Client.QueueLenRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueLenRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:partition_key, 2, type: :bytes, json_name: "partitionKey")
  field(:total, 3, type: :bool)
end

defmodule Modal.Client.QueueLenResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueLenResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:len, 1, type: :int32)
end

defmodule Modal.Client.QueueListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:total_size_limit, 2, type: :int32, json_name: "totalSizeLimit")
  field(:pagination, 3, type: Modal.Client.ListPagination)
end

defmodule Modal.Client.QueueListResponse.QueueInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueListResponse.QueueInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:created_at, 2, type: :double, json_name: "createdAt")
  field(:num_partitions, 3, type: :int32, json_name: "numPartitions")
  field(:total_size, 4, type: :int32, json_name: "totalSize")
  field(:queue_id, 5, type: :string, json_name: "queueId")
  field(:metadata, 6, type: Modal.Client.QueueMetadata)
end

defmodule Modal.Client.QueueListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queues, 1, repeated: true, type: Modal.Client.QueueListResponse.QueueInfo)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.QueueMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:creation_info, 2, type: Modal.Client.CreationInfo, json_name: "creationInfo")
end

defmodule Modal.Client.QueueNextItemsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueNextItemsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:partition_key, 2, type: :bytes, json_name: "partitionKey")
  field(:last_entry_id, 3, type: :string, json_name: "lastEntryId")
  field(:item_poll_timeout, 4, type: :float, json_name: "itemPollTimeout")
end

defmodule Modal.Client.QueueNextItemsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueueNextItemsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.QueueItem)
end

defmodule Modal.Client.QueuePutRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.QueuePutRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:queue_id, 1, type: :string, json_name: "queueId")
  field(:values, 4, repeated: true, type: :bytes)
  field(:partition_key, 5, type: :bytes, json_name: "partitionKey")
  field(:partition_ttl_seconds, 6, type: :int32, json_name: "partitionTtlSeconds")
end

defmodule Modal.Client.RPCRetryPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RPCRetryPolicy",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:retry_after_secs, 1, type: :float, json_name: "retryAfterSecs")
end

defmodule Modal.Client.RPCStatus do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RPCStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:code, 1, type: :int32)
  field(:message, 2, type: :string)
  field(:details, 3, repeated: true, type: Google.Protobuf.Any)
end

defmodule Modal.Client.RateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RateLimit",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:limit, 1, type: :int32)
  field(:interval, 2, type: Modal.Client.RateLimitInterval, enum: true)
end

defmodule Modal.Client.ResourceInfo.ResourceValue do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ResourceInfo.ResourceValue",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:value, 1, type: :uint32)
  field(:is_default, 2, type: :bool, json_name: "isDefault")
end

defmodule Modal.Client.ResourceInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ResourceInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:memory_mb, 1, type: Modal.Client.ResourceInfo.ResourceValue, json_name: "memoryMb")
  field(:milli_cpu, 2, type: Modal.Client.ResourceInfo.ResourceValue, json_name: "milliCpu")
  field(:gpu_type, 3, type: :string, json_name: "gpuType")
  field(:memory_mb_max, 4, type: :uint32, json_name: "memoryMbMax")
  field(:ephemeral_disk_mb, 5, type: :uint32, json_name: "ephemeralDiskMb")
  field(:milli_cpu_max, 6, type: :uint32, json_name: "milliCpuMax")
end

defmodule Modal.Client.Resources do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Resources",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:memory_mb, 2, type: :uint32, json_name: "memoryMb")
  field(:milli_cpu, 3, type: :uint32, json_name: "milliCpu")
  field(:gpu_config, 4, type: Modal.Client.GPUConfig, json_name: "gpuConfig")
  field(:memory_mb_max, 5, type: :uint32, json_name: "memoryMbMax")
  field(:ephemeral_disk_mb, 6, type: :uint32, json_name: "ephemeralDiskMb")
  field(:milli_cpu_max, 7, type: :uint32, json_name: "milliCpuMax")
  field(:rdma, 8, type: :bool)
end

defmodule Modal.Client.RuntimeInputMessage do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RuntimeInputMessage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:message, 1, type: :bytes)
  field(:message_index, 2, type: :uint64, json_name: "messageIndex")
  field(:eof, 3, type: :bool)
end

defmodule Modal.Client.RuntimeOutputBatch do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RuntimeOutputBatch",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.RuntimeOutputMessage)
  field(:batch_index, 2, type: :uint64, json_name: "batchIndex")
  field(:exit_code, 3, proto3_optional: true, type: :int32, json_name: "exitCode")
  field(:stdout, 4, repeated: true, type: Modal.Client.RuntimeOutputMessage)
  field(:stderr, 5, repeated: true, type: Modal.Client.RuntimeOutputMessage)
  field(:info, 6, repeated: true, type: Modal.Client.RuntimeOutputMessage)
end

defmodule Modal.Client.RuntimeOutputMessage do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.RuntimeOutputMessage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_descriptor, 1,
    type: Modal.Client.FileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )

  field(:message, 2, type: :string)
  field(:message_bytes, 3, type: :bytes, json_name: "messageBytes")
end

defmodule Modal.Client.S3Mount do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.S3Mount",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:bucket_name, 1, type: :string, json_name: "bucketName")
  field(:mount_path, 2, type: :string, json_name: "mountPath")
  field(:credentials_secret_id, 3, type: :string, json_name: "credentialsSecretId")
  field(:read_only, 4, type: :bool, json_name: "readOnly")
end

defmodule Modal.Client.Sandbox.ExperimentalOptionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Sandbox.ExperimentalOptionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :bool)
end

defmodule Modal.Client.Sandbox do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Sandbox",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:open_ports_oneof, 0)

  field(:entrypoint_args, 1, repeated: true, type: :string, json_name: "entrypointArgs")
  field(:mount_ids, 2, repeated: true, type: :string, json_name: "mountIds")
  field(:image_id, 3, type: :string, json_name: "imageId")
  field(:secret_ids, 4, repeated: true, type: :string, json_name: "secretIds")
  field(:resources, 5, type: Modal.Client.Resources)

  field(:cloud_provider, 6,
    type: Modal.Client.CloudProvider,
    json_name: "cloudProvider",
    enum: true
  )

  field(:timeout_secs, 7, type: :uint32, json_name: "timeoutSecs")
  field(:workdir, 8, proto3_optional: true, type: :string)

  field(:nfs_mounts, 9,
    repeated: true,
    type: Modal.Client.SharedVolumeMount,
    json_name: "nfsMounts"
  )

  field(:runtime_debug, 10, type: :bool, json_name: "runtimeDebug")
  field(:block_network, 11, type: :bool, json_name: "blockNetwork")
  field(:s3_mounts, 12, repeated: true, type: Modal.Client.S3Mount, json_name: "s3Mounts")

  field(:cloud_bucket_mounts, 14,
    repeated: true,
    type: Modal.Client.CloudBucketMount,
    json_name: "cloudBucketMounts"
  )

  field(:volume_mounts, 13,
    repeated: true,
    type: Modal.Client.VolumeMount,
    json_name: "volumeMounts"
  )

  field(:pty_info, 15, type: Modal.Client.PTYInfo, json_name: "ptyInfo")

  field(:scheduler_placement, 17,
    proto3_optional: true,
    type: Modal.Client.SchedulerPlacement,
    json_name: "schedulerPlacement"
  )

  field(:worker_id, 19, type: :string, json_name: "workerId")
  field(:open_ports, 20, type: Modal.Client.PortSpecs, json_name: "openPorts", oneof: 0)
  field(:i6pn_enabled, 21, type: :bool, json_name: "i6pnEnabled")
  field(:network_access, 22, type: Modal.Client.NetworkAccess, json_name: "networkAccess")
  field(:proxy_id, 23, proto3_optional: true, type: :string, json_name: "proxyId")
  field(:enable_snapshot, 24, type: :bool, json_name: "enableSnapshot")
  field(:snapshot_version, 25, proto3_optional: true, type: :uint32, json_name: "snapshotVersion")
  field(:cloud_provider_str, 26, type: :string, json_name: "cloudProviderStr")

  field(:runsc_runtime_version, 27,
    proto3_optional: true,
    type: :string,
    json_name: "runscRuntimeVersion"
  )

  field(:runtime, 28, proto3_optional: true, type: :string)
  field(:verbose, 29, type: :bool)
  field(:name, 30, proto3_optional: true, type: :string)

  field(:experimental_options, 31,
    repeated: true,
    type: Modal.Client.Sandbox.ExperimentalOptionsEntry,
    json_name: "experimentalOptions",
    map: true
  )

  field(:preload_path_prefixes, 32,
    repeated: true,
    type: :string,
    json_name: "preloadPathPrefixes"
  )

  field(:idle_timeout_secs, 33,
    proto3_optional: true,
    type: :uint32,
    json_name: "idleTimeoutSecs"
  )

  field(:direct_sandbox_commands_enabled, 34,
    type: :bool,
    json_name: "directSandboxCommandsEnabled"
  )

  field(:_restore_instance_type, 35, type: :string, json_name: "RestoreInstanceType")
  field(:custom_domain, 36, type: :string, json_name: "customDomain")
  field(:include_oidc_identity_token, 37, type: :bool, json_name: "includeOidcIdentityToken")

  field(:readiness_probe, 38,
    proto3_optional: true,
    type: Modal.Client.Probe,
    json_name: "readinessProbe"
  )
end

defmodule Modal.Client.SandboxCreateConnectTokenRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateConnectTokenRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:user_metadata, 2, type: :string, json_name: "userMetadata")
end

defmodule Modal.Client.SandboxCreateConnectTokenResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateConnectTokenResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)
  field(:token, 2, type: :string)
end

defmodule Modal.Client.SandboxCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:definition, 2, type: Modal.Client.Sandbox)
  field(:environment_name, 3, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.SandboxCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxCreateV2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateV2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:definition, 2, type: Modal.Client.Sandbox)
end

defmodule Modal.Client.SandboxCreateV2Response do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxCreateV2Response",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:tunnels, 2, repeated: true, type: Modal.Client.TunnelData)
  field(:task_id, 3, type: :string, json_name: "taskId")
end

defmodule Modal.Client.SandboxGetFromNameRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetFromNameRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_name, 1, type: :string, json_name: "sandboxName")
  field(:environment_name, 2, type: :string, json_name: "environmentName")
  field(:app_name, 3, type: :string, json_name: "appName")
end

defmodule Modal.Client.SandboxGetFromNameResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetFromNameResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxGetLogsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetLogsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")

  field(:file_descriptor, 2,
    type: Modal.Client.FileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )

  field(:timeout, 3, type: :float)
  field(:last_entry_id, 4, type: :string, json_name: "lastEntryId")
end

defmodule Modal.Client.SandboxGetResourceUsageRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetResourceUsageRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxGetResourceUsageResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetResourceUsageResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cpu_core_nanosecs, 1, type: :uint64, json_name: "cpuCoreNanosecs")
  field(:mem_gib_nanosecs, 2, type: :uint64, json_name: "memGibNanosecs")
  field(:gpu_nanosecs, 3, type: :uint64, json_name: "gpuNanosecs")
  field(:gpu_type, 4, proto3_optional: true, type: :string, json_name: "gpuType")
end

defmodule Modal.Client.SandboxGetTaskIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetTaskIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:timeout, 2, proto3_optional: true, type: :float)
  field(:wait_until_ready, 3, type: :bool, json_name: "waitUntilReady")
end

defmodule Modal.Client.SandboxGetTaskIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetTaskIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, proto3_optional: true, type: :string, json_name: "taskId")

  field(:task_result, 2,
    proto3_optional: true,
    type: Modal.Client.GenericResult,
    json_name: "taskResult"
  )
end

defmodule Modal.Client.SandboxGetTunnelsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetTunnelsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxGetTunnelsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxGetTunnelsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
  field(:tunnels, 2, repeated: true, type: Modal.Client.TunnelData)
end

defmodule Modal.Client.SandboxHandleMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxHandleMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
end

defmodule Modal.Client.SandboxInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:id, 1, type: :string)
  field(:created_at, 3, type: :double, json_name: "createdAt")
  field(:task_info, 4, type: Modal.Client.TaskInfo, json_name: "taskInfo")
  field(:app_id, 5, type: :string, json_name: "appId")
  field(:tags, 6, repeated: true, type: Modal.Client.SandboxTag)
  field(:name, 7, type: :string)
  field(:image_id, 8, type: :string, json_name: "imageId")
  field(:resource_info, 9, type: Modal.Client.ResourceInfo, json_name: "resourceInfo")
  field(:regions, 10, repeated: true, type: :string)
  field(:timeout_secs, 11, type: :uint32, json_name: "timeoutSecs")

  field(:idle_timeout_secs, 12,
    proto3_optional: true,
    type: :uint32,
    json_name: "idleTimeoutSecs"
  )

  field(:ready_at, 13, proto3_optional: true, type: :double, json_name: "readyAt")
end

defmodule Modal.Client.SandboxListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:before_timestamp, 2, type: :double, json_name: "beforeTimestamp")
  field(:environment_name, 3, type: :string, json_name: "environmentName")
  field(:include_finished, 4, type: :bool, json_name: "includeFinished")
  field(:tags, 5, repeated: true, type: Modal.Client.SandboxTag)
end

defmodule Modal.Client.SandboxListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandboxes, 1, repeated: true, type: Modal.Client.SandboxInfo)
end

defmodule Modal.Client.SandboxRestoreRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxRestoreRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:snapshot_id, 1, type: :string, json_name: "snapshotId")
  field(:sandbox_name_override, 2, type: :string, json_name: "sandboxNameOverride")

  field(:sandbox_name_override_type, 3,
    type: Modal.Client.SandboxRestoreRequest.SandboxNameOverrideType,
    json_name: "sandboxNameOverrideType",
    enum: true
  )
end

defmodule Modal.Client.SandboxRestoreResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxRestoreResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxSnapshotFsAsyncGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotFsAsyncGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxSnapshotFsAsyncRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotFsAsyncRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxSnapshotFsAsyncResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotFsAsyncResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
end

defmodule Modal.Client.SandboxSnapshotFsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotFsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxSnapshotFsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotFsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:image_id, 1, type: :string, json_name: "imageId")
  field(:result, 2, type: Modal.Client.GenericResult)
  field(:image_metadata, 3, type: Modal.Client.ImageMetadata, json_name: "imageMetadata")
end

defmodule Modal.Client.SandboxSnapshotGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:snapshot_id, 1, type: :string, json_name: "snapshotId")
end

defmodule Modal.Client.SandboxSnapshotGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:snapshot_id, 1, type: :string, json_name: "snapshotId")
end

defmodule Modal.Client.SandboxSnapshotRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxSnapshotResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:snapshot_id, 1, type: :string, json_name: "snapshotId")
end

defmodule Modal.Client.SandboxSnapshotWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:snapshot_id, 1, type: :string, json_name: "snapshotId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxSnapshotWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxSnapshotWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
end

defmodule Modal.Client.SandboxStdinWriteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxStdinWriteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:input, 2, type: :bytes)
  field(:index, 3, type: :uint32)
  field(:eof, 4, type: :bool)
end

defmodule Modal.Client.SandboxStdinWriteResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxStdinWriteResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.SandboxTag do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTag",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:tag_name, 1, type: :string, json_name: "tagName")
  field(:tag_value, 2, type: :string, json_name: "tagValue")
end

defmodule Modal.Client.SandboxTagsGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTagsGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxTagsGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTagsGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:tags, 1, repeated: true, type: Modal.Client.SandboxTag)
end

defmodule Modal.Client.SandboxTagsSetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTagsSetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:sandbox_id, 2, type: :string, json_name: "sandboxId")
  field(:tags, 3, repeated: true, type: Modal.Client.SandboxTag)
end

defmodule Modal.Client.SandboxTerminateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTerminateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
end

defmodule Modal.Client.SandboxTerminateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxTerminateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:existing_result, 1, type: Modal.Client.GenericResult, json_name: "existingResult")
end

defmodule Modal.Client.SandboxWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 1, type: Modal.Client.GenericResult)
end

defmodule Modal.Client.SandboxWaitUntilReadyRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxWaitUntilReadyRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:sandbox_id, 1, type: :string, json_name: "sandboxId")
  field(:timeout, 2, type: :float)
end

defmodule Modal.Client.SandboxWaitUntilReadyResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SandboxWaitUntilReadyResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:ready_at, 1, type: :double, json_name: "readyAt")
end

defmodule Modal.Client.Schedule.Cron do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Schedule.Cron",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cron_string, 1, type: :string, json_name: "cronString")
  field(:timezone, 2, type: :string)
end

defmodule Modal.Client.Schedule.Period do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Schedule.Period",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:years, 1, type: :int32)
  field(:months, 2, type: :int32)
  field(:weeks, 3, type: :int32)
  field(:days, 4, type: :int32)
  field(:hours, 5, type: :int32)
  field(:minutes, 6, type: :int32)
  field(:seconds, 7, type: :float)
end

defmodule Modal.Client.Schedule do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Schedule",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:schedule_oneof, 0)

  field(:cron, 1, type: Modal.Client.Schedule.Cron, oneof: 0)
  field(:period, 2, type: Modal.Client.Schedule.Period, oneof: 0)
end

defmodule Modal.Client.SchedulerPlacement do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SchedulerPlacement",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:X_zone, 0)

  oneof(:X_lifecycle, 1)

  field(:regions, 4, repeated: true, type: :string)
  field(:_zone, 2, proto3_optional: true, type: :string, json_name: "Zone", deprecated: true)

  field(:_lifecycle, 3,
    proto3_optional: true,
    type: :string,
    json_name: "Lifecycle",
    deprecated: true
  )

  field(:_instance_types, 5,
    repeated: true,
    type: :string,
    json_name: "InstanceTypes",
    deprecated: true
  )

  field(:nonpreemptible, 6, type: :bool)
end

defmodule Modal.Client.SecretCreateRequest.EnvDictEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretCreateRequest.EnvDictEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.SecretCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:env_dict, 1,
    repeated: true,
    type: Modal.Client.SecretCreateRequest.EnvDictEntry,
    json_name: "envDict",
    map: true
  )

  field(:app_id, 2, type: :string, json_name: "appId")
  field(:template_type, 3, type: :string, json_name: "templateType")
  field(:existing_secret_id, 4, type: :string, json_name: "existingSecretId")
end

defmodule Modal.Client.SecretCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:secret_id, 1, type: :string, json_name: "secretId")
end

defmodule Modal.Client.SecretDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:secret_id, 1, type: :string, json_name: "secretId")
end

defmodule Modal.Client.SecretGetOrCreateRequest.EnvDictEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretGetOrCreateRequest.EnvDictEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.SecretGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )

  field(:env_dict, 5,
    repeated: true,
    type: Modal.Client.SecretGetOrCreateRequest.EnvDictEntry,
    json_name: "envDict",
    map: true
  )

  field(:app_id, 6, type: :string, json_name: "appId")
  field(:required_keys, 7, repeated: true, type: :string, json_name: "requiredKeys")
end

defmodule Modal.Client.SecretGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:secret_id, 1, type: :string, json_name: "secretId")
  field(:metadata, 2, type: Modal.Client.SecretMetadata)
end

defmodule Modal.Client.SecretListItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretListItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:label, 1, type: :string)
  field(:created_at, 2, type: :double, json_name: "createdAt")
  field(:last_used_at, 3, type: :double, json_name: "lastUsedAt")
  field(:environment_name, 4, type: :string, json_name: "environmentName")
  field(:secret_id, 5, type: :string, json_name: "secretId")
  field(:metadata, 6, type: Modal.Client.SecretMetadata)
end

defmodule Modal.Client.SecretListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:pagination, 2, type: Modal.Client.ListPagination)
end

defmodule Modal.Client.SecretListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.SecretListItem)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.SecretMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:name, 1, type: :string)
  field(:creation_info, 2, type: Modal.Client.CreationInfo, json_name: "creationInfo")
end

defmodule Modal.Client.SecretUpdateRequest.Update do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretUpdateRequest.Update",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, proto3_optional: true, type: :string)
end

defmodule Modal.Client.SecretUpdateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SecretUpdateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:secret_id, 1, type: :string, json_name: "secretId")
  field(:updates, 2, repeated: true, type: Modal.Client.SecretUpdateRequest.Update)
end

defmodule Modal.Client.ServiceUserIdentity do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.ServiceUserIdentity",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:service_user_id, 1, type: :string, json_name: "serviceUserId")
  field(:service_user_name, 2, type: :string, json_name: "serviceUserName")
  field(:created_by, 3, type: Modal.Client.UserIdentity, json_name: "createdBy")
end

defmodule Modal.Client.SharedVolumeDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
end

defmodule Modal.Client.SharedVolumeGetFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeGetFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
  field(:path, 2, type: :string)
end

defmodule Modal.Client.SharedVolumeGetFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeGetFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:data, 1, type: :bytes, oneof: 0)
  field(:data_blob_id, 2, type: :string, json_name: "dataBlobId", oneof: 0)
end

defmodule Modal.Client.SharedVolumeGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )

  field(:app_id, 5, type: :string, json_name: "appId")
end

defmodule Modal.Client.SharedVolumeGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
end

defmodule Modal.Client.SharedVolumeHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
end

defmodule Modal.Client.SharedVolumeListFilesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeListFilesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
  field(:path, 2, type: :string)
end

defmodule Modal.Client.SharedVolumeListFilesResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeListFilesResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:entries, 1, repeated: true, type: Modal.Client.FileEntry)
end

defmodule Modal.Client.SharedVolumeListItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeListItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:label, 1, type: :string)
  field(:shared_volume_id, 2, type: :string, json_name: "sharedVolumeId")
  field(:created_at, 3, type: :double, json_name: "createdAt")

  field(:cloud_provider, 4,
    type: Modal.Client.CloudProvider,
    json_name: "cloudProvider",
    enum: true
  )
end

defmodule Modal.Client.SharedVolumeListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.SharedVolumeListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.SharedVolumeListItem)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.SharedVolumeMount do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeMount",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:mount_path, 1, type: :string, json_name: "mountPath")
  field(:shared_volume_id, 2, type: :string, json_name: "sharedVolumeId")

  field(:cloud_provider, 3,
    type: Modal.Client.CloudProvider,
    json_name: "cloudProvider",
    enum: true
  )
end

defmodule Modal.Client.SharedVolumePutFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumePutFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
  field(:path, 2, type: :string)
  field(:sha256_hex, 3, type: :string, json_name: "sha256Hex")
  field(:data, 4, type: :bytes, oneof: 0)
  field(:data_blob_id, 5, type: :string, json_name: "dataBlobId", oneof: 0)
  field(:resumable, 6, type: :bool)
end

defmodule Modal.Client.SharedVolumePutFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumePutFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exists, 1, type: :bool)
end

defmodule Modal.Client.SharedVolumeRemoveFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SharedVolumeRemoveFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:shared_volume_id, 1, type: :string, json_name: "sharedVolumeId")
  field(:path, 2, type: :string)
  field(:recursive, 3, type: :bool)
end

defmodule Modal.Client.SystemErrorMessage do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.SystemErrorMessage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:error_code, 1, type: Modal.Client.SystemErrorCode, json_name: "errorCode", enum: true)
  field(:error_message, 2, type: :string, json_name: "errorMessage")
end

defmodule Modal.Client.TaskClusterHelloRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskClusterHelloRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:container_ip, 2, type: :string, json_name: "containerIp")
end

defmodule Modal.Client.TaskClusterHelloResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskClusterHelloResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:cluster_id, 1, type: :string, json_name: "clusterId")
  field(:cluster_rank, 2, type: :uint32, json_name: "clusterRank")
  field(:container_ips, 3, repeated: true, type: :string, json_name: "containerIps")
  field(:container_ipv4_ips, 4, repeated: true, type: :string, json_name: "containerIpv4Ips")
end

defmodule Modal.Client.TaskCurrentInputsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskCurrentInputsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:input_ids, 1, repeated: true, type: :string, json_name: "inputIds")
end

defmodule Modal.Client.TaskGetCommandRouterAccessRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskGetCommandRouterAccessRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
end

defmodule Modal.Client.TaskGetCommandRouterAccessResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskGetCommandRouterAccessResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:jwt, 1, type: :string)
  field(:url, 2, type: :string)
end

defmodule Modal.Client.TaskGetInfoRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskGetInfoRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
end

defmodule Modal.Client.TaskGetInfoResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskGetInfoResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:app_id, 1, type: :string, json_name: "appId")
  field(:info, 2, type: Modal.Client.TaskInfo)
end

defmodule Modal.Client.TaskInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:id, 1, type: :string)
  field(:started_at, 2, type: :double, json_name: "startedAt")
  field(:finished_at, 3, type: :double, json_name: "finishedAt")
  field(:result, 4, type: Modal.Client.GenericResult)
  field(:enqueued_at, 5, type: :double, json_name: "enqueuedAt")
  field(:gpu_type, 6, type: :string, json_name: "gpuType")
  field(:sandbox_id, 7, type: :string, json_name: "sandboxId")

  field(:snapshot_behavior, 8,
    type: Modal.Client.TaskSnapshotBehavior,
    json_name: "snapshotBehavior",
    enum: true
  )

  field(:gpu_config, 9, type: Modal.Client.GPUConfig, json_name: "gpuConfig")
end

defmodule Modal.Client.TaskListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:app_id, 2, type: :string, json_name: "appId")
end

defmodule Modal.Client.TaskListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:tasks, 1, repeated: true, type: Modal.Client.TaskStats)
end

defmodule Modal.Client.TaskLogs do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskLogs",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:data, 1, type: :string)
  field(:task_state, 6, type: Modal.Client.TaskState, json_name: "taskState", enum: true)
  field(:timestamp, 7, type: :double)

  field(:file_descriptor, 8,
    type: Modal.Client.FileDescriptor,
    json_name: "fileDescriptor",
    enum: true
  )

  field(:task_progress, 9, type: Modal.Client.TaskProgress, json_name: "taskProgress")
  field(:function_call_id, 10, type: :string, json_name: "functionCallId")
  field(:input_id, 11, type: :string, json_name: "inputId")
  field(:timestamp_ns, 12, type: :uint64, json_name: "timestampNs")
  field(:container_id, 13, type: :string, json_name: "containerId")
  field(:container_name, 14, type: :string, json_name: "containerName")
end

defmodule Modal.Client.TaskLogsBatch do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskLogsBatch",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:items, 2, repeated: true, type: Modal.Client.TaskLogs)
  field(:entry_id, 5, type: :string, json_name: "entryId")
  field(:app_done, 10, type: :bool, json_name: "appDone")
  field(:function_id, 11, type: :string, json_name: "functionId")
  field(:input_id, 12, type: :string, json_name: "inputId")
  field(:image_id, 13, type: :string, json_name: "imageId")
  field(:eof, 14, type: :bool)
  field(:pty_exec_id, 15, type: :string, json_name: "ptyExecId")
  field(:root_function_id, 16, type: :string, json_name: "rootFunctionId")
  field(:ttl_days, 17, type: :uint32, json_name: "ttlDays")
end

defmodule Modal.Client.TaskProgress do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskProgress",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:len, 1, type: :uint64)
  field(:pos, 2, type: :uint64)
  field(:progress_type, 3, type: Modal.Client.ProgressType, json_name: "progressType", enum: true)
  field(:description, 4, type: :string)
end

defmodule Modal.Client.TaskResultRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskResultRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:result, 2, type: Modal.Client.GenericResult)
end

defmodule Modal.Client.TaskStats do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskStats",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:task_id, 1, type: :string, json_name: "taskId")
  field(:app_id, 2, type: :string, json_name: "appId")
  field(:app_description, 3, type: :string, json_name: "appDescription")
  field(:started_at, 4, type: :double, json_name: "startedAt")
  field(:enqueued_at, 5, type: :double, json_name: "enqueuedAt")
end

defmodule Modal.Client.TaskTemplate do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TaskTemplate",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:rank, 1, type: :uint32)
  field(:resources, 2, type: Modal.Client.Resources)
  field(:target_concurrent_inputs, 3, type: :uint32, json_name: "targetConcurrentInputs")
  field(:max_concurrent_inputs, 4, type: :uint32, json_name: "maxConcurrentInputs")
  field(:index, 5, type: :uint32)
end

defmodule Modal.Client.TokenFlowCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenFlowCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:utm_source, 3, type: :string, json_name: "utmSource")
  field(:localhost_port, 4, type: :int32, json_name: "localhostPort")
  field(:next_url, 5, type: :string, json_name: "nextUrl")
end

defmodule Modal.Client.TokenFlowCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenFlowCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:token_flow_id, 1, type: :string, json_name: "tokenFlowId")
  field(:web_url, 2, type: :string, json_name: "webUrl")
  field(:code, 3, type: :string)
  field(:wait_secret, 4, type: :string, json_name: "waitSecret")
end

defmodule Modal.Client.TokenFlowWaitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenFlowWaitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:timeout, 1, type: :float)
  field(:token_flow_id, 2, type: :string, json_name: "tokenFlowId")
  field(:wait_secret, 3, type: :string, json_name: "waitSecret")
end

defmodule Modal.Client.TokenFlowWaitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenFlowWaitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:token_id, 1, type: :string, json_name: "tokenId")
  field(:token_secret, 2, type: :string, json_name: "tokenSecret")
  field(:timeout, 3, type: :bool)
  field(:workspace_username, 4, type: :string, json_name: "workspaceUsername")
end

defmodule Modal.Client.TokenInfoGetRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenInfoGetRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Modal.Client.TokenInfoGetResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TokenInfoGetResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:identity, 0)

  field(:token_id, 1, type: :string, json_name: "tokenId")
  field(:workspace_id, 2, type: :string, json_name: "workspaceId")
  field(:workspace_name, 3, type: :string, json_name: "workspaceName")
  field(:user_identity, 4, type: Modal.Client.UserIdentity, json_name: "userIdentity", oneof: 0)

  field(:service_user_identity, 5,
    type: Modal.Client.ServiceUserIdentity,
    json_name: "serviceUserIdentity",
    oneof: 0
  )

  field(:created_at, 6, type: Google.Protobuf.Timestamp, json_name: "createdAt")
  field(:expires_at, 7, type: Google.Protobuf.Timestamp, json_name: "expiresAt")
  field(:token_name, 8, type: :string, json_name: "tokenName")
end

defmodule Modal.Client.TunnelData do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TunnelData",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:host, 1, type: :string)
  field(:port, 2, type: :uint32)
  field(:unencrypted_host, 3, proto3_optional: true, type: :string, json_name: "unencryptedHost")
  field(:unencrypted_port, 4, proto3_optional: true, type: :uint32, json_name: "unencryptedPort")
  field(:container_port, 5, type: :uint32, json_name: "containerPort")
end

defmodule Modal.Client.TunnelStartRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TunnelStartRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:port, 1, type: :uint32)
  field(:unencrypted, 2, type: :bool)

  field(:tunnel_type, 3,
    proto3_optional: true,
    type: Modal.Client.TunnelType,
    json_name: "tunnelType",
    enum: true
  )
end

defmodule Modal.Client.TunnelStartResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TunnelStartResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:host, 1, type: :string)
  field(:port, 2, type: :uint32)
  field(:unencrypted_host, 3, proto3_optional: true, type: :string, json_name: "unencryptedHost")
  field(:unencrypted_port, 4, proto3_optional: true, type: :uint32, json_name: "unencryptedPort")
end

defmodule Modal.Client.TunnelStopRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TunnelStopRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:port, 1, type: :uint32)
end

defmodule Modal.Client.TunnelStopResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.TunnelStopResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:exists, 1, type: :bool)
end

defmodule Modal.Client.UploadUrlList do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.UploadUrlList",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: :string)
end

defmodule Modal.Client.UserActionInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.UserActionInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:timestamp, 2, type: :double)
end

defmodule Modal.Client.UserIdentity do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.UserIdentity",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:username, 2, type: :string)
end

defmodule Modal.Client.VolumeCommitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeCommitRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
end

defmodule Modal.Client.VolumeCommitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeCommitResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:skip_reload, 1, type: :bool, json_name: "skipReload")
end

defmodule Modal.Client.VolumeCopyFiles2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeCopyFiles2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:src_paths, 2, repeated: true, type: :string, json_name: "srcPaths")
  field(:dst_path, 3, type: :string, json_name: "dstPath")
  field(:recursive, 4, type: :bool)
end

defmodule Modal.Client.VolumeCopyFilesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeCopyFilesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:src_paths, 2, repeated: true, type: :string, json_name: "srcPaths")
  field(:dst_path, 3, type: :string, json_name: "dstPath")
  field(:recursive, 4, type: :bool)
end

defmodule Modal.Client.VolumeDeleteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeDeleteRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:environment_name, 2, type: :string, json_name: "environmentName", deprecated: true)
end

defmodule Modal.Client.VolumeGetByIdRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetByIdRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
end

defmodule Modal.Client.VolumeGetByIdResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetByIdResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:metadata, 2, type: Modal.Client.VolumeMetadata)
end

defmodule Modal.Client.VolumeGetFile2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetFile2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:start, 3, type: :uint64)
  field(:len, 4, type: :uint64)
end

defmodule Modal.Client.VolumeGetFile2Response do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetFile2Response",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:get_urls, 1, repeated: true, type: :string, json_name: "getUrls")
  field(:size, 2, type: :uint64)
  field(:start, 3, type: :uint64)
  field(:len, 4, type: :uint64)
end

defmodule Modal.Client.VolumeGetFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:start, 3, type: :uint64)
  field(:len, 4, type: :uint64)
end

defmodule Modal.Client.VolumeGetFileResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetFileResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:data_oneof, 0)

  field(:data, 1, type: :bytes, oneof: 0)
  field(:data_blob_id, 2, type: :string, json_name: "dataBlobId", oneof: 0)
  field(:size, 3, type: :uint64)
  field(:start, 4, type: :uint64)
  field(:len, 5, type: :uint64)
end

defmodule Modal.Client.VolumeGetOrCreateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetOrCreateRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:deployment_name, 1, type: :string, json_name: "deploymentName")
  field(:environment_name, 3, type: :string, json_name: "environmentName")

  field(:object_creation_type, 4,
    type: Modal.Client.ObjectCreationType,
    json_name: "objectCreationType",
    enum: true
  )

  field(:app_id, 5, type: :string, json_name: "appId")
  field(:version, 6, type: Modal.Client.VolumeFsVersion, enum: true)
end

defmodule Modal.Client.VolumeGetOrCreateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeGetOrCreateResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:version, 2, type: Modal.Client.VolumeFsVersion, enum: true)
  field(:metadata, 3, type: Modal.Client.VolumeMetadata)
end

defmodule Modal.Client.VolumeHeartbeatRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeHeartbeatRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
end

defmodule Modal.Client.VolumeListFiles2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListFiles2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:recursive, 4, type: :bool)
  field(:max_entries, 3, proto3_optional: true, type: :uint32, json_name: "maxEntries")
end

defmodule Modal.Client.VolumeListFiles2Response do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListFiles2Response",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:entries, 1, repeated: true, type: Modal.Client.FileEntry)
end

defmodule Modal.Client.VolumeListFilesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListFilesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:recursive, 4, type: :bool)
  field(:max_entries, 3, proto3_optional: true, type: :uint32, json_name: "maxEntries")
end

defmodule Modal.Client.VolumeListFilesResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListFilesResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:entries, 1, repeated: true, type: Modal.Client.FileEntry)
end

defmodule Modal.Client.VolumeListItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:label, 1, type: :string)
  field(:volume_id, 2, type: :string, json_name: "volumeId")
  field(:created_at, 3, type: :double, json_name: "createdAt")
  field(:metadata, 4, type: Modal.Client.VolumeMetadata)
end

defmodule Modal.Client.VolumeListRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
  field(:pagination, 2, type: Modal.Client.ListPagination)
end

defmodule Modal.Client.VolumeListResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeListResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:items, 1, repeated: true, type: Modal.Client.VolumeListItem)
  field(:environment_name, 2, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.VolumeMetadata do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeMetadata",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:version, 1, type: Modal.Client.VolumeFsVersion, enum: true)
  field(:name, 2, type: :string)
  field(:creation_info, 3, type: Modal.Client.CreationInfo, json_name: "creationInfo")
end

defmodule Modal.Client.VolumeMount do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeMount",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:mount_path, 2, type: :string, json_name: "mountPath")
  field(:allow_background_commits, 3, type: :bool, json_name: "allowBackgroundCommits")
  field(:read_only, 4, type: :bool, json_name: "readOnly")
end

defmodule Modal.Client.VolumePutFiles2Request.File do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFiles2Request.File",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:path, 1, type: :string)
  field(:size, 2, type: :uint64)
  field(:blocks, 3, repeated: true, type: Modal.Client.VolumePutFiles2Request.Block)
  field(:mode, 4, proto3_optional: true, type: :uint32)
end

defmodule Modal.Client.VolumePutFiles2Request.Block do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFiles2Request.Block",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:contents_sha256, 1, type: :bytes, json_name: "contentsSha256")
  field(:put_response, 2, proto3_optional: true, type: :bytes, json_name: "putResponse")
end

defmodule Modal.Client.VolumePutFiles2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFiles2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:files, 2, repeated: true, type: Modal.Client.VolumePutFiles2Request.File)

  field(:disallow_overwrite_existing_files, 3,
    type: :bool,
    json_name: "disallowOverwriteExistingFiles"
  )
end

defmodule Modal.Client.VolumePutFiles2Response.MissingBlock do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFiles2Response.MissingBlock",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:file_index, 1, type: :uint64, json_name: "fileIndex")
  field(:block_index, 2, type: :uint64, json_name: "blockIndex")
  field(:put_url, 3, type: :string, json_name: "putUrl")
end

defmodule Modal.Client.VolumePutFiles2Response do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFiles2Response",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:missing_blocks, 1,
    repeated: true,
    type: Modal.Client.VolumePutFiles2Response.MissingBlock,
    json_name: "missingBlocks"
  )
end

defmodule Modal.Client.VolumePutFilesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumePutFilesRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:files, 2, repeated: true, type: Modal.Client.MountFile)

  field(:disallow_overwrite_existing_files, 3,
    type: :bool,
    json_name: "disallowOverwriteExistingFiles"
  )
end

defmodule Modal.Client.VolumeReloadRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeReloadRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
end

defmodule Modal.Client.VolumeRemoveFile2Request do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeRemoveFile2Request",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:recursive, 3, type: :bool)
end

defmodule Modal.Client.VolumeRemoveFileRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeRemoveFileRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:path, 2, type: :string)
  field(:recursive, 3, type: :bool)
end

defmodule Modal.Client.VolumeRenameRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.VolumeRenameRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:volume_id, 1, type: :string, json_name: "volumeId")
  field(:name, 2, type: :string)
end

defmodule Modal.Client.Warning do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.Warning",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:type, 1, type: Modal.Client.Warning.WarningType, enum: true)
  field(:message, 2, type: :string)
end

defmodule Modal.Client.WebUrlInfo do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WebUrlInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:truncated, 1, type: :bool)
  field(:has_unique_hash, 2, type: :bool, json_name: "hasUniqueHash", deprecated: true)
  field(:label_stolen, 3, type: :bool, json_name: "labelStolen")
end

defmodule Modal.Client.WebhookConfig do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WebhookConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:type, 1, type: Modal.Client.WebhookType, enum: true)
  field(:method, 2, type: :string)
  field(:requested_suffix, 4, type: :string, json_name: "requestedSuffix")
  field(:async_mode, 5, type: Modal.Client.WebhookAsyncMode, json_name: "asyncMode", enum: true)

  field(:custom_domains, 6,
    repeated: true,
    type: Modal.Client.CustomDomainConfig,
    json_name: "customDomains"
  )

  field(:web_server_port, 7, type: :uint32, json_name: "webServerPort")
  field(:web_server_startup_timeout, 8, type: :float, json_name: "webServerStartupTimeout")
  field(:web_endpoint_docs, 9, type: :bool, json_name: "webEndpointDocs")
  field(:requires_proxy_auth, 10, type: :bool, json_name: "requiresProxyAuth")
  field(:ephemeral_suffix, 11, type: :string, json_name: "ephemeralSuffix")
end

defmodule Modal.Client.WorkspaceBillingReportItem.TagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceBillingReportItem.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Modal.Client.WorkspaceBillingReportItem do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceBillingReportItem",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:object_id, 1, type: :string, json_name: "objectId")
  field(:description, 2, type: :string)
  field(:environment_name, 3, type: :string, json_name: "environmentName")
  field(:interval, 4, type: Google.Protobuf.Timestamp)
  field(:cost, 5, type: :string)

  field(:tags, 6,
    repeated: true,
    type: Modal.Client.WorkspaceBillingReportItem.TagsEntry,
    map: true
  )
end

defmodule Modal.Client.WorkspaceBillingReportRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceBillingReportRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:start_timestamp, 1, type: Google.Protobuf.Timestamp, json_name: "startTimestamp")
  field(:end_timestamp, 2, type: Google.Protobuf.Timestamp, json_name: "endTimestamp")
  field(:resolution, 3, type: :string)
  field(:tag_names, 4, repeated: true, type: :string, json_name: "tagNames")
end

defmodule Modal.Client.WorkspaceDashboardUrlRequest do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceDashboardUrlRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:environment_name, 1, type: :string, json_name: "environmentName")
end

defmodule Modal.Client.WorkspaceDashboardUrlResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceDashboardUrlResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:url, 1, type: :string)
end

defmodule Modal.Client.WorkspaceNameLookupResponse do
  @moduledoc false

  use Protobuf,
    full_name: "modal.client.WorkspaceNameLookupResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:workspace_name, 1, type: :string, json_name: "workspaceName", deprecated: true)
  field(:username, 2, type: :string)
end

defmodule Modal.Client.ModalClient.Service do
  @moduledoc false

  use GRPC.Service, name: "modal.client.ModalClient", protoc_gen_elixir_version: "0.16.0"

  rpc(:AppClientDisconnect, Modal.Client.AppClientDisconnectRequest, Google.Protobuf.Empty)

  rpc(:AppCountLogs, Modal.Client.AppCountLogsRequest, Modal.Client.AppCountLogsResponse)

  rpc(:AppCreate, Modal.Client.AppCreateRequest, Modal.Client.AppCreateResponse)

  rpc(:AppDeploy, Modal.Client.AppDeployRequest, Modal.Client.AppDeployResponse)

  rpc(
    :AppDeploymentHistory,
    Modal.Client.AppDeploymentHistoryRequest,
    Modal.Client.AppDeploymentHistoryResponse
  )

  rpc(:AppFetchLogs, Modal.Client.AppFetchLogsRequest, Modal.Client.AppFetchLogsResponse)

  rpc(
    :AppGetByDeploymentName,
    Modal.Client.AppGetByDeploymentNameRequest,
    Modal.Client.AppGetByDeploymentNameResponse
  )

  rpc(:AppGetLayout, Modal.Client.AppGetLayoutRequest, Modal.Client.AppGetLayoutResponse)

  rpc(:AppGetLogs, Modal.Client.AppGetLogsRequest, stream(Modal.Client.TaskLogsBatch))

  rpc(:AppGetObjects, Modal.Client.AppGetObjectsRequest, Modal.Client.AppGetObjectsResponse)

  rpc(:AppGetOrCreate, Modal.Client.AppGetOrCreateRequest, Modal.Client.AppGetOrCreateResponse)

  rpc(:AppGetTags, Modal.Client.AppGetTagsRequest, Modal.Client.AppGetTagsResponse)

  rpc(:AppHeartbeat, Modal.Client.AppHeartbeatRequest, Google.Protobuf.Empty)

  rpc(:AppList, Modal.Client.AppListRequest, Modal.Client.AppListResponse)

  rpc(:AppLookup, Modal.Client.AppLookupRequest, Modal.Client.AppLookupResponse)

  rpc(:AppPublish, Modal.Client.AppPublishRequest, Modal.Client.AppPublishResponse)

  rpc(:AppRollback, Modal.Client.AppRollbackRequest, Google.Protobuf.Empty)

  rpc(:AppSetObjects, Modal.Client.AppSetObjectsRequest, Google.Protobuf.Empty)

  rpc(:AppSetTags, Modal.Client.AppSetTagsRequest, Google.Protobuf.Empty)

  rpc(:AppStop, Modal.Client.AppStopRequest, Google.Protobuf.Empty)

  rpc(:AttemptAwait, Modal.Client.AttemptAwaitRequest, Modal.Client.AttemptAwaitResponse)

  rpc(:AttemptRetry, Modal.Client.AttemptRetryRequest, Modal.Client.AttemptRetryResponse)

  rpc(:AttemptStart, Modal.Client.AttemptStartRequest, Modal.Client.AttemptStartResponse)

  rpc(:AuthTokenGet, Modal.Client.AuthTokenGetRequest, Modal.Client.AuthTokenGetResponse)

  rpc(:BlobCreate, Modal.Client.BlobCreateRequest, Modal.Client.BlobCreateResponse)

  rpc(:BlobGet, Modal.Client.BlobGetRequest, Modal.Client.BlobGetResponse)

  rpc(:ClassCreate, Modal.Client.ClassCreateRequest, Modal.Client.ClassCreateResponse)

  rpc(:ClassGet, Modal.Client.ClassGetRequest, Modal.Client.ClassGetResponse)

  rpc(:ClientHello, Google.Protobuf.Empty, Modal.Client.ClientHelloResponse)

  rpc(:ClusterGet, Modal.Client.ClusterGetRequest, Modal.Client.ClusterGetResponse)

  rpc(:ClusterList, Modal.Client.ClusterListRequest, Modal.Client.ClusterListResponse)

  rpc(:ContainerCheckpoint, Modal.Client.ContainerCheckpointRequest, Google.Protobuf.Empty)

  rpc(:ContainerExec, Modal.Client.ContainerExecRequest, Modal.Client.ContainerExecResponse)

  rpc(
    :ContainerExecGetOutput,
    Modal.Client.ContainerExecGetOutputRequest,
    stream(Modal.Client.RuntimeOutputBatch)
  )

  rpc(:ContainerExecPutInput, Modal.Client.ContainerExecPutInputRequest, Google.Protobuf.Empty)

  rpc(
    :ContainerExecWait,
    Modal.Client.ContainerExecWaitRequest,
    Modal.Client.ContainerExecWaitResponse
  )

  rpc(
    :ContainerFilesystemExec,
    Modal.Client.ContainerFilesystemExecRequest,
    Modal.Client.ContainerFilesystemExecResponse
  )

  rpc(
    :ContainerFilesystemExecGetOutput,
    Modal.Client.ContainerFilesystemExecGetOutputRequest,
    stream(Modal.Client.FilesystemRuntimeOutputBatch)
  )

  rpc(
    :ContainerHeartbeat,
    Modal.Client.ContainerHeartbeatRequest,
    Modal.Client.ContainerHeartbeatResponse
  )

  rpc(:ContainerHello, Google.Protobuf.Empty, Google.Protobuf.Empty)

  rpc(:ContainerLog, Modal.Client.ContainerLogRequest, Google.Protobuf.Empty)

  rpc(
    :ContainerReloadVolumes,
    Modal.Client.ContainerReloadVolumesRequest,
    Modal.Client.ContainerReloadVolumesResponse
  )

  rpc(:ContainerStop, Modal.Client.ContainerStopRequest, Modal.Client.ContainerStopResponse)

  rpc(:DictClear, Modal.Client.DictClearRequest, Google.Protobuf.Empty)

  rpc(:DictContains, Modal.Client.DictContainsRequest, Modal.Client.DictContainsResponse)

  rpc(:DictContents, Modal.Client.DictContentsRequest, stream(Modal.Client.DictEntry))

  rpc(:DictDelete, Modal.Client.DictDeleteRequest, Google.Protobuf.Empty)

  rpc(:DictGet, Modal.Client.DictGetRequest, Modal.Client.DictGetResponse)

  rpc(:DictGetById, Modal.Client.DictGetByIdRequest, Modal.Client.DictGetByIdResponse)

  rpc(:DictGetOrCreate, Modal.Client.DictGetOrCreateRequest, Modal.Client.DictGetOrCreateResponse)

  rpc(:DictHeartbeat, Modal.Client.DictHeartbeatRequest, Google.Protobuf.Empty)

  rpc(:DictLen, Modal.Client.DictLenRequest, Modal.Client.DictLenResponse)

  rpc(:DictList, Modal.Client.DictListRequest, Modal.Client.DictListResponse)

  rpc(:DictPop, Modal.Client.DictPopRequest, Modal.Client.DictPopResponse)

  rpc(:DictUpdate, Modal.Client.DictUpdateRequest, Modal.Client.DictUpdateResponse)

  rpc(
    :DomainCertificateVerify,
    Modal.Client.DomainCertificateVerifyRequest,
    Modal.Client.DomainCertificateVerifyResponse
  )

  rpc(:DomainCreate, Modal.Client.DomainCreateRequest, Modal.Client.DomainCreateResponse)

  rpc(:DomainList, Modal.Client.DomainListRequest, Modal.Client.DomainListResponse)

  rpc(:EnvironmentCreate, Modal.Client.EnvironmentCreateRequest, Google.Protobuf.Empty)

  rpc(:EnvironmentDelete, Modal.Client.EnvironmentDeleteRequest, Google.Protobuf.Empty)

  rpc(
    :EnvironmentGetOrCreate,
    Modal.Client.EnvironmentGetOrCreateRequest,
    Modal.Client.EnvironmentGetOrCreateResponse
  )

  rpc(:EnvironmentList, Google.Protobuf.Empty, Modal.Client.EnvironmentListResponse)

  rpc(:EnvironmentUpdate, Modal.Client.EnvironmentUpdateRequest, Modal.Client.EnvironmentListItem)

  rpc(
    :FlashContainerDeregister,
    Modal.Client.FlashContainerDeregisterRequest,
    Google.Protobuf.Empty
  )

  rpc(
    :FlashContainerList,
    Modal.Client.FlashContainerListRequest,
    Modal.Client.FlashContainerListResponse
  )

  rpc(
    :FlashContainerRegister,
    Modal.Client.FlashContainerRegisterRequest,
    Modal.Client.FlashContainerRegisterResponse
  )

  rpc(
    :FlashSetTargetSlotsMetrics,
    Modal.Client.FlashSetTargetSlotsMetricsRequest,
    Modal.Client.FlashSetTargetSlotsMetricsResponse
  )

  rpc(
    :FunctionAsyncInvoke,
    Modal.Client.FunctionAsyncInvokeRequest,
    Modal.Client.FunctionAsyncInvokeResponse
  )

  rpc(
    :FunctionBindParams,
    Modal.Client.FunctionBindParamsRequest,
    Modal.Client.FunctionBindParamsResponse
  )

  rpc(:FunctionCallCancel, Modal.Client.FunctionCallCancelRequest, Google.Protobuf.Empty)

  rpc(
    :FunctionCallFromId,
    Modal.Client.FunctionCallFromIdRequest,
    Modal.Client.FunctionCallFromIdResponse
  )

  rpc(
    :FunctionCallGetDataIn,
    Modal.Client.FunctionCallGetDataRequest,
    stream(Modal.Client.DataChunk)
  )

  rpc(
    :FunctionCallGetDataOut,
    Modal.Client.FunctionCallGetDataRequest,
    stream(Modal.Client.DataChunk)
  )

  rpc(
    :FunctionCallList,
    Modal.Client.FunctionCallListRequest,
    Modal.Client.FunctionCallListResponse
  )

  rpc(:FunctionCallPutDataOut, Modal.Client.FunctionCallPutDataRequest, Google.Protobuf.Empty)

  rpc(:FunctionCreate, Modal.Client.FunctionCreateRequest, Modal.Client.FunctionCreateResponse)

  rpc(:FunctionFinishInputs, Modal.Client.FunctionFinishInputsRequest, Google.Protobuf.Empty)

  rpc(:FunctionGet, Modal.Client.FunctionGetRequest, Modal.Client.FunctionGetResponse)

  rpc(
    :FunctionGetCallGraph,
    Modal.Client.FunctionGetCallGraphRequest,
    Modal.Client.FunctionGetCallGraphResponse
  )

  rpc(
    :FunctionGetCurrentStats,
    Modal.Client.FunctionGetCurrentStatsRequest,
    Modal.Client.FunctionStats
  )

  rpc(
    :FunctionGetDynamicConcurrency,
    Modal.Client.FunctionGetDynamicConcurrencyRequest,
    Modal.Client.FunctionGetDynamicConcurrencyResponse
  )

  rpc(
    :FunctionGetInputs,
    Modal.Client.FunctionGetInputsRequest,
    Modal.Client.FunctionGetInputsResponse
  )

  rpc(
    :FunctionGetOutputs,
    Modal.Client.FunctionGetOutputsRequest,
    Modal.Client.FunctionGetOutputsResponse
  )

  rpc(
    :FunctionGetSerialized,
    Modal.Client.FunctionGetSerializedRequest,
    Modal.Client.FunctionGetSerializedResponse
  )

  rpc(:FunctionMap, Modal.Client.FunctionMapRequest, Modal.Client.FunctionMapResponse)

  rpc(
    :FunctionPrecreate,
    Modal.Client.FunctionPrecreateRequest,
    Modal.Client.FunctionPrecreateResponse
  )

  rpc(
    :FunctionPutInputs,
    Modal.Client.FunctionPutInputsRequest,
    Modal.Client.FunctionPutInputsResponse
  )

  rpc(:FunctionPutOutputs, Modal.Client.FunctionPutOutputsRequest, Google.Protobuf.Empty)

  rpc(
    :FunctionRetryInputs,
    Modal.Client.FunctionRetryInputsRequest,
    Modal.Client.FunctionRetryInputsResponse
  )

  rpc(:FunctionStartPtyShell, Google.Protobuf.Empty, Google.Protobuf.Empty)

  rpc(
    :FunctionUpdateSchedulingParams,
    Modal.Client.FunctionUpdateSchedulingParamsRequest,
    Modal.Client.FunctionUpdateSchedulingParamsResponse
  )

  rpc(:ImageDelete, Modal.Client.ImageDeleteRequest, Google.Protobuf.Empty)

  rpc(:ImageFromId, Modal.Client.ImageFromIdRequest, Modal.Client.ImageFromIdResponse)

  rpc(
    :ImageGetOrCreate,
    Modal.Client.ImageGetOrCreateRequest,
    Modal.Client.ImageGetOrCreateResponse
  )

  rpc(
    :ImageJoinStreaming,
    Modal.Client.ImageJoinStreamingRequest,
    stream(Modal.Client.ImageJoinStreamingResponse)
  )

  rpc(:MapAwait, Modal.Client.MapAwaitRequest, Modal.Client.MapAwaitResponse)

  rpc(:MapCheckInputs, Modal.Client.MapCheckInputsRequest, Modal.Client.MapCheckInputsResponse)

  rpc(
    :MapStartOrContinue,
    Modal.Client.MapStartOrContinueRequest,
    Modal.Client.MapStartOrContinueResponse
  )

  rpc(
    :MountGetOrCreate,
    Modal.Client.MountGetOrCreateRequest,
    Modal.Client.MountGetOrCreateResponse
  )

  rpc(:MountPutFile, Modal.Client.MountPutFileRequest, Modal.Client.MountPutFileResponse)

  rpc(
    :NotebookKernelPublishResults,
    Modal.Client.NotebookKernelPublishResultsRequest,
    Google.Protobuf.Empty
  )

  rpc(:ProxyAddIp, Modal.Client.ProxyAddIpRequest, Modal.Client.ProxyAddIpResponse)

  rpc(:ProxyCreate, Modal.Client.ProxyCreateRequest, Modal.Client.ProxyCreateResponse)

  rpc(:ProxyDelete, Modal.Client.ProxyDeleteRequest, Google.Protobuf.Empty)

  rpc(:ProxyGet, Modal.Client.ProxyGetRequest, Modal.Client.ProxyGetResponse)

  rpc(
    :ProxyGetOrCreate,
    Modal.Client.ProxyGetOrCreateRequest,
    Modal.Client.ProxyGetOrCreateResponse
  )

  rpc(:ProxyList, Google.Protobuf.Empty, Modal.Client.ProxyListResponse)

  rpc(:ProxyRemoveIp, Modal.Client.ProxyRemoveIpRequest, Google.Protobuf.Empty)

  rpc(:QueueClear, Modal.Client.QueueClearRequest, Google.Protobuf.Empty)

  rpc(:QueueDelete, Modal.Client.QueueDeleteRequest, Google.Protobuf.Empty)

  rpc(:QueueGet, Modal.Client.QueueGetRequest, Modal.Client.QueueGetResponse)

  rpc(:QueueGetById, Modal.Client.QueueGetByIdRequest, Modal.Client.QueueGetByIdResponse)

  rpc(
    :QueueGetOrCreate,
    Modal.Client.QueueGetOrCreateRequest,
    Modal.Client.QueueGetOrCreateResponse
  )

  rpc(:QueueHeartbeat, Modal.Client.QueueHeartbeatRequest, Google.Protobuf.Empty)

  rpc(:QueueLen, Modal.Client.QueueLenRequest, Modal.Client.QueueLenResponse)

  rpc(:QueueList, Modal.Client.QueueListRequest, Modal.Client.QueueListResponse)

  rpc(:QueueNextItems, Modal.Client.QueueNextItemsRequest, Modal.Client.QueueNextItemsResponse)

  rpc(:QueuePut, Modal.Client.QueuePutRequest, Google.Protobuf.Empty)

  rpc(:SandboxCreate, Modal.Client.SandboxCreateRequest, Modal.Client.SandboxCreateResponse)

  rpc(
    :SandboxCreateConnectToken,
    Modal.Client.SandboxCreateConnectTokenRequest,
    Modal.Client.SandboxCreateConnectTokenResponse
  )

  rpc(:SandboxCreateV2, Modal.Client.SandboxCreateV2Request, Modal.Client.SandboxCreateV2Response)

  rpc(
    :SandboxGetFromName,
    Modal.Client.SandboxGetFromNameRequest,
    Modal.Client.SandboxGetFromNameResponse
  )

  rpc(:SandboxGetLogs, Modal.Client.SandboxGetLogsRequest, stream(Modal.Client.TaskLogsBatch))

  rpc(
    :SandboxGetResourceUsage,
    Modal.Client.SandboxGetResourceUsageRequest,
    Modal.Client.SandboxGetResourceUsageResponse
  )

  rpc(
    :SandboxGetTaskId,
    Modal.Client.SandboxGetTaskIdRequest,
    Modal.Client.SandboxGetTaskIdResponse
  )

  rpc(
    :SandboxGetTaskIdV2,
    Modal.Client.SandboxGetTaskIdRequest,
    Modal.Client.SandboxGetTaskIdResponse
  )

  rpc(
    :SandboxGetTunnels,
    Modal.Client.SandboxGetTunnelsRequest,
    Modal.Client.SandboxGetTunnelsResponse
  )

  rpc(
    :SandboxGetTunnelsV2,
    Modal.Client.SandboxGetTunnelsRequest,
    Modal.Client.SandboxGetTunnelsResponse
  )

  rpc(:SandboxList, Modal.Client.SandboxListRequest, Modal.Client.SandboxListResponse)

  rpc(:SandboxRestore, Modal.Client.SandboxRestoreRequest, Modal.Client.SandboxRestoreResponse)

  rpc(:SandboxSnapshot, Modal.Client.SandboxSnapshotRequest, Modal.Client.SandboxSnapshotResponse)

  rpc(
    :SandboxSnapshotFs,
    Modal.Client.SandboxSnapshotFsRequest,
    Modal.Client.SandboxSnapshotFsResponse
  )

  rpc(
    :SandboxSnapshotFsAsync,
    Modal.Client.SandboxSnapshotFsAsyncRequest,
    Modal.Client.SandboxSnapshotFsAsyncResponse
  )

  rpc(
    :SandboxSnapshotFsAsyncGet,
    Modal.Client.SandboxSnapshotFsAsyncGetRequest,
    Modal.Client.SandboxSnapshotFsResponse
  )

  rpc(
    :SandboxSnapshotGet,
    Modal.Client.SandboxSnapshotGetRequest,
    Modal.Client.SandboxSnapshotGetResponse
  )

  rpc(
    :SandboxSnapshotWait,
    Modal.Client.SandboxSnapshotWaitRequest,
    Modal.Client.SandboxSnapshotWaitResponse
  )

  rpc(
    :SandboxStdinWrite,
    Modal.Client.SandboxStdinWriteRequest,
    Modal.Client.SandboxStdinWriteResponse
  )

  rpc(:SandboxTagsGet, Modal.Client.SandboxTagsGetRequest, Modal.Client.SandboxTagsGetResponse)

  rpc(:SandboxTagsSet, Modal.Client.SandboxTagsSetRequest, Google.Protobuf.Empty)

  rpc(
    :SandboxTerminate,
    Modal.Client.SandboxTerminateRequest,
    Modal.Client.SandboxTerminateResponse
  )

  rpc(
    :SandboxTerminateV2,
    Modal.Client.SandboxTerminateRequest,
    Modal.Client.SandboxTerminateResponse
  )

  rpc(:SandboxWait, Modal.Client.SandboxWaitRequest, Modal.Client.SandboxWaitResponse)

  rpc(
    :SandboxWaitUntilReady,
    Modal.Client.SandboxWaitUntilReadyRequest,
    Modal.Client.SandboxWaitUntilReadyResponse
  )

  rpc(:SandboxWaitV2, Modal.Client.SandboxWaitRequest, Modal.Client.SandboxWaitResponse)

  rpc(:SecretDelete, Modal.Client.SecretDeleteRequest, Google.Protobuf.Empty)

  rpc(
    :SecretGetOrCreate,
    Modal.Client.SecretGetOrCreateRequest,
    Modal.Client.SecretGetOrCreateResponse
  )

  rpc(:SecretList, Modal.Client.SecretListRequest, Modal.Client.SecretListResponse)

  rpc(:SecretUpdate, Modal.Client.SecretUpdateRequest, Google.Protobuf.Empty)

  rpc(:SharedVolumeDelete, Modal.Client.SharedVolumeDeleteRequest, Google.Protobuf.Empty)

  rpc(
    :SharedVolumeGetFile,
    Modal.Client.SharedVolumeGetFileRequest,
    Modal.Client.SharedVolumeGetFileResponse
  )

  rpc(
    :SharedVolumeGetOrCreate,
    Modal.Client.SharedVolumeGetOrCreateRequest,
    Modal.Client.SharedVolumeGetOrCreateResponse
  )

  rpc(:SharedVolumeHeartbeat, Modal.Client.SharedVolumeHeartbeatRequest, Google.Protobuf.Empty)

  rpc(
    :SharedVolumeList,
    Modal.Client.SharedVolumeListRequest,
    Modal.Client.SharedVolumeListResponse
  )

  rpc(
    :SharedVolumeListFiles,
    Modal.Client.SharedVolumeListFilesRequest,
    Modal.Client.SharedVolumeListFilesResponse
  )

  rpc(
    :SharedVolumeListFilesStream,
    Modal.Client.SharedVolumeListFilesRequest,
    stream(Modal.Client.SharedVolumeListFilesResponse)
  )

  rpc(
    :SharedVolumePutFile,
    Modal.Client.SharedVolumePutFileRequest,
    Modal.Client.SharedVolumePutFileResponse
  )

  rpc(:SharedVolumeRemoveFile, Modal.Client.SharedVolumeRemoveFileRequest, Google.Protobuf.Empty)

  rpc(
    :TaskClusterHello,
    Modal.Client.TaskClusterHelloRequest,
    Modal.Client.TaskClusterHelloResponse
  )

  rpc(:TaskCurrentInputs, Google.Protobuf.Empty, Modal.Client.TaskCurrentInputsResponse)

  rpc(
    :TaskGetCommandRouterAccess,
    Modal.Client.TaskGetCommandRouterAccessRequest,
    Modal.Client.TaskGetCommandRouterAccessResponse
  )

  rpc(:TaskGetInfo, Modal.Client.TaskGetInfoRequest, Modal.Client.TaskGetInfoResponse)

  rpc(:TaskList, Modal.Client.TaskListRequest, Modal.Client.TaskListResponse)

  rpc(:TaskResult, Modal.Client.TaskResultRequest, Google.Protobuf.Empty)

  rpc(:TokenFlowCreate, Modal.Client.TokenFlowCreateRequest, Modal.Client.TokenFlowCreateResponse)

  rpc(:TokenFlowWait, Modal.Client.TokenFlowWaitRequest, Modal.Client.TokenFlowWaitResponse)

  rpc(:TokenInfoGet, Modal.Client.TokenInfoGetRequest, Modal.Client.TokenInfoGetResponse)

  rpc(:TunnelStart, Modal.Client.TunnelStartRequest, Modal.Client.TunnelStartResponse)

  rpc(:TunnelStop, Modal.Client.TunnelStopRequest, Modal.Client.TunnelStopResponse)

  rpc(:VolumeCommit, Modal.Client.VolumeCommitRequest, Modal.Client.VolumeCommitResponse)

  rpc(:VolumeCopyFiles, Modal.Client.VolumeCopyFilesRequest, Google.Protobuf.Empty)

  rpc(:VolumeCopyFiles2, Modal.Client.VolumeCopyFiles2Request, Google.Protobuf.Empty)

  rpc(:VolumeDelete, Modal.Client.VolumeDeleteRequest, Google.Protobuf.Empty)

  rpc(:VolumeGetById, Modal.Client.VolumeGetByIdRequest, Modal.Client.VolumeGetByIdResponse)

  rpc(:VolumeGetFile, Modal.Client.VolumeGetFileRequest, Modal.Client.VolumeGetFileResponse)

  rpc(:VolumeGetFile2, Modal.Client.VolumeGetFile2Request, Modal.Client.VolumeGetFile2Response)

  rpc(
    :VolumeGetOrCreate,
    Modal.Client.VolumeGetOrCreateRequest,
    Modal.Client.VolumeGetOrCreateResponse
  )

  rpc(:VolumeHeartbeat, Modal.Client.VolumeHeartbeatRequest, Google.Protobuf.Empty)

  rpc(:VolumeList, Modal.Client.VolumeListRequest, Modal.Client.VolumeListResponse)

  rpc(
    :VolumeListFiles,
    Modal.Client.VolumeListFilesRequest,
    stream(Modal.Client.VolumeListFilesResponse)
  )

  rpc(
    :VolumeListFiles2,
    Modal.Client.VolumeListFiles2Request,
    stream(Modal.Client.VolumeListFiles2Response)
  )

  rpc(:VolumePutFiles, Modal.Client.VolumePutFilesRequest, Google.Protobuf.Empty)

  rpc(:VolumePutFiles2, Modal.Client.VolumePutFiles2Request, Modal.Client.VolumePutFiles2Response)

  rpc(:VolumeReload, Modal.Client.VolumeReloadRequest, Google.Protobuf.Empty)

  rpc(:VolumeRemoveFile, Modal.Client.VolumeRemoveFileRequest, Google.Protobuf.Empty)

  rpc(:VolumeRemoveFile2, Modal.Client.VolumeRemoveFile2Request, Google.Protobuf.Empty)

  rpc(:VolumeRename, Modal.Client.VolumeRenameRequest, Google.Protobuf.Empty)

  rpc(
    :WorkspaceBillingReport,
    Modal.Client.WorkspaceBillingReportRequest,
    stream(Modal.Client.WorkspaceBillingReportItem)
  )

  rpc(
    :WorkspaceDashboardUrlGet,
    Modal.Client.WorkspaceDashboardUrlRequest,
    Modal.Client.WorkspaceDashboardUrlResponse
  )

  rpc(:WorkspaceNameLookup, Google.Protobuf.Empty, Modal.Client.WorkspaceNameLookupResponse)
end

defmodule Modal.Client.ModalClient.Stub do
  @moduledoc false

  use GRPC.Stub, service: Modal.Client.ModalClient.Service
end
