variable "s3_logging_bucket_name" {
  description = "Nom du bucket destination des server access logs — output `s3_logging_bucket_name` du module audit-buckets."
  type        = string
}

variable "s3_inventory_bucket_name" {
  description = "Nom du bucket destination des rapports S3 Inventory — output `s3_inventory_bucket_name` du module audit-buckets."
  type        = string
}

variable "source_bucket_names" {
  description = "Liste des buckets S3 sources analysés. Utilisé pour construire les chemins LOCATION et la partition projection bucket (enum) dans les deux tables."
  type        = list(string)
}

variable "inventory_prefix" {
  description = "Préfixe configuré dans l'inventory configuration S3 (champ 'Destination prefix'). Doit correspondre exactement à la configuration créée à l'étape 8 du setup guide."
  type        = string
  default     = "inventory-finops"
}

variable "access_logs_year_start" {
  description = "Première année couverte par la partition projection de la table access_logs. Doit précéder ou correspondre à la date d'activation du server access logging sur le bucket source."
  type        = number
  default     = 2025
}

variable "inventory_columns" {
  description = <<-EOT
    Schéma de la table inventory. À renseigner depuis le champ fileSchema du manifest.json
    du premier snapshot S3 Inventory :
      s3://[s3-inventory-bucket]/[source-bucket]/[inventory-prefix]/[YYYY-MM-DD]/manifest.json
    Laisser vide (défaut []) si le premier snapshot n'est pas encore arrivé — la table
    est créée sans colonnes et devient requêtable dès que la variable est alimentée.
  EOT
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "inventory_projection_start" {
  description = "Date du premier snapshot S3 Inventory, format yyyy-MM-dd-HH-mm (ex. 2026-06-17-01-00). Borne de départ de la partition projection dt. Lire dans le nom du dossier hive/ ou dans le champ creationTimestamp du manifest.json."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.inventory_projection_start))
    error_message = "Format attendu : yyyy-MM-dd-HH-mm, ex. 2026-06-17-01-00."
  }
}

variable "resource_prefix" {
  description = "Optional prefix prepended to the Glue database and table names (underscore separator, e.g. \"test\" → \"test_finops_s3\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the Glue catalog database. aws_glue_catalog_table does not support tags."
  type        = map(string)
  default     = {}
}
