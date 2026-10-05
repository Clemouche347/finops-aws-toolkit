variable "cur_exports_bucket" {
  description = "Nom du bucket S3 qui reçoit les exports CUR — output `cur_exports_bucket_name` du module audit-buckets."
  type        = string
}

variable "export_prefix" {
  description = "Préfixe S3 configuré dans l'export Data Exports (champ 'S3 key prefix')."
  type        = string
  default     = "cur"
}

variable "export_name" {
  description = "Nom de l'export CUR — doit correspondre exactement au nom créé dans Data Exports."
  type        = string
  default     = "finops_cur"
}

variable "projection_start_date" {
  description = "Premier mois de données, format yyyy-MM (ex. 2025-12). Borne de départ de la partition projection."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}$", var.projection_start_date))
    error_message = "Format attendu : yyyy-MM, ex. 2025-12."
  }
}

variable "columns" {
  description = <<-EOT
    Schéma de la table CUR (~120 colonnes). À renseigner depuis le fichier create-table.sql
    généré par AWS dans :
      s3://[cur-exports-bucket]/[prefix]/[export_name]/metadata/BILLING_PERIOD=yyyy-MM/[export_name]-create-table.sql
    Laisser vide (défaut []) si le premier snapshot CUR n'est pas encore arrivé — la table
    est créée sans colonnes et devient requêtable dès que la variable est alimentée.
  EOT
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "resource_prefix" {
  description = "Optional prefix prepended to the Glue database and table names (underscore separator, e.g. \"test\" → \"test_finops_cur\")."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the Glue catalog database. aws_glue_catalog_table does not support tags."
  type        = map(string)
  default     = {}
}
