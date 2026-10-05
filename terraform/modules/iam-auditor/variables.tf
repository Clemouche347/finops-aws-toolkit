variable "user_name" {
  description = "IAM username for the FinOps user created by this module."
  type        = string
  default     = "finops-auditor"
}

variable "profile" {
  description = "IAM profile: 'audit' (read + Athena only) or 'admin' (audit + FinOps infrastructure setup). See annexe A."
  type        = string
  default     = "admin"

  validation {
    condition     = contains(["audit", "admin"], var.profile)
    error_message = "Accepted values: 'audit' or 'admin'."
  }
}

variable "enable_iam_policy" {
  description = "Create and attach Finops-IAM. ⚠️ Allows creation and modification of customer managed policies — only enable when explicitly needed."
  type        = bool
  default     = false
}

variable "enable_tagging_policy" {
  description = "Create and attach Finops-tagging-all-resources (multi-service tagging across the whole account)."
  type        = bool
  default     = false
}

variable "resource_prefix" {
  description = "Optional prefix prepended to the IAM user and all policy names (hyphen separator, e.g. \"test\" → \"test-finops-auditor\", \"test-Finops-allow-audit\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the IAM user and all customer managed policies."
  type        = map(string)
  default     = {}
}
