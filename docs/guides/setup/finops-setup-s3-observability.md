# S3 Observabilité — Analyses des buckets S3
*Extrait du guide finops-setup-guide.md — blocs relatifs à l'analyse S3*

---

## Étape 2 bis — Créer le(s) bucket(s) S3 pour les résultats Athena des analyses des buckets s3

Reproduire l'étape 2
**Account regional namespace** *(recommandé)* : préfixe `athena-results-s3`
AWS Region: meme que les buckets analysés

---

### 6c — Créer le(s) Workgroup(s) finops-s3
---
0. S'assurer d'être dans la région des buckets analysés
1. reproduire les étapes 6a et 6b avec nom du workgroup `finops-s3`

Query result location: `s3://athena-results-s3-[ACCOUNT-ID]-[region]/results/` 

En cas d'analyse multi-région, creer un workgroup par région

---

## Étape 8 — Configurer S3 Inventory

S3 Inventory génère des rapports CSV listant tous les objets de chaque bucket
(taille, storage class, date de modification, ETag, lifecycle…).
Utile pour détecter les buckets volumineux, les objets anciens sans lifecycle rule,
et les candidates au tiering Intelligent-Tiering.

>  créer 1 bucket destination par région.

---

### 8.1 — Créer les buckets destination de S3 Inventory

Pour chaque région, créer un bucket dédié à la réception des rapports CSV.

Deux options de nommage, les deux sont compatibles avec les policies IAM :

| Région | Account regional namespace *(recommandé)* | Global namespace |
|--------|-------------------------------------------|-----------------|
| eu-west-3 | `s3-inventory-[ACCOUNT-ID]-eu-west-3-an` | `s3-inventory-[ACCOUNT-ID]-eu-west-3` |
| eu-central-1 | `s3-inventory-[ACCOUNT-ID]-eu-central-1-an` | `s3-inventory-[ACCOUNT-ID]-eu-central-1` |

> ⚠️ Le bucket destination doit être dans la même région que le bucket source.
> "Block all public access" : ✅ activé. Versioning/encryption : défaut.

---

### 8.2 — Appliquer la bucket policy sur chaque destination

Coller la policy ci-dessous sur chaque bucket destination.
Remplacer `[ACCOUNT-ID]` et `[REGION]` avant de sauvegarder.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "InventoryPolicy",
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::s3-inventory-[ACCOUNT-ID]-[REGION]-an/*",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "[ACCOUNT-ID]",
                    "s3:x-amz-acl": "bucket-owner-full-control"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::*"
                }
            }
        }
    ]
}
```

> `"aws:SourceArn": "arn:aws:s3:::*"` autorise n'importe quel bucket du compte à écrire
> dans ce destination — : remplacement possible de `*` par l'ARN exact et ajouter un Statement par bucket supplémentaire.

---

### 8.3 — Créer les inventory configurations sur chaque bucket source

Via la console (le plus simple) :
**S3** → bucket concerné → onglet **Management** → **Inventory configurations** → **Create inventory configuration**

Paramètres recommandés :

| Champ | Valeur |
|-------|--------|
| Configuration name | `inventory-finops` |
| Scope | Entire bucket |
| Destination bucket | `s3-inventory-[ACCOUNT-ID]-[REGION]-an` (même compte, même région) |
| Frequency | **Weekly** — suffisant pour un audit |
| Output format | **CSV** |

Champs optionnels à cocher :
- **Size**
- **Last modified date**
- **Storage class**
- **Intelligent-Tiering: Access tier**
- **ETag**
- **Lifecycle expiration date**

> Premier rapport généré sous 48h après activation.
> Les rapports sont déposés sous le préfixe `[SOURCE-BUCKET]/inventory-finops/` dans le bucket destination.

---

### 8.4 — Prérequis IAM

Les permissions suivantes doivent être ajoutées :

```json
{
    "Sid": "S3InventoryCreateDestination",
    "Effect": "Allow",
    "Action": [
        "s3:CreateBucket",
        "s3:PutBucketPolicy"
    ],
    "Resource": "arn:aws:s3:::*s3-inventory*"
},
{
    "Sid": "S3InventoryConfigureSource",
    "Effect": "Allow",
    "Action": "s3:PutInventoryConfiguration",
    "Resource": "arn:aws:s3:::*"
}
```

> `s3:PutInventoryConfiguration` s'applique sur le bucket **source** (pas la destination).
> `s3:CreateBucket` est scopé sur les buckets contenant `s3-inventory` dans le nom.

---

### 8.5 — Activer le Server Access Logging sur chaque bucket source

Permet de tracer les accès aux objets et d'identifier le **last access** réel —
utile pour détecter les buckets inactifs et confirmer les quick wins.

**Bucket destination** (1 par région, à créer) :

| Région | Account regional namespace *(recommandé)* | Global namespace |
|--------|-------------------------------------------|-----------------|
| eu-west-3 | `s3-logging-[ACCOUNT-ID]-eu-west-3-an` | `s3-logging-[ACCOUNT-ID]-eu-west-3` |
| eu-central-1 | `s3-logging-[ACCOUNT-ID]-eu-central-1-an` | `s3-logging-[ACCOUNT-ID]-eu-central-1` |

**Permission IAM à ajouter:

```json
{
    "Sid": "S3ServerLogging",
    "Effect": "Allow",
    "Action": [
        "s3:PutBucketLogging",
        "s3:GetBucketLogging"
    ],
    "Resource": "arn:aws:s3:::*"
}
```

**Activation** : S3 → bucket source → onglet **Properties** → **Server access logging** → **Edit** → Enable → indiquer le bucket destination.
**Log object key format** : [DestinationPrefix][SourceAccountId]/​[SourceRegion]/​[SourceBucket]/​[YYYY]/​[MM]/​[DD]/​[YYYY]-[MM]-[DD]-[hh]-[mm]-[ss]-[UniqueString]

> La console ajoute automatiquement `s3:PutObject` sur le bucket destination via bucket policy — rien à faire manuellement.

---

## Annexe A1bis Catalogage Athena pour l'analayse S3 - access_logs

Query 1
```sql
CREATE DATABASE finops_s3;
```

Query 2 - partition projection
```sql
CREATE EXTERNAL TABLE finops_s3.access_logs (
  bucketowner STRING, bucket_name STRING, requestdatetime STRING,
  remoteip STRING, requester STRING, requestid STRING, operation STRING,
  key STRING, request_uri STRING, httpstatus STRING, errorcode STRING,
  bytessent BIGINT, objectsize BIGINT, totaltime STRING, turnaroundtime STRING,
  referrer STRING, useragent STRING, versionid STRING, hostid STRING,
  sigv STRING, ciphersuite STRING, authtype STRING, endpoint STRING,
  tlsversion STRING, accesspointarn STRING, aclrequired STRING,
  sourceregion STRING
)
PARTITIONED BY (year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
  'input.regex' = '([^ ]*) ([^ ]*) \\[(.*?)\\] ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (-|[0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (\"[^\"]*\"|-) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)'
)
STORED AS INPUTFORMAT 'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://[bucket-destination-logs]/[account-id]/eu-west-3/[bucket-source]/'           # Remplacer
TBLPROPERTIES (
  'projection.enabled' = 'true',
  'projection.year.type'  = 'integer', 'projection.year.range'  = '2026,2030', 'projection.year.digits'  = '4',
  'projection.month.type' = 'integer', 'projection.month.range' = '1,12',      'projection.month.digits' = '2',
  'projection.day.type'   = 'integer', 'projection.day.range'   = '1,31',      'projection.day.digits'   = '2',
  'storage.location.template' = 's3://[bucket-destination-logs]/[account-id]/eu-west-3/[bucket-source]/${year}/${month}/${day}/' # Remplacer
);
```

Query 3: verif
```sql
SELECT * FROM finops_s3.access_logs
WHERE year='2026' AND month='06' AND day='17'
LIMIT 10;
```

## Annexe A1 ter Catalogage Athena pour l'analyse S3 - inventory

Télécharge le manifest du dernier snapshot
Lis fileSchema — c'est la liste exacte des colonnes dans l'ordre
Adapte le DDL en conséquence
Ajuste projection.dt.range avec la vraie date du premier snapshot
Remplace les deux chemins S3 avec les valeurs du client

Query 1

```sql
CREATE EXTERNAL TABLE finops_s3.inventory (
  -- colonnes à adapter depuis fileSchema du manifest.json
  bucket STRING,
  key STRING,
  size BIGINT,
  last_modified_date STRING,
  etag STRING,
  storage_class STRING
  -- ajouter/supprimer selon fileSchema
)
PARTITIONED BY (dt STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
STORED AS INPUTFORMAT 'org.apache.hadoop.hive.ql.io.SymlinkTextInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://[BUCKET-DESTINATION]/[BUCKET-SOURCE]/[PREFIX-INVENTORY]/hive/'
TBLPROPERTIES (
  'projection.enabled' = 'true',
  'projection.dt.type' = 'date',
  'projection.dt.format' = 'yyyy-MM-dd-HH-mm',
  'projection.dt.range' = '[PREMIER-SNAPSHOT],NOW',
  'projection.dt.interval' = '1',
  'projection.dt.interval.unit' = 'DAYS',
  'storage.location.template' = 's3://[BUCKET-DESTINATION]/[BUCKET-SOURCE]/[PREFIX-INVENTORY]/hive/dt=${dt}/'
);
```

Les 3 variables à remplacer :

[BUCKET-DESTINATION] : bucket où atterrissent les inventories
[BUCKET-SOURCE] : bucket analysé
[PREFIX-INVENTORY] : préfixe configuré dans l'inventory config
[PREMIER-SNAPSHOT] : date du premier dossier dans hive/ format 2026-06-17-01-00


Query 2 test
```sql
SELECT * FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
LIMIT 10;
```

Query pour la suite
```sql
SELECT storage_class, COUNT(*) as nb_objets, 
       ROUND(SUM(size)/1024.0/1024.0, 2) as taille_mb
FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
GROUP BY storage_class;
```
