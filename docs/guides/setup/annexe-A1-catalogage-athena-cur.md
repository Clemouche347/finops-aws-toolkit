## Annexe A1 — Catalogage Athena (CREATE DATABASE + CREATE TABLE)

> Cette étape est nécessaire pour pouvoir requêter le CUR avec Athena.
> Elle peut être faite par le client, ou par l'auditeur si une policy Glue write temporaire est accordée.

---

### Étape A — La table n'existe pas (normal)

Avec CUR 2.0 / Data Exports, la table Athena **n'est jamais créée automatiquement**,
même avec "Amazon Athena integration" cochée. Cette option dépose seulement les outils
de catalogage (`create-table.sql`, `crawler-cfn.yml`) dans le bucket S3, à côté des données.
Le catalogage manuel ci-dessous est donc systématique — ce n'est pas un bug.

Vérification rapide dans Athena (workgroup `finops-cur`, région `us-east-1`) :

```sql
SHOW TABLES IN finops_cur;
```

> `SHOW TABLES` est une lecture — le user `finops-auditor` en ReadOnly peut l'exécuter
> sans la policy Glue write temporaire. Cette policy n'est
> nécessaire qu'à partir de l'étape B (CREATE DATABASE / CREATE TABLE).

Si vide (cas normal) → continuer avec les étapes A bis, B et C.
Si une table apparaît (catalogage déjà fait par le passé) → passer directement à l'étape D.

---

### Étape A bis — Vérifier le vrai chemin S3 des données

⚠️ **Indispensable avant l'étape C.** Le chemin exact n'est pas devinable — il dépend
du préfixe choisi + du nom de l'export, et AWS ajoute un niveau `data/`. Lister la racine
du bucket en CLI pour voir le vrai chemin :

```bash
aws s3 ls s3://cur-exports-[ACCOUNT-ID]/ --recursive | head -30
```

Le chemin réel ressemblera à :
`s3://cur-exports-[ACCOUNT-ID]/cur/finops_cur/data/BILLING_PERIOD=2026-05/...`

C'est-à-dire : `bucket / prefix / NOM-DE-L-EXPORT / data / BILLING_PERIOD=AAAA-MM /`
Le nom de l'export est répété dans le chemin — noter le chemin exact jusqu'à `data/`
(inclus, sans le `BILLING_PERIOD=`), il sera réutilisé à l'étape C dans le `LOCATION`.

---

### Étape B — Créer la database

Dans Athena (workgroup `finops-cur`, région `us-east-1`) :

```sql
CREATE DATABASE IF NOT EXISTS finops_cur;
```

> Nom en underscores → aucun quoting nécessaire, ni en DDL ni en SELECT.
> ⚠️ Si un nom à **tirets** était utilisé, il faudrait le quoter partout — et la syntaxe
> diffère selon le moteur : backticks `` `nom-a-tirets` `` en DDL (Hive), mais guillemets
> doubles `"nom-a-tirets"` en SELECT (Trino). Mélanger les deux échoue. D'où le choix des underscores.

---

### Étape C — Créer la table externe

> ✅ **Méthode recommandée : utiliser le `create-table.sql` généré par AWS.**
> AWS dépose un `create-table.sql` complet dans le bucket S3, sous
> `.../[export-name]/metadata/BILLING_PERIOD=AAAA-MM/[export-name]-create-table.sql`.
> Ce fichier contient le **schéma exact** du CUR (≈120 colonnes, avec les `MAP` de tags
> et les noms générés par AWS). C'est la seule source fiable — ne pas retaper le schéma à la main.
>
> Le récupérer et l'ouvrir :
> ```bash
> aws s3 cp s3://cur-exports-[ACCOUNT-ID]/cur/finops_cur/metadata/BILLING_PERIOD=2026-06/finops_cur-create-table.sql /tmp/ref.sql
> cat /tmp/ref.sql
> ```
> (adapter le chemin et le mois à ce qui a été repéré à l'étape A bis)

Le fichier généré par AWS contient le schéma complet, le `PARTITIONED BY (BILLING_PERIOD STRING)`
et le `LOCATION` — mais **pas** la partition projection. Sans projection, il faudrait recharger
les partitions chaque mois (`MSCK` / `ALTER TABLE`), avec le piège de casse `BILLING_PERIOD`.
**Ajouter manuellement le bloc `TBLPROPERTIES` de projection** (voir ci-dessous) avant d'exécuter
le `CREATE TABLE` — c'est ce qui évite toute corvée mensuelle.

Avant d'exécuter dans Athena, quatre choses à faire sur le SQL généré :

1. **Nom database.table** — puisque l'export est nommé `finops_cur` (underscores),
   la database et la table générées le sont aussi : `finops_cur.finops_cur`.
   Aucun quoting nécessaire, rien à renommer.
2. **Ajouter le bloc `TBLPROPERTIES` de partition projection** (absent du fichier généré) —
   voir le bloc ci-dessous.
3. **`projection.billing_period.range`** — ajuster la date de début (ex. `2025-12,NOW`)
   à la date réelle du premier mois de données.
4. **`LOCATION` et `storage.location.template`** — utiliser le vrai chemin `data/` repéré
   à l'étape A bis, avec `BILLING_PERIOD=` en majuscules dans le template.

À titre de référence, voici la structure d'un `create-table.sql` réel (schéma abrégé —
le vrai en contient ~120) :

```sql
CREATE EXTERNAL TABLE finops_cur.finops_cur (
  bill_bill_type STRING,
  bill_billing_entity STRING,
  bill_billing_period_end_date TIMESTAMP,
  bill_billing_period_start_date TIMESTAMP,
  bill_payer_account_id STRING,
  cost_category MAP<STRING,STRING>,
  identity_line_item_id STRING,
  identity_time_interval STRING,
  line_item_availability_zone STRING,
  line_item_line_item_type STRING,
  line_item_product_code STRING,
  line_item_resource_id STRING,
  line_item_unblended_cost DOUBLE,
  line_item_usage_account_id STRING,
  line_item_usage_amount DOUBLE,
  line_item_usage_start_date TIMESTAMP,
  line_item_usage_end_date TIMESTAMP,
  line_item_usage_type STRING,
  pricing_public_on_demand_cost DOUBLE,
  pricing_term STRING,
  pricing_unit STRING,
  product MAP<STRING,STRING>,
  product_instance_type STRING,
  product_region_code STRING,
  product_servicecode STRING,
  reservation_effective_cost DOUBLE,
  reservation_reservation_a_r_n STRING,
  resource_tags MAP<STRING,STRING>,
  savings_plan_savings_plan_a_r_n STRING,
  savings_plan_savings_plan_effective_cost DOUBLE,
  savings_plan_used_commitment DOUBLE,
  tags MAP<STRING,STRING>
  -- ... ~90 colonnes supplémentaires dans le fichier réel
)
PARTITIONED BY (BILLING_PERIOD STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
WITH SERDEPROPERTIES ('serialization.format' = '1')
LOCATION 's3://cur-exports-[ACCOUNT-ID]/cur/finops_cur/data/'
-- bloc TBLPROPERTIES ci-dessous = AJOUT MANUEL (absent du create-table.sql généré par AWS)
TBLPROPERTIES (
  'projection.enabled' = 'true',
  'projection.billing_period.type' = 'date',
  'projection.billing_period.range' = '2025-12,NOW',
  'projection.billing_period.format' = 'yyyy-MM',
  'projection.billing_period.interval' = '1',
  'projection.billing_period.interval.unit' = 'MONTHS',
  'storage.location.template' = 's3://cur-exports-[ACCOUNT-ID]/cur/finops_cur/data/BILLING_PERIOD=${billing_period}/'
);
```

> Le schéma (colonnes) + `PARTITIONED BY` + `LOCATION` viennent du fichier généré par AWS.
> Le bloc `TBLPROPERTIES` est l'ajout manuel qui active la partition projection.

> ⚠️ **Points qui surprennent dans le schéma réel AWS** (ne pas "corriger") :
> - La colonne de partition est `BILLING_PERIOD` en **MAJUSCULES** dans `PARTITIONED BY`,
>   mais `${billing_period}` en minuscules dans `storage.location.template`. Les deux coexistent, c'est normal.
> - Les ARN sont nommés `reservation_reservation_a_r_n` / `savings_plan_savings_plan_a_r_n`
>   (underscores entre les lettres de "ARN") — c'est la conversion automatique d'AWS.
> - Les tags sont des colonnes `MAP<STRING,STRING>` (`resource_tags`, `tags`, `cost_category`, `product`).
>   On les requête avec la syntaxe `resource_tags['nom_du_tag']`.
> - Pas de `STORED AS INPUTFORMAT/OUTPUTFORMAT` : AWS utilise `WITH SERDEPROPERTIES` à la place. Les deux marchent.

---

### Étape D — Vérifier que ça fonctionne

```sql
SELECT bill_payer_account_id, line_item_product_code,
       SUM(line_item_unblended_cost) AS total_cost
FROM finops_cur.finops_cur
WHERE billing_period = '2026-04'
GROUP BY 1, 2
ORDER BY total_cost DESC
LIMIT 20;
```

> ⚠️ Remplacer `2026-04` par un mois dont les données existent (voir les dossiers de l'étape A bis).
> Le filtre `billing_period` (minuscules) fonctionne même si la colonne est déclarée
> `BILLING_PERIOD` en majuscules — les noms de colonnes Athena sont insensibles à la casse.

Si la requête retourne des résultats → catalogage OK, mission peut démarrer.

> **Rappel partition projection** : grâce aux `TBLPROPERTIES` de l'étape C, Athena
> calcule les partitions automatiquement. Plus jamais besoin de `MSCK REPAIR TABLE`
> ni d'`ALTER TABLE ADD PARTITION` à chaque nouveau mois.
> Ne **pas** utiliser `MSCK REPAIR TABLE` : il échoue silencieusement sur les préfixes
> en majuscules (`BILLING_PERIOD=`) et peut renvoyer un faux succès sans rien charger.


---