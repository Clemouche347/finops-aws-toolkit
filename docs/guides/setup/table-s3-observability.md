# Architecture FinOps S3 — choix par région

| Composant            | Cardinalité          | Portée                                      | Justification |
|----------------------|----------------------|---------------------------------------------|---------------|
| Workgroup Athena     | 1 / région           | Tous buckets, logs + inventory              | Frontière quota/coût/output, pas de logique schéma |
| Bucket athena_results| 1 / région           | Tous résultats de requête                   | Output unique, lifecycle 30j déjà défini |
| Bucket s3_logging    | 1 / région           | Reçoit les access logs de tous les buckets  | Format AWS range déjà par account/region/bucket |
| Bucket s3_inventory  | 1 / région           | Reçoit les inventaires de tous les buckets  | Idem, préfixe par bucket |
| Database Glue        | 1 / région (finops_s3)| Namespace commun                           | Pas de bénéfice à découper |
| Table access_logs    | 1 commune / région   | Tous buckets, partition `bucket` (enum)     | Schéma fixe identique, requête transverse |
| Table inventory      | 1 / bucket (défaut)  | 1 bucket chacune                            | fileSchema potentiellement divergent entre buckets |