data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  prefix_dash = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
}

# =============================================================
# CUR group — provider must target us-east-1
# =============================================================

resource "aws_s3_bucket" "cur_exports" {
  count = var.create_cur_group ? 1 : 0

  # global namespace: cur-exports-[ID] (no region, per CLAUDE.md naming table)
  bucket           = var.use_global_namespace ? "${local.prefix_dash}cur-exports-${local.account_id}" : "${local.prefix_dash}cur-exports-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "cur_exports" {
  count  = var.create_cur_group ? 1 : 0
  bucket = aws_s3_bucket.cur_exports[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Policy applied by the CUR wizard — managed here for Terraform consistency
resource "aws_s3_bucket_policy" "cur_exports" {
  count  = var.create_cur_group ? 1 : 0
  bucket = aws_s3_bucket.cur_exports[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EnableAWSDataExportsToWriteToS3AndCheckPolicy"
      Effect = "Allow"
      Principal = {
        Service = [
          "bcm-data-exports.amazonaws.com",
          "billingreports.amazonaws.com",
        ]
      }
      Action = [
        "s3:PutObject",
        "s3:GetBucketPolicy",
      ]
      Resource = [
        aws_s3_bucket.cur_exports[0].arn,
        "${aws_s3_bucket.cur_exports[0].arn}/*",
      ]
      Condition = {
        StringLike = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn" = [
            "arn:aws:cur:us-east-1:${local.account_id}:definition/*",
            "arn:aws:bcm-data-exports:us-east-1:${local.account_id}:export/*",
          ]
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.cur_exports]
}

resource "aws_s3_bucket_lifecycle_configuration" "cur_exports" {
  count  = var.create_cur_group ? 1 : 0
  bucket = aws_s3_bucket.cur_exports[0].id

  rule {
    id     = "expire-cur-exports"
    status = "Enabled"
    filter {}
    expiration {
      days = 456
    }
  }
}

resource "aws_s3_bucket" "athena_results_cur" {
  count = var.create_cur_group ? 1 : 0

  bucket           = var.use_global_namespace ? "${local.prefix_dash}athena-results-cur-${local.account_id}" : "${local.prefix_dash}athena-results-cur-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "athena_results_cur" {
  count  = var.create_cur_group ? 1 : 0
  bucket = aws_s3_bucket.athena_results_cur[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results_cur" {
  count  = var.create_cur_group ? 1 : 0
  bucket = aws_s3_bucket.athena_results_cur[0].id

  rule {
    id     = "expire-athena-results-cur"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# =============================================================
# S3 analysis group — provider must target the infra region
# =============================================================

resource "aws_s3_bucket" "athena_results_s3" {
  count = var.create_analysis_group ? 1 : 0

  # global namespace: athena-results-s3-[ID]-[region] (with region, per naming table)
  bucket           = var.use_global_namespace ? "${local.prefix_dash}athena-results-s3-${local.account_id}-${local.region}" : "${local.prefix_dash}athena-results-s3-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "athena_results_s3" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.athena_results_s3[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results_s3" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.athena_results_s3[0].id

  rule {
    id     = "expire-athena-results-s3"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# =============================================================
# Compute Optimizer — provider must target the infra region
# =============================================================

resource "aws_s3_bucket" "compute_optimizer_results" {
  count = var.create_compute_optimizer_bucket ? 1 : 0

  bucket           = var.use_global_namespace ? "${local.prefix_dash}compute-optimizer-results-${local.account_id}-${local.region}" : "${local.prefix_dash}compute-optimizer-results-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "compute_optimizer_results" {
  count  = var.create_compute_optimizer_bucket ? 1 : 0
  bucket = aws_s3_bucket.compute_optimizer_results[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "compute_optimizer_results" {
  count  = var.create_compute_optimizer_bucket ? 1 : 0
  bucket = aws_s3_bucket.compute_optimizer_results[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "compute-optimizer.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.compute_optimizer_results[0].arn
      },
      {
        Effect    = "Allow"
        Principal = { Service = "compute-optimizer.amazonaws.com" }
        Action    = "s3:GetBucketPolicyStatus"
        Resource  = aws_s3_bucket.compute_optimizer_results[0].arn
      },
      {
        Effect    = "Allow"
        Principal = { Service = "compute-optimizer.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.compute_optimizer_results[0].arn}/compute-optimizer/${local.account_id}/*",
          "${aws_s3_bucket.compute_optimizer_results[0].arn}/*/compute-optimizer/${local.account_id}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:compute-optimizer:${local.region}:${local.account_id}:*"
          }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.compute_optimizer_results]
}

resource "aws_s3_bucket_lifecycle_configuration" "compute_optimizer_results" {
  count  = var.create_compute_optimizer_bucket ? 1 : 0
  bucket = aws_s3_bucket.compute_optimizer_results[0].id

  rule {
    id     = "expire-compute-optimizer"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket" "s3_inventory" {
  count = var.create_analysis_group ? 1 : 0

  bucket           = var.use_global_namespace ? "${local.prefix_dash}s3-inventory-${local.account_id}-${local.region}" : "${local.prefix_dash}s3-inventory-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "s3_inventory" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_inventory[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "s3_inventory" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_inventory[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "InventoryPolicy"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.s3_inventory[0].arn}/*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "s3:x-amz-acl"      = "bucket-owner-full-control"
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3:::*"
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.s3_inventory]
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_inventory" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_inventory[0].id

  rule {
    id     = "expire-inventory-reports"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket" "s3_logging" {
  count = var.create_analysis_group ? 1 : 0

  bucket           = var.use_global_namespace ? "${local.prefix_dash}s3-logging-${local.account_id}-${local.region}" : "${local.prefix_dash}s3-logging-${local.account_id}-${local.region}-an"
  bucket_namespace = var.use_global_namespace ? null : "account-regional"
  tags             = var.tags
}

resource "aws_s3_bucket_public_access_block" "s3_logging" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_logging[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allows the S3 server access logging service to write to this bucket
resource "aws_s3_bucket_policy" "s3_logging" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_logging[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.s3_logging[0].arn}/*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.s3_logging]
}
resource "aws_s3_bucket_lifecycle_configuration" "s3_logging" {
  count  = var.create_analysis_group ? 1 : 0
  bucket = aws_s3_bucket.s3_logging[0].id

  rule {
    id     = "expire-server-access-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}
