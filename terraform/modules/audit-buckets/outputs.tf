# Groupe CUR
output "cur_exports_bucket_name" {
  description = "Nom du bucket cur-exports (null si create_cur_group = false)"
  value       = try(aws_s3_bucket.cur_exports[0].bucket, null)
}

output "cur_exports_bucket_arn" {
  description = "ARN du bucket cur-exports (null si create_cur_group = false)"
  value       = try(aws_s3_bucket.cur_exports[0].arn, null)
}

output "athena_results_cur_bucket_name" {
  description = "Nom du bucket athena-results-cur (null si create_cur_group = false)"
  value       = try(aws_s3_bucket.athena_results_cur[0].bucket, null)
}

output "athena_results_cur_bucket_arn" {
  description = "ARN du bucket athena-results-cur (null si create_cur_group = false)"
  value       = try(aws_s3_bucket.athena_results_cur[0].arn, null)
}

# Groupe analyse S3
output "athena_results_s3_bucket_name" {
  description = "Nom du bucket athena-results-s3 (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.athena_results_s3[0].bucket, null)
}

output "athena_results_s3_bucket_arn" {
  description = "ARN du bucket athena-results-s3 (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.athena_results_s3[0].arn, null)
}

output "compute_optimizer_results_bucket_name" {
  description = "Nom du bucket compute-optimizer-results (null si create_compute_optimizer_bucket = false)"
  value       = try(aws_s3_bucket.compute_optimizer_results[0].bucket, null)
}

output "compute_optimizer_results_bucket_arn" {
  description = "ARN du bucket compute-optimizer-results (null si create_compute_optimizer_bucket = false)"
  value       = try(aws_s3_bucket.compute_optimizer_results[0].arn, null)
}

output "s3_inventory_bucket_name" {
  description = "Nom du bucket s3-inventory (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.s3_inventory[0].bucket, null)
}

output "s3_inventory_bucket_arn" {
  description = "ARN du bucket s3-inventory (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.s3_inventory[0].arn, null)
}

output "s3_logging_bucket_name" {
  description = "Nom du bucket s3-logging (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.s3_logging[0].bucket, null)
}

output "s3_logging_bucket_arn" {
  description = "ARN du bucket s3-logging (null si create_analysis_group = false)"
  value       = try(aws_s3_bucket.s3_logging[0].arn, null)
}
