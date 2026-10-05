output "database_name" {
  description = "Nom de la database Glue."
  value       = aws_glue_catalog_database.finops_cur.name
}

output "table_name" {
  description = "Nom de la table externe Glue."
  value       = aws_glue_catalog_table.finops_cur.name
}

output "table_id" {
  description = "Identifiant Glue de la table (catalog_id:database_name:table_name)."
  value       = aws_glue_catalog_table.finops_cur.id
}

output "s3_data_location" {
  description = "Chemin S3 racine des données CUR (sans partition)."
  value       = local.data_location
}
