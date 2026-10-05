output "configured_buckets" {
  description = "List of source bucket names that were configured (logging + inventory)."
  value       = keys(aws_s3_bucket_inventory.this)
}

output "inventory_destination_prefix" {
  description = "Base path in the inventory bucket where reports land: inventory_bucket_name/inventory_prefix. Full per-bucket path appends /[source-bucket]/hive/dt=[date]/."
  value       = "${var.inventory_bucket_name}/${var.inventory_prefix}"
}
