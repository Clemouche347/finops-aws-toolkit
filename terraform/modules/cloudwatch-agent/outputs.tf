output "parameter_name" {
  description = "Nom du paramètre SSM CloudWatch Agent."
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}

output "parameter_arn" {
  description = "ARN du paramètre SSM CloudWatch Agent."
  value       = aws_ssm_parameter.cloudwatch_agent_config.arn
}
