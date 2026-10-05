# Module `glue-s3-tables`

> **Bloc analyse S3 optionnel.** Ce module fait partie de l'ensemble `s3-inventory`/`s3-logging` (audit-buckets) + `finops-s3` (athena-workgroups) + `glue-s3-tables`. L'activation se pilote via la variable `enable_s3_analysis` au niveau de `examples/client-root`.

Crée la database Glue `finops_s3` et deux tables externes pour l'analyse des buckets S3 :
- `finops_s3.access_logs` — server access logging (RegexSerDe, schéma fixe)
- `finops_s3.inventory` — S3 Inventory CSV (OpenCSVSerde + SymlinkTextInputFormat, schéma variable)

La partition projection est activée sur les deux tables — aucun `MSCK REPAIR TABLE` nécessaire.

**Provider** : doit pointer sur la région des buckets analysés (pas us-east-1). Pour plusieurs régions, instancier le module une fois par région avec le provider correspondant (via `for_each` au niveau de `examples/client-root`).

---

## Table `access_logs`

Schéma fixe 27 colonnes, format AWS stable — entièrement codé dans le module.
Partition projection `year`/`month`/`day` (integer, digits).

Chemin LOCATION construit automatiquement depuis le format AWS des server access logs :
```
s3://[s3-logging-bucket]/[account-id]/[region]/[source-bucket]/
```
Les valeurs `account-id` et `region` sont lues via les data sources AWS — aucune variable supplémentaire.

---

## Table `inventory`

Schéma dépendant du `fileSchema` du `manifest.json` du premier snapshot S3 Inventory.

**Procédure après le premier snapshot (sous 48h après activation de l'inventory config) :**

```bash
# Repérer le manifest du dernier snapshot
aws s3 ls s3://[s3-inventory-bucket]/[source-bucket]/inventory-finops/hive/ --recursive | grep manifest.json | tail -1

# Télécharger et lire le fileSchema
aws s3 cp s3://[s3-inventory-bucket]/[source-bucket]/inventory-finops/hive/dt=[YYYY-MM-DD-HH-mm]/manifest.json /tmp/manifest.json
cat /tmp/manifest.json | python3 -m json.tool | grep fileSchema
```

Convertir `fileSchema` en liste Terraform pour `var.inventory_columns` :

```hcl
inventory_columns = [
  { name = "bucket",             type = "string" },
  { name = "key",                type = "string" },
  { name = "size",               type = "bigint" },
  { name = "last_modified_date", type = "string" },
  { name = "etag",               type = "string" },
  { name = "storage_class",      type = "string" },
  # ... adapter selon fileSchema réel
]
```

Tant que `var.inventory_columns = []` (défaut), la table existe dans Glue mais n'est pas requêtable.

---

## Variables

| Variable | Type | Défaut | Description |
|----------|------|--------|-------------|
| `s3_logging_bucket_name` | `string` | — | Bucket destination server access logs — output `s3_logging_bucket_name` de `audit-buckets`. |
| `s3_inventory_bucket_name` | `string` | — | Bucket destination S3 Inventory — output `s3_inventory_bucket_name` de `audit-buckets`. |
| `source_bucket_name` | `string` | — | Nom du bucket S3 source analysé. |
| `inventory_prefix` | `string` | `"inventory-finops"` | Préfixe configuré dans l'inventory configuration S3. |
| `access_logs_year_start` | `number` | `2025` | Première année de la partition projection access_logs. |
| `inventory_columns` | `list(object({name, type}))` | `[]` | Colonnes de la table inventory, depuis `fileSchema` du manifest.json. |
| `inventory_projection_start` | `string` | — | Date du premier snapshot inventory, format `yyyy-MM-dd-HH-mm` (ex. `2026-06-17-01-00`). |
| `resource_prefix` | `string` | `""` | Préfixe optionnel ajouté à la database et aux tables Glue (séparateur underscore, ex. `"test"` → `"test_finops_s3"`, `"test_access_logs"`, `"test_inventory"`). |
| `tags` | `map(string)` | `{}` | Tags appliqués à la Glue catalog database. `aws_glue_catalog_table` ne supporte pas l'argument `tags`. |

## Outputs

| Output | Description |
|--------|-------------|
| `database_name` | Nom de la database Glue (`finops_s3`). |
| `access_logs_table_name` | Nom de la table access_logs. |
| `access_logs_table_id` | Identifiant Glue complet de la table access_logs. |
| `access_logs_location` | Chemin S3 racine des access logs (sans partition). |
| `inventory_table_name` | Nom de la table inventory. |
| `inventory_table_id` | Identifiant Glue complet de la table inventory. |
| `inventory_location` | Chemin S3 racine des snapshots inventory (dossier `hive/`). |

---

## Ce que ce module ne fait PAS

- Ne crée pas les buckets S3 — c'est le module `audit-buckets` (`create_analysis_group = true`).
- Ne crée pas le workgroup Athena `finops-s3` — c'est le module `athena-workgroups` (`create_s3_workgroup = true`).
- Ne configure pas S3 Inventory sur les buckets source — action manuelle dans la console (étape 8 du setup guide).
- N'active pas le server access logging sur les buckets source — action manuelle dans la console (étape 8.5 du setup guide).
- Ne gère pas les databases CUR — c'est le module `glue-cur-table`.
