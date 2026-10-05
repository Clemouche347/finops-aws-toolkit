locals {
  prefix_under = var.resource_prefix != "" ? "${var.resource_prefix}_" : ""
}

# =============================================================
# CUR workgroup — provider must target us-east-1
# =============================================================

resource "aws_athena_workgroup" "finops_cur" {
  count = var.create_cur_workgroup ? 1 : 0

  name          = "${local.prefix_under}finops-cur"
  description   = "Audit FinOps - lecture CUR uniquement"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    # 100 GB circuit breaker — cancels the query without blocking legitimate ones
    bytes_scanned_cutoff_per_query = 107374182400

    result_configuration {
      output_location = "s3://${var.athena_results_cur_bucket_name}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.tags
}

# =============================================================
# S3 analysis workgroup — provider must target the analyzed buckets region
# One call per region for multi-region deployments (same pattern as audit-buckets)
# =============================================================

resource "aws_athena_workgroup" "finops_s3" {
  count = var.create_s3_workgroup ? 1 : 0

  name          = "${local.prefix_under}finops-s3"
  description   = "Audit FinOps - analyse S3 (access logs, inventory)"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 107374182400 # 100 GB

    result_configuration {
      output_location = "s3://${var.athena_results_s3_bucket_name}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.tags
}
