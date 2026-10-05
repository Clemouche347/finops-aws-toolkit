locals {
  # Standard RAM + disk config — source: docs/guides/setup/annexe-A2-cloudwatch-agent.md
  default_config = jsonencode({
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId   = "$${aws:InstanceId}"
        InstanceType = "$${aws:InstanceType}"
      }
      metrics_collected = {
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 300
        }
        disk = {
          measurement                 = ["used_percent"]
          resources                   = ["*"]
          metrics_collection_interval = 300
        }
      }
    }
  })

  config_value = coalesce(var.agent_config_json, local.default_config)
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = var.parameter_name
  type  = "String"
  value = local.config_value
  tags  = var.tags
}
