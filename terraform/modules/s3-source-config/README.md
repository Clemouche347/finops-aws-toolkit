# Module `s3-source-config`

> **Bloc analyse S3 optionnel.** Ce module fait partie de l'ensemble `s3-inventory`/`s3-logging` (audit-buckets) + `finops-s3` (athena-workgroups) + `glue-s3-tables`. L'activation se pilote via `enable_s3_analysis` au niveau de `client-root/terraform-<region>`.

Configure chaque bucket S3 source pour :
- **Server access logging** — livraison vers le bucket `s3-logging`, format partitionné automatique `[account-id]/[region]/[source-bucket]/YYYY/MM/DD/`. Structure attendue par la table `access_logs` de `glue-s3-tables`.
- **S3 Inventory** — configuration `[inventory_prefix]` (défaut `inventory-finops`), livraison vers le bucket `s3-inventory` sous `[source-bucket]/[inventory_prefix]/hive/dt=[date]/`. Structure attendue par la table `inventory` de `glue-s3-tables`.

**Important :** `var.inventory_prefix` doit avoir la même valeur que `inventory_prefix` dans `glue-s3-tables` — les deux variables pointent vers le même segment de chemin S3.

---

## Variables

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `source_bucket_names` | `list(string)` | — | Buckets source à configurer. |
| `logging_bucket_name` | `string` | — | Bucket destination des access logs — output `s3_logging_bucket_name` de `audit-buckets`. |
| `inventory_bucket_name` | `string` | — | Bucket destination des inventaires — output `s3_inventory_bucket_name` de `audit-buckets`. |
| `inventory_prefix` | `string` | `"inventory-finops"` | Nom de la configuration S3 Inventory et segment de chemin dans le bucket destination. Doit correspondre à `inventory_prefix` de `glue-s3-tables`. |
| `inventory_frequency` | `string` | `"Weekly"` | Fréquence de livraison : `"Daily"` ou `"Weekly"`. |
| `inventory_format` | `string` | `"Parquet"` | Format de livraison : `"CSV"`, `"Parquet"` ou `"ORC"`. |
| `resource_prefix` | `string` | `""` | Préfixe optionnel ajouté au nom de la configuration inventory (séparateur tiret, ex. `"test"` → `"test-inventory-finops"`). |
| `tags` | `map(string)` | `{}` | Accepté pour cohérence d'interface. `aws_s3_bucket_logging` et `aws_s3_bucket_inventory` ne supportent pas les tags. |

## Outputs

| Output | Description |
|---|---|
| `configured_buckets` | Liste des buckets source configurés. |
| `inventory_destination_prefix` | Chemin de base dans le bucket inventory : `inventory_bucket_name/inventory_prefix`. |

## Exemple d'appel minimal

```hcl
module "s3_source_config" {
  source = "../../../../finops-aws-toolkit/terraform/modules/s3-source-config"

  source_bucket_names   = ["my-app-bucket", "my-data-bucket"]
  logging_bucket_name   = module.audit_buckets_infra.s3_logging_bucket_name
  inventory_bucket_name = module.audit_buckets_infra.s3_inventory_bucket_name
  resource_prefix       = var.resource_prefix
  tags                  = local.common_tags
}
```

---

## Ce que ce module ne fait PAS

- Ne crée pas les buckets destination — c'est le module `audit-buckets` (`create_analysis_group = true`).
- Ne crée pas la database et les tables Glue — c'est le module `glue-s3-tables`.
- Ne crée pas le workgroup Athena — c'est le module `athena-workgroups` (`create_s3_workgroup = true`).
- Ne configure pas le schéma de la table `inventory` — renseigner `inventory_columns` dans `glue-s3-tables` après le premier snapshot (voir README de ce module).
