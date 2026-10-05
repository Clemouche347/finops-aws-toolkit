# Module `glue-cur-table`

Crée la database Glue `finops_cur` et la table externe `finops_cur.finops_cur` pour requêter le CUR 2.0 avec Athena.

La partition projection (`TBLPROPERTIES`) est activée dès la création — aucun `MSCK REPAIR TABLE` ni `ALTER TABLE ADD PARTITION` nécessaire lors des nouvelles périodes de facturation.

**Provider** : doit pointer sur `us-east-1` (contrainte AWS pour CUR et Athena CUR).

## Schéma des colonnes — point d'attention

Le schéma (~120 colonnes) n'est connu qu'après réception du premier fichier CUR. AWS génère le fichier de référence à l'emplacement suivant :

```
s3://[cur-exports-bucket]/[prefix]/[export_name]/metadata/BILLING_PERIOD=yyyy-MM/[export_name]-create-table.sql
```

Récupération :

```bash
aws s3 cp s3://[cur-exports-bucket]/cur/finops_cur/metadata/BILLING_PERIOD=yyyy-MM/finops_cur-create-table.sql /tmp/ref.sql
```

Convertir les colonnes du `CREATE TABLE` en liste Terraform pour `var.columns`, puis relancer `terraform apply`.

Tant que `var.columns = []` (défaut), la table existe dans le catalogue Glue mais n'est pas requêtable.

## Variables

| Variable | Type | Défaut | Description |
|----------|------|--------|-------------|
| `cur_exports_bucket` | `string` | — | Nom du bucket CUR — output `cur_exports_bucket_name` du module `audit-buckets`. |
| `export_prefix` | `string` | `"cur"` | Préfixe S3 configuré dans Data Exports. |
| `export_name` | `string` | `"finops_cur"` | Nom de l'export CUR (doit correspondre exactement à Data Exports). |
| `projection_start_date` | `string` | — | Premier mois de données, format `yyyy-MM` (ex. `2025-12`). |
| `columns` | `list(object({name, type}))` | `[]` | Colonnes de la table. Vide jusqu'à réception du `create-table.sql` AWS. |
| `resource_prefix` | `string` | `""` | Préfixe optionnel ajouté à la database et à la table Glue (séparateur underscore, ex. `"test"` → `"test_finops_cur"`). N'affecte pas `export_name` (nom de l'export CUR dans Data Exports, externe à Terraform). |
| `tags` | `map(string)` | `{}` | Tags appliqués à la Glue catalog database. `aws_glue_catalog_table` ne supporte pas l'argument `tags`. |

## Outputs

| Output | Description |
|--------|-------------|
| `database_name` | Nom de la database Glue (`finops_cur`). |
| `table_name` | Nom de la table Glue (`finops_cur`). |
| `table_id` | Identifiant Glue complet de la table. |
| `s3_data_location` | Chemin S3 racine des données (sans partition). |

## Ce que ce module ne fait PAS

- Ne crée pas le bucket CUR ni le bucket résultats Athena — c'est le module `audit-buckets`.
- Ne crée pas le workgroup Athena `finops-cur` — c'est le module `athena-workgroups`.
- Ne crée pas l'export CUR lui-même — action manuelle dans la console AWS Data Exports (voir guide de setup).
- Ne déclenche pas le chargement initial des partitions — inutile grâce à la partition projection.
- Ne gère pas la base de données `finops_s3` ni les tables d'analyse S3 — c'est le module `glue-s3-tables`.
