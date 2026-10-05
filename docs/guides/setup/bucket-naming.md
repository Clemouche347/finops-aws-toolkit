# Référence — Nommage des buckets S3 FinOps

| Bucket (préfixe) | Account regional namespace *(recommandé)* | Global namespace | Wildcard IAM |
|---|---|---|---|
| `cur-exports` | `cur-exports-[ID]-us-east-1-an` | `cur-exports-[ID]` | `*cur-exports*` |
| `athena-results-cur` | `athena-results-cur-[ID]-us-east-1-an` | `athena-results-cur-[ID]` | `*athena-results*` |
| `athena-results-s3` | `athena-results-s3-[ID]-[region]-an` | `athena-results-s3-[ID]-[region]` | `*athena-results*` |
| `compute-optimizer-results` | `compute-optimizer-results-[ID]-[region]-an` | `compute-optimizer-results-[ID]-[region]` | `*compute-optimizer-results*` |
| `s3-inventory` | `s3-inventory-[ID]-[region]-an` | `s3-inventory-[ID]-[region]` | `*s3-inventory*` |
| `s3-logging` | `s3-logging-[ID]-[region]-an` | `s3-logging-[ID]-[region]` | `*s3-logging*` |

**Règle de nommage :**
- Buckets mono-région (us-east-1 forcé) : pas de région dans le nom (`cur-exports`, `athena-results-cur`)
- Buckets multi-région : région dans le nom (`[region]` = ex. `eu-west-3`)

**Les wildcards IAM matchent les deux namespaces** sans modification.
