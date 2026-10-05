# CUR 2.0 + Athena — Guide pratique FinOps
*Juin 2026*

---

## 1. Pourquoi CUR + Athena plutôt que Cost Explorer ?

Cost Explorer est un outil de visualisation. Il agrège, filtre, et affiche des tendances. Il est indispensable pour avoir une vue d'ensemble rapide. Mais il a des limites structurelles :

- CE plafonne à 14 jours pour le resource-level daily, et n'affiche que
  les 5 000 ressources les plus coûteuses par service. Au-delà, AWS
  lui-même renvoie vers le CUR.
- CE expose des dimensions préfabriquées (Service, Usage Type, Resource,
  charge type). Il ne permet pas de croiser librement resource_id × tag ×
  usage_type dans une même requête. Le CUR + Athena, si.
- Le CUR donne accès à toutes les lignes, toute la profondeur d'historique,
  et n'importe quel croisement de colonnes en SQL.

**CUR + Athena = SQL sur les données brutes de facturation.** Tu peux descendre à la ligne individuelle, croiser n'importe quelle dimension, filtrer sur n'importe quelle colonne.

C'est la différence entre lire un tableau de bord et lire la base de données derrière.

---

## 2. Architecture du setup

```
AWS Billing
    └── Data Exports (CUR 2.0)
            └── S3 bucket (Parquet, 1 fichier/jour par mois)
                    └── AWS Glue Data Catalog (table externe)
                            └── Athena (moteur SQL Trino)
```

**Points critiques à retenir :**

- Le wizard Data Exports ne crée **pas** la table Glue. Il dépose un fichier `create-table.sql` dans S3. La création de la table est une étape manuelle séparée.
- CUR 2.0 = format **Parquet** (colonnaire). Les requêtes `COUNT(*)` lisent les métadonnées, pas les données → scan quasi nul, coût négligeable.
- Athena = moteur **Trino** (anciennement Presto). Pas de syntaxe Hive dans les SELECT. Exemple : `SHOW PARTITIONS` n'existe pas en Trino → erreur.
- Les colonnes de type map (`product`, `resource_tags`) s'accèdent avec `resource_tags['user_Env']`.

---

## 3. La partition projection — comprendre et vérifier

### Pourquoi c'est crucial

CUR est organisé en partitions par `billing_period` (format `YYYY-MM`). Sans partition chargée, aucune donnée n'est accessible. Deux approches existent :

| Approche | Mécanisme | Risque |
|---|---|---|
| `MSCK REPAIR TABLE` | Scanne S3 et écrit dans Glue | Double piège : silencieux si casse S3 majuscule (`BILLING_PERIOD=`) ou sans droits Glue write |
| **Partition projection** | Athena gère les partitions virtuellement via TBLPROPERTIES | Robuste, aucune dépendance Glue write |

**La partition projection est la solution recommandée.**

### TBLPROPERTIES à vérifier

```sql
SHOW CREATE TABLE nom_de_ta_table;
```

Tu dois voir :

```
'projection.enabled' = 'true'
'projection.billing_period.type' = 'date'
'projection.billing_period.format' = 'yyyy-MM'
'projection.billing_period.range' = '2025-12,NOW'
'storage.location.template' = 's3://bucket/.../BILLING_PERIOD=${billing_period}/'
```

- `type = 'date'` → Athena énumère automatiquement les mois dans la plage. Correct.
- `type = 'injected'` → tu devrais passer la valeur explicitement dans chaque requête. Moins pratique.
- Si `projection.enabled` absent → pas de projection, retour au risque MSCK.

### Filtre billing_period — toujours présent

```sql
WHERE billing_period = '2026-06'           -- 1 mois exact
WHERE billing_period BETWEEN '2025-12' AND '2026-05'   -- plage multi-mois
```

Mettre un prédicat sur billing_period dans le WHERE active le partition
pruning : Athena élague les partitions avant d'ouvrir les fichiers Parquet.
L'ordre des conditions dans le WHERE n'a aucun effet (l'optimiseur Trino
réordonne). Ce qui compte : que le prédicat soit là, et qu'il porte
directement sur la colonne (pas de fonction enveloppante).

Sans aucun filtre billing_period, Athena scanne toute la plage de projection.

---

## 4. Les requêtes clés — séquence d'audit

### Q1 — Sanity check

*Objectif : confirmer que les données sont là et la plage temporelle.*

```sql
SELECT COUNT(*) AS nb_lignes,
       MIN(line_item_usage_start_date) AS debut,
       MAX(line_item_usage_start_date) AS fin,
       COUNT(DISTINCT line_item_resource_id) AS nb_ressources
FROM finops_cur
WHERE billing_period = '2026-06';
```

Si le résultat est 0 → problème de partition ou de fichier Parquet pas encore arrivé (délai T+24h à T+48h après minuit UTC).

---

### Q2 — Coût par service et type de ligne

*Objectif : reproduire la vue CE, mais avec séparation Usage / Credit / Tax.*

```sql
SELECT line_item_product_code,
       line_item_line_item_type,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
GROUP BY 1, 2
ORDER BY cout_usd DESC;
```

**`GROUP BY 1, 2`** = raccourci numérique référençant les positions dans le SELECT. Équivalent de `GROUP BY line_item_product_code, line_item_line_item_type`.

**Ce que tu cherches ici :**
- Les lignes `Credit` qui compensent exactement les lignes `Usage` → crédits actifs, le vrai spend est masqué. Pour voir le spend brut, ajouter `AND line_item_line_item_type = 'Usage'`.
- Un `AmazonVPC` significatif → NAT Gateway probable.
- Un `AmazonEC2` dominant → instances à analyser en Q3.

**Piège NAT Gateway :** ses coûts sont ventilés sur **deux** product_code dans Q2 :
- `AmazonVPC` → frais horaires + data processing
- `AmazonEC2` → data transfer egress internet

Q2 les montre séparément. Q3 les agrège sur le même ARN. C'est pourquoi le coût Q3 d'un NAT est supérieur à ce que Q2 montre sous `AmazonVPC`.

---

### Q2bis — Coût par service et par mois (cartographie multi-mois)

*Objectif : sortir la tendance service × mois sur la période d'audit. 

```sql
SELECT line_item_product_code,
       billing_period,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period BETWEEN '2026-01' AND '2026-06'
  AND line_item_line_item_type = 'Usage'
GROUP BY 1, 2
ORDER BY 1, 2;
```

**Différence avec Q2 :** Q2 est mono-mois et sert au snapshot d'une période donnée. Q2bis ajoute `billing_period` au GROUP BY pour obtenir une ligne par service et par mois. C'est cette sortie qui révèle la nature fixe ou variable de chaque poste : un coût plat mois après mois = fixe, un coût qui varie avec l'activité = variable.

**Lecture :**
- Service à coût constant sur les 6 mois → coût fixe (NAT, RDS réservé, support, baseline compute).
- Service en dents de scie ou en tendance → coût variable (Textract, data transfer, Lambda, S3 en croissance).
- Service qui apparaît en cours de période → ressource créée récemment, à investiguer.

**Note `line_item_line_item_type = 'Usage'` :** exclut crédits et taxes pour ne garder que le spend brut. Pour voir l'effet des crédits sur la tendance, retirer ce filtre et ajouter `line_item_line_item_type` au GROUP BY.

### Q3 — Coût par resource_id ← valeur ajoutée principale

*Objectif : identifier chaque ressource individuelle et son coût réel.*
Mono-mois ou élargir le WHERE à multi mois pour le coût agrégé par resource_id sur une période de plusieurs mois

```sql
SELECT line_item_resource_id,
       line_item_product_code,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND line_item_resource_id != ''
GROUP BY 1, 2
ORDER BY cout_usd DESC
LIMIT 50;
```

**Pourquoi `resource_id != ''`** : les taxes, frais de support, et certains crédits ont un resource_id vide (chaîne vide, pas NULL). Ces lignes ne correspondent à aucune ressource identifiable. On les exclut.

coût semestriel par ressource
```sql
WHERE billing_period BETWEEN '2026-01' AND '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND line_item_resource_id != ''
```

**Ce que tu vois ici que CE ne montre pas :**
- Quel NAT Gateway précis (`arn:aws:ec2:...:natgateway/nat-xxx`)
- Quelle instance EC2 individuelle (`i-0xxxxxxx`)
- Quels volumes EBS détachés (`vol-xxxxxxx`)
- Quelles EIP candidates orphelines (`eipalloc-xxxxxxx`)

Pour décomposer le coût d'une ressource spécifique :

```sql
SELECT line_item_usage_type,
       line_item_operation,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_resource_id = 'COLLE_RESOURCE_ID_ICI'
GROUP BY 1, 2;
```



---

### Q4 — Ressources non taguées avec coût

*Objectif : mesurer la couverture de tagging et identifier les ressources sans attribution.*

**Étape préalable — découvrir les clés de tags actives dans CUR :**

```sql
SELECT DISTINCT map_keys(resource_tags) AS cles_tags
FROM finops_cur
WHERE billing_period = '2026-06'
  AND cardinality(resource_tags) > 0
LIMIT 20;
```

Si cette query retourne vide → les cost allocation tags ne sont pas activés dans Billing console. Aucune attribution n'est possible.

**Requête principale :**

```sql
SELECT line_item_resource_id,
       line_item_product_code,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND (resource_tags['user_Env'] IS NULL OR resource_tags['user_Env'] = '')
GROUP BY 1, 2
HAVING SUM(line_item_unblended_cost) > 0
ORDER BY cout_usd DESC;
```

**Remplace `user_Env`** par les vraies clés découvertes à l'étape précédente. CUR préfixe les clés avec `user_` → tag `Env` devient `resource_tags['user_Env']`. La casse est stricte.

**Pièges tags fréquents chez les petites équipes :**
- Clé créée, valeur absente → `resource_tags` vide dans CUR, comme si pas de tag
- Cost allocation tags non activés → toutes les lignes `resource_tags` vides
- Activation des cost allocation tags → AWS fait un backfill partiel : l'activation d'un tag s'applique rétroactivement jusqu'à la date où le tag a été physiquement posé sur la ressource. comble le gap entre tagging physique et activation ; les coûts antérieurs au tagging restent inattribuables.

---

### Q5 — Data transfer détaillé

*Objectif : décomposer les coûts de transfer et identifier NAT inactif, egress internet, inter-AZ.*

```sql
SELECT line_item_usage_type,
       line_item_operation,
       pricing_unit,
       ROUND(SUM(line_item_usage_amount), 4) AS quantite,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND (line_item_usage_type LIKE '%DataTransfer%'
       OR line_item_usage_type LIKE '%Bytes%'
       OR line_item_usage_type LIKE '%NatGateway%')
  AND line_item_unblended_cost > 0.001
GROUP BY 1, 2, 3
ORDER BY cout_usd DESC;
```

**Décodage des usage_type :**
- `EUW3-NatGateway-Hours` → frais horaires NAT (tick fixe, indépendant du trafic)
- `EUW3-NatGateway-Bytes` → data processing NAT (facturation au GB traité)
- `EUW3-DataTransfer-Out-Bytes` → egress internet depuis eu-west-3
- `EUW3-EUC1-AWS-*` → transfer inter-région (EUW3 → Frankfurt, etc.)
- `DataTransfer-Regional-Bytes` → inter-AZ dans la même région

**Signal quick win :** `NatGateway-Hours` avec coût significatif + `NatGateway-Bytes` à $0 → NAT Gateway qui tourne sans traiter de trafic. Suppression = économie immédiate.

**Le bruit USE1-* (Virginia) :** appels API globaux S3, CloudFront, Cost Explorer. Ces services ont des endpoints us-east-1 même depuis eu-west-3. Normal, ignorer.

---

### Q6 — Candidats orphelins (stockage et IP facturés)

*Objectif : pré-cibler les ressources à coût récurrent qui sont probablement inutilisées. EBS détachés, EIP non attachées, snapshots accumulés.*

```sql
SELECT line_item_resource_id,
       line_item_usage_type,
       ROUND(SUM(line_item_usage_amount), 4) AS quantite,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND (line_item_usage_type LIKE '%EBS:Volume%'
       OR line_item_usage_type LIKE '%ElasticIP%'
       OR line_item_usage_type LIKE '%Snapshot%')
GROUP BY 1, 2, 3
ORDER BY cout_usd DESC;
```

**Limite importante : le CUR voit le coût, pas l'état d'attachement.** Cette requête sort des *candidats*, pas une preuve d'orphelinat. Un EBS facturé peut être attaché à une instance arrêtée et toujours utile. La confirmation se fait côté API, pas dans le CUR :
- EBS : `aws ec2 describe-volumes --filters Name=status,Values=available` → seuls les volumes `available` sont réellement détachés.
- EIP : `aws ec2 describe-addresses` → une EIP sans `AssociationId` est non attachée.
- Snapshots : croiser avec les AMI et volumes existants pour repérer ceux qui ne servent plus aucune restauration.

**Signal EIP fort :** une EIP attachée à une instance *running* est gratuite. Si elle apparaît ici avec un coût, c'est qu'elle est non attachée ou attachée à une ressource arrêtée. Candidat quick win quasi certain. Attention au piège déjà noté : une EIP sur NAT Gateway n'a pas d'AssociationId mais n'est pas orpheline pour autant, vérifier avant de conclure.

**Méthode :** Q6 produit la liste de candidats classés par coût. Pour chacun au-dessus d'un seuil pertinent, confirmer l'état réel par API avant de l'inscrire en quick win. Ne jamais recommander une suppression sur la seule base du CUR.

### Q7 — Engagements existants (Savings Plans / Reserved Instances)

*Objectif : constater les engagements déjà en place et leur usage.*

```sql
SELECT line_item_line_item_type,
       line_item_product_code,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type IN (
        'SavingsPlanCoveredUsage',
        'SavingsPlanNegation',
        'SavingsPlanUpfrontFee',
        'SavingsPlanRecurringFee',
        'DiscountedUsage',
        'RIFee',
        'Fee')
GROUP BY 1, 2
ORDER BY cout_usd DESC;
```

**Ce que la requête mesure : l'existant, pas la recommandation.** Le CUR montre les engagements en cours et l'usage qu'ils couvrent. Il ne dit pas ce qu'il faudrait acheter. La recommandation d'achat (quel SP, quelle couverture cible) vient de Cost Optimization Hub ou Cost Explorer, jamais du CUR.

**Décodage des line_item_type :**
- `SavingsPlanCoveredUsage` → usage couvert par un SP actif (coût au tarif SP).
- `SavingsPlanNegation` → ligne négative qui annule le coût on-demand correspondant.
- `SavingsPlanUpfrontFee` / `SavingsPlanRecurringFee` → coût d'achat du SP (upfront ou mensuel).
- `DiscountedUsage` → usage couvert par une RI.
- `RIFee` → frais récurrent d'une RI.
- `Fee` → frais divers, à inspecter au cas par cas.

**Résultat vide = constat à part entière.** Si la requête ne retourne rien, aucun engagement n'est en place : tout le compute tourne en on-demand.


### Q8 — Ventilation d'un service par usage_type

*Objectif : décomposer un poste de coût en sous-composants pour le rendre actionnable. Transforme un service cher (Textract, RDS) en quick win précis.*

```sql
SELECT line_item_usage_type,
       line_item_operation,
       ROUND(SUM(line_item_usage_amount), 4) AS quantite,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND line_item_product_code = 'AmazonTextract'
GROUP BY 1, 2
ORDER BY cout_usd DESC;
```

**Différence avec Q3 :** Q3 décompose par ressource individuelle (resource_id). Q8 décompose un service par nature d'usage (usage_type × operation). Q3 répond "quelle ressource coûte", Q8 répond "quel type d'appel ou de composant coûte dans ce service".

**Remplace `AmazonTextract`** par le product_code du service à investiguer, repéré en Q2. Cibles probables : `AmazonTextract`, `AmazonRDS`, `AmazonCloudWatch`.

**Textract — le quick win caché :** cette ventilation révèle la répartition entre les deux API. `AnalyzeDocument` coûte environ 33x plus cher que `DetectDocumentText` (~50 USD vs ~1,50 USD pour 1 000 pages). Si `AnalyzeDocument` domine alors que de l'extraction de texte simple suffirait, c'est un quick win majeur. Vérifier aussi l'absence de cache : retraiter le même document = coût pur répété.

**RDS :** la ventilation sépare instance (`InstanceUsage`), stockage (`StorageUsage`), IO, backup, et Multi-AZ. Permet de cibler le rightsizing ou de questionner l'utilité du Multi-AZ si la charge est faible.

**CloudWatch :** sépare ingestion de logs, stockage de logs, métriques custom, et dashboards. Les log groups sans politique de rétention gonflent le stockage. Quick win classique : appliquer une rétention.

## 5. Filtres temporels

**Sur un mois exact :**
```sql
WHERE billing_period = '2026-06'
```

**Sur des jours précis dans un mois :**
```sql
WHERE billing_period = '2026-06'
  AND line_item_usage_start_date >= TIMESTAMP '2026-06-01 00:00:00'
  AND line_item_usage_start_date < TIMESTAMP '2026-06-08 00:00:00'
```

**Sur plusieurs mois :**

```sql
WHERE billing_period BETWEEN '2026-01' AND '2026-06'
```
ou

```sql
WHERE billing_period BETWEEN '2026-01' AND '2026-06'
  AND line_item_usage_start_date >= TIMESTAMP '2026-01-01 00:00:00'
  AND line_item_usage_start_date < TIMESTAMP '2026-07-01 00:00:00'
```

**Analyse weekend / nuit (quick win stop/start) :**

*Pattern hebdomadaire (weekend vs semaine) :*
*BoxUsage = heures d'instance on-demand : ce qui disparait quand on eteint.*
*Tri par cout pour reperer vite les jours les plus chers.*
```sql
SELECT DATE_FORMAT(line_item_usage_start_date, '%W') AS jour,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND line_item_product_code = 'AmazonEC2'
  AND line_item_usage_type LIKE '%BoxUsage%'
GROUP BY 1
ORDER BY 2 DESC;
```

*Pattern horaire (jour vs nuit) :*
*ORDER BY 1 volontaire : tri par heure croissante (0h -> 23h) pour lire la courbe, pas par cout.*
```sql
SELECT HOUR(line_item_usage_start_date) AS heure,
       ROUND(SUM(line_item_unblended_cost), 4) AS cout_usd
FROM finops_cur
WHERE billing_period = '2026-06'
  AND line_item_line_item_type = 'Usage'
  AND line_item_product_code = 'AmazonEC2'
  AND line_item_usage_type LIKE '%BoxUsage%'
GROUP BY 1
ORDER BY 1;
```

Si le coût EC2 dev/staging est constant du lundi au dimanche → elles tournent 24/7. Règle empirique : stop/start 8h/jour 5j/7 = ~75% d'économie sur le compute on-demand de ces instances.

> ATTENTION interpretation : BoxUsage couvre l'usage on-demand. Si les instances sont couvertes par un Savings Plan ou une RI, le cout BoxUsage peut etre reduit ou bascule sous un autre line_item_type, et le pattern jour/nuit sera fausse. Verifier d'abord en Q2 la presence de lignes SavingsPlan* / Reservation avant d'interpreter ces courbes.

---

## 6. Enseignements terrain — pièges à ne pas répéter

| Piège | Ce qui se passe | Solution |
|---|---|---|
| `SHOW PARTITIONS` en Athena | Erreur syntaxe — c'est du Hive, Athena = Trino | Utiliser `SHOW CREATE TABLE` pour vérifier la projection |
| `MSCK REPAIR TABLE` | Silencieux si S3 en majuscules (`BILLING_PERIOD=`) ou sans droits Glue | Toujours utiliser la partition projection |
| Tags sans valeur | `resource_tags` vide dans CUR = impossible à filtrer | Vérifier clé + valeur en EC2 console avant d'écrire Q4 |
| Cost allocation tags non activés | `map_keys(resource_tags)` retourne vide pour toutes les ressources | Activer dans Billing console → effet T+24h uniquement a partir de la date ou le tag a été physiquement posé sur la resource|
| `ROUND(,4)` masque les petits coûts | Des lignes à $0.000001 passent le filtre `> 0` et polluent les résultats | Utiliser `> 0.001` comme seuil minimal |
| NAT Gateway split product_code | Q2 montre VPC + EC2 séparément, Q3 agrège sur la ressource ID | Toujours utiliser Q3 pour le coût total d'une ressource |
| Backticks vs guillemets Athena | Backticks = DDL Hive, guillemets doubles = SELECT Trino | Ne pas mélanger les deux dans la même requête |

---

## 7. Checklist avant d'attaquer le CUR

Avant d'écrire la première query :

- [ ] `SHOW CREATE TABLE` → vérifier que `projection.enabled = true`
- [ ] Q1 sanity check → confirmer nb_lignes > 0 et plage de dates cohérente
- [ ] `SELECT DISTINCT map_keys(resource_tags)` → inventorier les clés de tags actives
- [ ] Q2 → identifier les top services, repérer les crédits actifs
- [ ] Q3 → descendre au niveau ressource, noter les Resource ID / ARN suspects
- [ ] Requête de décomposition sur chaque ressource > $20/mois
- [ ] Q4 → mesurer couverture tagging (avec les vraies clés découvertes)
- [ ] Q5 → data transfer, repérer NAT-Hours sans NAT-Bytes

**Si `map_keys` retourne vide :** documenter comme limitation. L'attribution par environnement ou par client sera impossible sans activation des cost allocation tags + valeurs renseignées.

---

## 8. Pratique Athena — organisation de session

- **10 onglets max** dans l'éditeur → gérer activement
- Nommer chaque onglet dès l'ouverture (double-clic) : `Q1-sanity`, `Q2-services`, `Q3-resources`, etc.
- `Save as` sauvegarde le **texte** de la requête dans "Saved queries". Pas les résultats.
- `Download results` sauvegarde les résultats en CSV. Le fichier existe déjà dans S3 — pas de coût scan supplémentaire.
- En audit client : exporter les résultats clés en CSV à chaque session. Si le client modifie l'infra entre deux sessions, les données changent et tu perds la photo à l'instant T.
- Convention de nommage des fichiers .csv: {client}_{YYYY-MM}_{Qx-sujet}_{date-extraction}.csv
example: client_2026-01_2026-06_Q2-services_2026-07-02.csv
- L'historique d'exécution ("Recent queries") est conservé 45 jours.

---
