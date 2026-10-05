# Module `athena-workgroups`

Crée les workgroups Athena pour l'audit FinOps :
- `finops-cur` — requêtes CUR, us-east-1
- `finops-s3` — analyse S3 (access logs, inventory), région des buckets analysés

Les deux workgroups sont indépendants et contrôlés par des flags distincts. Même pattern qu'`audit-buckets` : appeler le module une fois pour le CUR (provider us-east-1), une fois par région pour le workgroup S3 (provider région cible).

## Configuration appliquée (les deux workgroups)

| Paramètre | Valeur |
|-----------|--------|
| Engine | Athena SQL (défaut) |
| Authentication | IAM (défaut) |
| Query result management | Customer managed |
| Override client-side settings | Oui (`enforce_workgroup_configuration = true`) |
| Bytes scanned cutoff | 100 GB → Cancel query |
| Chiffrement résultats | SSE_S3 |
| CloudWatch metrics | Activé (défaut) |

## Variables

| Variable | Type | Défaut | Description |
|----------|------|--------|-------------|
| `create_cur_workgroup` | `bool` | `false` | Active la création de `finops-cur`. Provider doit pointer sur us-east-1. |
| `athena_results_cur_bucket_name` | `string` | `null` | Nom du bucket résultats CUR — output `athena_results_cur_bucket_name` du module `audit-buckets`. |
| `create_s3_workgroup` | `bool` | `false` | Active la création de `finops-s3`. Provider doit pointer sur la région des buckets analysés. |
| `athena_results_s3_bucket_name` | `string` | `null` | Nom du bucket résultats S3 — output `athena_results_s3_bucket_name` du module `audit-buckets`. |
| `resource_prefix` | `string` | `""` | Préfixe optionnel ajouté aux noms des workgroups (séparateur underscore, ex. `"test"` → `"test_finops-cur"`). |
| `tags` | `map(string)` | `{}` | Tags appliqués aux workgroups Athena. |

## Outputs

| Output | Description |
|--------|-------------|
| `finops_cur_workgroup_name` | Nom du workgroup `finops-cur` (null si désactivé) |
| `finops_cur_workgroup_arn` | ARN du workgroup `finops-cur` (null si désactivé) |
| `finops_s3_workgroup_name` | Nom du workgroup `finops-s3` (null si désactivé) |
| `finops_s3_workgroup_arn` | ARN du workgroup `finops-s3` (null si désactivé) |

## Ce que ce module ne fait PAS

- Ne crée pas les buckets S3 de résultats — c'est le module `audit-buckets`.
- Ne configure pas le garde-fou de budget mensuel Athena (distinct du cutoff par requête) — action manuelle si besoin.
- N'active pas les named queries ni les prepared statements.
- Le workgroup `finops-s3` est optionnel (bloc analyse S3, voir `enable_s3_analysis` dans `examples/client-root`).
