output "user_arn" {
  description = "ARN of the FinOps IAM user."
  value       = aws_iam_user.finops.arn
}

output "user_name" {
  description = "Name of the FinOps IAM user."
  value       = aws_iam_user.finops.name
}

output "attached_policy_arns" {
  description = "Map of policies attached to the user (key = internal identifier, value = ARN)."
  value       = local.all_policy_arns
}
