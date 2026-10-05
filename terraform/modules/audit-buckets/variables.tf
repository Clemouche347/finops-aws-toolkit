variable "use_global_namespace" {
  description = "Utilise le global S3 namespace plutôt que le account-regional namespace (défaut). Voir tableau des noms dans CLAUDE.md."
  type        = bool
  default     = false
}

variable "create_cur_group" {
  description = "Crée les buckets CUR (cur-exports, athena-results-cur). Le provider passé doit pointer sur us-east-1."
  type        = bool
  default     = false
}

variable "create_compute_optimizer_bucket" {
  description = "Crée le bucket compute-optimizer-results. Le provider doit pointer sur la région infra."
  type        = bool
  default     = false
}

variable "create_analysis_group" {
  description = "Crée les buckets d'analyse S3 (athena-results-s3, s3-inventory, s3-logging). Le provider doit pointer sur la région des buckets analysés."
  type        = bool
  default     = false
}

variable "resource_prefix" {
  description = "Optional prefix prepended to all S3 bucket base names (hyphen separator, e.g. \"test\" → \"test-cur-exports-...\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all S3 buckets."
  type        = map(string)
  default     = {}
}
