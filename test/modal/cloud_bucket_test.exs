defmodule Modal.CloudBucketTest do
  @moduledoc """
  Tests for `Modal.CloudBucket` — the struct + its proto translation
  + integration into `Modal.Sandbox.create/2`'s `:cloud_bucket_mounts`
  option.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  @client :mock
  @app %Modal.App{id: "ap-test", name: "test", client: @client}

  describe "to_proto/1" do
    test "S3 bucket with full options maps to CloudBucketMount" do
      bucket = %Modal.CloudBucket{
        bucket_name: "my-data",
        type: :s3,
        mount_path: "/data",
        secret_id: "st-aws",
        read_only: true,
        requester_pays: false
      }

      assert %Modal.Client.CloudBucketMount{
               bucket_name: "my-data",
               mount_path: "/data",
               bucket_type: :S3,
               read_only: true,
               requester_pays: false,
               credentials_secret_id: "st-aws"
             } = Modal.CloudBucket.to_proto(bucket)
    end

    test "R2 + custom endpoint_url" do
      bucket = %Modal.CloudBucket{
        bucket_name: "my-r2",
        type: :r2,
        mount_path: "/r2",
        secret_id: "st-r2",
        endpoint_url: "https://accountid.r2.cloudflarestorage.com"
      }

      proto = Modal.CloudBucket.to_proto(bucket)
      assert proto.bucket_type == :R2
      assert proto.bucket_endpoint_url == "https://accountid.r2.cloudflarestorage.com"
    end

    test "GCS bucket type accepts :gcs or :gcp alias" do
      assert %{bucket_type: :GCP} =
               Modal.CloudBucket.to_proto(%Modal.CloudBucket{
                 bucket_name: "x",
                 type: :gcs,
                 mount_path: "/x"
               })

      assert %{bucket_type: :GCP} =
               Modal.CloudBucket.to_proto(%Modal.CloudBucket{
                 bucket_name: "x",
                 type: :gcp,
                 mount_path: "/x"
               })
    end

    test "key_prefix flows through" do
      proto =
        Modal.CloudBucket.to_proto(%Modal.CloudBucket{
          bucket_name: "shared",
          type: :s3,
          mount_path: "/u",
          key_prefix: "user-42/"
        })

      assert proto.key_prefix == "user-42/"
    end

    test "unknown bucket type raises ArgumentError" do
      assert_raise ArgumentError, ~r/:s3, :r2, or :gcs/, fn ->
        Modal.CloudBucket.to_proto(%Modal.CloudBucket{
          bucket_name: "x",
          type: :azure,
          mount_path: "/x"
        })
      end
    end
  end

  describe "Sandbox :cloud_bucket_mounts integration" do
    test "list of CloudBuckets flows into Sandbox.cloud_bucket_mounts on the wire" do
      buckets = [
        %Modal.CloudBucket{bucket_name: "a", type: :s3, mount_path: "/a", secret_id: "st-1"},
        %Modal.CloudBucket{
          bucket_name: "b",
          type: :r2,
          mount_path: "/b",
          secret_id: "st-2",
          read_only: true
        }
      ]

      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, req, _ ->
        assert [
                 %Modal.Client.CloudBucketMount{
                   bucket_name: "a",
                   bucket_type: :S3,
                   mount_path: "/a",
                   read_only: false
                 },
                 %Modal.Client.CloudBucketMount{
                   bucket_name: "b",
                   bucket_type: :R2,
                   mount_path: "/b",
                   read_only: true
                 }
               ] = req.definition.cloud_bucket_mounts

        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: "sb-1"}}
      end)

      assert {:ok, _} =
               Modal.Sandbox.create(@client,
                 app_id: @app.id,
                 image_id: "im",
                 cloud_bucket_mounts: buckets
               )
    end

    test "no :cloud_bucket_mounts leaves the proto field empty" do
      Modal.Client.Mock
      |> expect(:rpc, fn _, :sandbox_create, req, _ ->
        assert req.definition.cloud_bucket_mounts == []
        {:ok, %Modal.Client.SandboxCreateResponse{sandbox_id: "sb-1"}}
      end)

      Modal.Sandbox.create(@client, app_id: @app.id, image_id: "im")
    end

    test "non-CloudBucket entry raises ArgumentError" do
      assert_raise ArgumentError, ~r/CloudBucket/, fn ->
        Modal.Sandbox.create(@client,
          app_id: @app.id,
          image_id: "im",
          cloud_bucket_mounts: [%{not: "a bucket"}]
        )
      end
    end
  end

  describe "Inspect" do
    test "human-readable summary with mount + ro/rw flag + key_prefix" do
      assert inspect(%Modal.CloudBucket{
               bucket_name: "data",
               type: :s3,
               mount_path: "/data",
               read_only: true
             }) =~ "s3://data → /data (ro)"

      assert inspect(%Modal.CloudBucket{
               bucket_name: "shared",
               type: :r2,
               mount_path: "/u",
               key_prefix: "user-42/"
             }) =~ "r2://shared/user-42/"
    end
  end
end
