# Module : audit-buckets

Crée les buckets S3 d'audit FinOps, leurs bucket policies et leurs lifecycle rules.

## Ce que fait ce module

Trois groupes de buckets, activables indépendamment :

**Groupe CUR** (`create_cur_group = true`) — appeler avec un provider us-east-1 :
- `cur-exports-[ID]-us-east-1-an` — réception de l'export CUR 2.0 (policy bcm-data-exports + billingreports)
- `athena-results-cur-[ID]-us-east-1-an` — résultats des requêtes Athena CUR

**Compute Optimizer** (`create_compute_optimizer_bucket = true`) — appeler avec un provider région infra :
- `compute-optimizer-results-[ID]-[region]-an` — exports Compute Optimizer (policy compute-optimizer)

**Groupe analyse S3** (`create_analysis_group = true`) — appeler avec un provider région des buckets analysés :
- `athena-results-s3-[ID]-[region]-an` — résultats des requêtes Athena S3
- `s3-inventory-[ID]-[region]-an` — rapports S3 Inventory (policy s3.amazonaws.com)
- `s3-logging-[ID]-[region]-an` — server access logs (policy logging.s3.amazonaws.com)

Namespace par défaut : account-regional (suffixe `-an`). Variable `use_global_namespace` pour basculer.

## Variables

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `create_cur_group` | bool | false | Active le groupe CUR (us-east-1) |
| `create_compute_optimizer_bucket` | bool | false | Active le bucket Compute Optimizer (région infra) |
| `create_analysis_group` | bool | false | Active le groupe analyse S3 (région des buckets analysés) |
| `use_global_namespace` | bool | false | Global namespace au lieu de account-regional |
| `resource_prefix` | string | `""` | Préfixe optionnel ajouté au nom de base de chaque bucket (séparateur tiret, ex. `"test"` → `"test-cur-exports-..."`) |
| `tags` | map(string) | `{}` | Tags appliqués à chaque `aws_s3_bucket`. Les ressources associées (`aws_s3_bucket_public_access_block`, `aws_s3_bucket_policy`, `aws_s3_bucket_lifecycle_configuration`) ne supportent pas l'argument `tags`. |

## Appel type dans examples/client-root

```hcl
# Buckets CUR — toujours us-east-1
module "audit_buckets_cur" {
  source           = "../../modules/audit-buckets"
  providers        = { aws = aws.us_east_1 }
  create_cur_group = true
}

# Bucket Compute Optimizer — région infra
module "audit_buckets_compute_optimizer" {
  source                          = "../../modules/audit-buckets"
  providers                       = { aws = aws.eu_west_3 }
  create_compute_optimizer_bucket = true
}

# Buckets analyse S3 — conditionné par enable_s3_analysis dans la racine
module "audit_buckets_s3" {
  source                = "../../modules/audit-buckets"
  providers             = { aws = aws.eu_west_3 }
  create_analysis_group = true
}
```

## Lifecycle rules (source : guide setup étape 10)

| Bucket | Expiration |
|---|---|
| cur-exports | 456 jours |
| athena-results-cur | 30 jours |
| compute-optimizer-results | 90 jours |
| athena-results-s3 | 30 jours |
| s3-inventory | 90 jours |
| s3-logging | 90 jours |

## Ce que ce module NE fait PAS

- N'active PAS l'export CUR 2.0 (action manuelle ou hors-périmètre Terraform — voir guide setup étape 3)
- N'active PAS Compute Optimizer ni Cost Optimization Hub (opt-in root/admin — étape 5)
- Ne configure PAS les inventory configurations sur les buckets source (action du module `s3-source-config`)
- Ne configure PAS le server access logging sur les buckets source (action du module `s3-source-config`)
- Ne crée PAS les workgroups Athena → module `athena-workgroups`
- Provider AWS >= 6.37 requis pour `bucket_namespace = "account-regional"` (mars 2026)
