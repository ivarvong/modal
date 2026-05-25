defmodule Modal.CloudBucket do
  @moduledoc """
  Mount an S3 / R2 / GCS bucket at a path inside a Modal sandbox or
  function. The most-asked-for Modal feature for data-heavy ML
  workloads — bucket contents appear as a filesystem path, no
  upload step required.

      bucket = %Modal.CloudBucket{
        bucket_name: "my-training-data",
        type: :s3,
        mount_path: "/data",
        secret_id: aws_secret_id,
        read_only: true
      }

      Modal.Sandbox.create(client,
        app_id: app.id,
        image_id: image_id,
        cloud_bucket_mounts: [bucket],
        cmd: ["python", "train.py"]
      )

  ## Credentials

  `:secret_id` is the `Modal.Secret` holding the cloud provider's
  credentials. Modal expects standard env-var names inside the
  secret:

    * **S3**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional
      `AWS_SESSION_TOKEN`.
    * **R2**: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. Pair with
      `:endpoint_url` pointing at your account-specific R2 endpoint.
    * **GCS**: `GOOGLE_APPLICATION_CREDENTIALS_JSON` (the JSON key
      file content, as a string).

  ## Read-only vs read-write

  Default is read-write. For training workloads where the bucket is
  the source of truth and the sandbox just reads, set `read_only:
  true` — Modal can optimize caching and concurrent access.

  ## Key prefix

  `:key_prefix` mounts only objects under a sub-prefix:

      %Modal.CloudBucket{bucket_name: "shared", key_prefix: "user-42/", mount_path: "/u"}

  Inside the container `/u/foo.txt` is `shared/user-42/foo.txt` in
  the bucket. Useful for multi-tenant isolation without per-tenant
  buckets.
  """

  @enforce_keys [:bucket_name, :type, :mount_path]
  defstruct [
    :bucket_name,
    :type,
    :mount_path,
    :secret_id,
    :endpoint_url,
    :key_prefix,
    read_only: false,
    requester_pays: false
  ]

  @type bucket_type :: :s3 | :r2 | :gcs

  @type t :: %__MODULE__{
          bucket_name: String.t(),
          type: bucket_type(),
          mount_path: String.t(),
          secret_id: String.t() | nil,
          endpoint_url: String.t() | nil,
          key_prefix: String.t() | nil,
          read_only: boolean(),
          requester_pays: boolean()
        }

  @doc false
  # Used by Modal.Sandbox to convert the public struct into the
  # proto Modal's API expects. Not part of the public API.
  @spec to_proto(t()) :: Modal.Client.CloudBucketMount.t()
  def to_proto(%__MODULE__{} = b) do
    %Modal.Client.CloudBucketMount{
      bucket_name: b.bucket_name,
      mount_path: b.mount_path,
      bucket_type: bucket_type_atom(b.type),
      read_only: b.read_only,
      requester_pays: b.requester_pays,
      credentials_secret_id: b.secret_id || "",
      bucket_endpoint_url: b.endpoint_url,
      key_prefix: b.key_prefix
    }
  end

  defp bucket_type_atom(:s3), do: :S3
  defp bucket_type_atom(:r2), do: :R2
  defp bucket_type_atom(:gcs), do: :GCP
  defp bucket_type_atom(:gcp), do: :GCP

  defp bucket_type_atom(other),
    do:
      raise(
        ArgumentError,
        "Modal.CloudBucket :type must be :s3, :r2, or :gcs; got #{inspect(other)}"
      )

  defimpl Inspect do
    def inspect(%Modal.CloudBucket{} = b, _opts) do
      flag = if b.read_only, do: "ro", else: "rw"

      "#Modal.CloudBucket<#{b.type}://#{b.bucket_name}" <>
        if(b.key_prefix, do: "/#{b.key_prefix}", else: "") <>
        " → #{b.mount_path} (#{flag})>"
    end
  end
end
