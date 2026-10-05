locals {
  prefix_dash = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
}

# Server access logging — partitioned prefix format so AWS delivers logs under
# [account-id]/[region]/[source-bucket]/YYYY/MM/DD/ automatically.
# glue-s3-tables access_logs table expects exactly this path structure.
resource "aws_s3_bucket_logging" "this" {
  for_each = toset(var.source_bucket_names)

  bucket        = each.key
  target_bucket = var.logging_bucket_name
  target_prefix = ""

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# S3 Inventory — one configuration per source bucket.
# Reports land at s3://[inventory-bucket]/[source-bucket]/[inventory_prefix]/hive/dt=[date]/
# which is the LOCATION path expected by the glue-s3-tables inventory table.
resource "aws_s3_bucket_inventory" "this" {
  for_each = toset(var.source_bucket_names)

  bucket = each.key
  name   = "${local.prefix_dash}${var.inventory_prefix}"

  included_object_versions = "Current"

  schedule {
    frequency = var.inventory_frequency
  }

  destination {
    bucket {
      bucket_arn = "arn:aws:s3:::${var.inventory_bucket_name}"
      format     = var.inventory_format
    }
  }

  optional_fields = ["Size", "LastModifiedDate", "StorageClass", "ETag", "IntelligentTieringAccessTier", "LifecycleExpirationDate"]
}
