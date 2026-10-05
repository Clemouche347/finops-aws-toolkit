variable "source_bucket_names" {
  description = "Source S3 bucket names to configure (server access logging + S3 Inventory)."
  type        = list(string)
}

variable "logging_bucket_name" {
  description = "Destination bucket for server access logs — output `s3_logging_bucket_name` of audit-buckets."
  type        = string
}

variable "inventory_bucket_name" {
  description = "Destination bucket for S3 Inventory reports — output `s3_inventory_bucket_name` of audit-buckets."
  type        = string
}

variable "inventory_prefix" {
  description = <<-EOT
    S3 Inventory configuration name and sub-folder used in the destination bucket.
    Must match the inventory_prefix variable of glue-s3-tables — both resolve to the same S3 path segment.
    Convention: "inventory-finops".
  EOT
  type        = string
  default     = "inventory-finops"
}

variable "inventory_frequency" {
  description = "S3 Inventory delivery frequency."
  type        = string
  default     = "Weekly"

  validation {
    condition     = contains(["Daily", "Weekly"], var.inventory_frequency)
    error_message = "inventory_frequency must be \"Daily\" or \"Weekly\"."
  }
}

variable "inventory_format" {
  description = "S3 Inventory output format."
  type        = string
  default     = "Parquet"

  validation {
    condition     = contains(["CSV", "Parquet", "ORC"], var.inventory_format)
    error_message = "inventory_format must be \"CSV\", \"Parquet\", or \"ORC\"."
  }
}

variable "resource_prefix" {
  description = "Optional prefix prepended to the inventory configuration name (hyphen separator, e.g. \"test\" → \"test-inventory-finops\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Accepted for interface consistency. aws_s3_bucket_logging and aws_s3_bucket_inventory do not support tags."
  type        = map(string)
  default     = {}
}
