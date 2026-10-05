output "finops_cur_workgroup_name" {
  description = "Nom du workgroup Athena finops-cur (null si create_cur_workgroup = false)"
  value       = try(aws_athena_workgroup.finops_cur[0].name, null)
}

output "finops_cur_workgroup_arn" {
  description = "ARN du workgroup Athena finops-cur (null si create_cur_workgroup = false)"
  value       = try(aws_athena_workgroup.finops_cur[0].arn, null)
}

output "finops_s3_workgroup_name" {
  description = "Nom du workgroup Athena finops-s3 (null si create_s3_workgroup = false)"
  value       = try(aws_athena_workgroup.finops_s3[0].name, null)
}

output "finops_s3_workgroup_arn" {
  description = "ARN du workgroup Athena finops-s3 (null si create_s3_workgroup = false)"
  value       = try(aws_athena_workgroup.finops_s3[0].arn, null)
}
