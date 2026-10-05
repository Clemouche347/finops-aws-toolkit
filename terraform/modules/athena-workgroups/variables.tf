variable "create_cur_workgroup" {
  description = "Crée le workgroup finops-cur (us-east-1). Le provider doit pointer sur us-east-1."
  type        = bool
  default     = false
}

variable "athena_results_cur_bucket_name" {
  description = "Nom du bucket athena-results-cur (output du module audit-buckets). Requis si create_cur_workgroup = true."
  type        = string
  default     = null
}

variable "create_s3_workgroup" {
  description = "Crée le workgroup finops-s3 (région des buckets analysés). Le provider doit pointer sur la région cible."
  type        = bool
  default     = false
}

variable "athena_results_s3_bucket_name" {
  description = "Nom du bucket athena-results-s3 (output du module audit-buckets). Requis si create_s3_workgroup = true."
  type        = string
  default     = null
}

variable "resource_prefix" {
  description = "Optional prefix prepended to workgroup names (underscore separator, e.g. \"test\" → \"test_finops-cur\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
