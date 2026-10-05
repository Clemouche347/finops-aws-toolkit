variable "parameter_name" {
  description = "Nom du paramètre SSM. Doit commencer par AmazonCloudWatchAgent — scope imposé par la policy Finops-cloudwatch-agent."
  type        = string
  default     = "AmazonCloudWatchAgent-Config"
}

variable "agent_config_json" {
  description = "Contenu JSON de la configuration CloudWatch Agent. Si null, utilise la config standard RAM + disque à 300 s (source : annexe A2)."
  type        = string
  default     = null
}

variable "resource_prefix" {
  description = "Accepted for interface consistency. NOT applied to the SSM parameter name — see README for the SSM naming exception."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
