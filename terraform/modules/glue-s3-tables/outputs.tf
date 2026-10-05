output "database_name" {
  description = "Nom de la database Glue."
  value       = aws_glue_catalog_database.finops_s3.name
}

output "access_logs_table_name" {
  description = "Nom de la table externe access_logs."
  value       = aws_glue_catalog_table.access_logs.name
}

output "access_logs_table_id" {
  description = "Identifiant Glue de la table access_logs (catalog_id:database_name:table_name)."
  value       = aws_glue_catalog_table.access_logs.id
}

output "access_logs_base" {
  description = "Préfixe S3 racine des access logs (tous buckets)"
  value       = local.access_logs_base
}

output "inventory_table_name" {
  description = "Nom de la table externe inventory."
  value       = aws_glue_catalog_table.inventory.name
}

output "inventory_table_id" {
  description = "Identifiant Glue de la table inventory (catalog_id:database_name:table_name)."
  value       = aws_glue_catalog_table.inventory.id
}

output "inventory_base" {
  description = "Préfixe S3 racine de l'inventory (tous buckets)"
  value       = local.inventory_base
}
