# Setup AWS pour audit FinOps
Juin 2026  
*Actions one-shot à faire avant le démarrage de la mission*

---
## Résumé des actions

| # | Action | Durée | Qui |
|---|--------|-------|-----|
| 0 | Activer l'accès IAM aux données de facturation (Annexe A) | 2 min | account admin |
| 1 | Créer policies + IAM user (Annexe A) | 15 min | account admin |
| 2 | Créer le bucket S3 pour Athena results | 3 min | finops admin |
| 3 | Activer CUR 2.0 (Data Exports) — le wizard crée le bucket S3 CUR | 10 min | finops admin |
| 4 | Activer AWS Resource Explorer | 5 min | finops admin |
| 5 | Activer Compute Optimizer & look back 32 jours + Cost Optimization Hub | 5 min | finops admin |
| 6 | Créer workgroup Athena + garde-fou | 10 min | finops admin |
| 7 | Soumettre ticket backfill 24 mois | 5 min | finops admin |
| 8 | Setup S3 Inventory → voir finops-setup-s3-observability.md | 20 min | finops admin |
| 9 | Activer les Cost allocation tags | 10 min | finops admin |
| 10 | Configurer les Lifecycle rules sur les buckets d'audit | 5 min | finops admin |
| A1 | Catalogage Athena CUR → annexe-A1-catalogage-athena.md | 15 min | finops admin |
| A2 | Installer CloudWatch Agent → annexe-A2-cloudwatch-agent.md | 10 min | finops admin |
| A3 | Transmettre credentials (Annexe A §1.3) | — | account admin |

> ⚠️ Si certaines de ces actions ont déjà été effectuées, vérifier dans les étapes ci-dessous la configuration

---

## Etape 0 & Etape 1 - refer to Annexe A
Étape 0 — Prérequis : accès IAM aux données de facturation
Étape 1 — Créer les policies et l'utilisateur IAM finops

---

## Étape 2 — Créer le bucket S3 pour les résultats Athena du cur

> Le bucket CUR sera créé automatiquement par le wizard à l'étape 3.
> Seul ce bucket doit être créé manuellement maintenant.

1. Console AWS → **S3** → **Create bucket**
2. AWS Region : **`us-east-1`** ⚠️ obligatoire
3. **Namespace** — deux options, les deux sont compatibles avec les policies IAM :
   - **Account regional namespace** *(recommandé)* : saisir le préfixe **`athena-results-cur`** —
     AWS ajoute automatiquement le suffixe `-[ACCOUNT-ID]-us-east-1-an`.
     Nom final : `athena-results-cur-[ACCOUNT-ID]-us-east-1-an`
   - **Global namespace** : saisir **`athena-results-cur-[ACCOUNT-ID]`** manuellement
     (l'account ID garantit l'unicité globale)
4. "Block all public access" : ✅ activé (par défaut, ne pas toucher)
5. Versioning, encryption, tags : laisser par défaut
6. **Create bucket**
7. 📝 **Noter le nom exact du bucket créé** — il sera réutilisé au workgroup Athena (étape 6)

> Les policies IAM utilisent des wildcards par préfixe (`arn:aws:s3:::athena-results*`) :
> elles matchent les deux options, le suffixe étant ajouté à la fin du nom.

---

> → Analyses S3 : voir [finops-setup-s3-observability.md](finops-setup-s3-observability.md)

## Étape 3 — Activer CUR 2.0 (Data Exports)

Le wizard crée le bucket CUR et applique sa policy automatiquement.

1. Console AWS → **Billing and Cost Management**
   *(chercher "Billing" dans la barre de recherche, ou menu compte en haut à droite)*
2. Menu gauche → **Data Exports**
3. **Create export**

### Remplir l'export comme suit :

| Champ | Valeur |
|-------|--------|
| Export type | **Standard data export** |
| Export name | `finops_cur` |
| Data table | **CUR 2.0** |
| Time granularity | **Hourly** — voir note ci-dessous |
| Include resource IDs | ✅ cocher |
| Split cost allocation data | ✅ cocher |
| File format | **Parquet** |
| File versioning | **Create new export file** *(ne pas choisir Overwrite)* |

> 💡 **Nom d'export en underscores** (`finops_cur`, pas de tirets) : la database et la table
> Glue héritent de ce nom. Avec des underscores, aucune requête SQL n'aura besoin de backticks
> ni de guillemets. Un nom à tirets forcerait `` `database-name` `` (DDL) ou `"database-name"` (SELECT)
> partout — autant l'éviter dès le départ.

> 💡 **Pourquoi Hourly** : le CUR lui-même est gratuit, seul le stockage S3 est facturé
> (Parquet, négligeable à cette échelle). Hourly permet de tracer les courbes de charge
> horaires (activité nocturne, dev/staging 24/7, dimensionnement Savings Plans).
> La granularité est figée à la création de l'export — la changer ensuite = recréer
> l'export + nouveau ticket backfill. Daily ne ferait économiser presque rien et fermerait l'option.

### Configuration du bucket S3 (Data export storage settings)

- Choisir **"This account"**
- Sélectionner **"Create a new S3 bucket"** (ou un bucket existant)
- Bucket name : préfixe **`cur-exports`**
  - Si le wizard propose le choix de namespace (pas dispo en Juin 2026) : **Account regional namespace** (recommandé) →
    nom final `cur-exports-[ACCOUNT-ID]-us-east-1-an`
  - Sinon (global namespace) : saisir `cur-exports-[ACCOUNT-ID]`
  - Alternative : créer le bucket d'abord dans S3 (comme à l'étape 2) puis le sélectionner
    comme bucket existant dans le wizard
- Region : **`us-east-1`** ⚠️ obligatoire pour Athena
- 📝 **Noter le nom exact du bucket** — réutilisé au ticket backfill (étape 7) et au catalogage (annexe 1)
- Le wizard affiche la bucket policy qu'il va appliquer — la vérifier et confirmer

La policy appliquée par le wizard est la suivante (référence, ne pas modifier) :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableAWSDataExportsToWriteToS3AndCheckPolicy",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "bcm-data-exports.amazonaws.com",
          "billingreports.amazonaws.com"
        ]
      },
      "Action": [
        "s3:PutObject",
        "s3:GetBucketPolicy"
      ],
      "Resource": [
        "arn:aws:s3:::cur-exports-[ACCOUNT-ID]",
        "arn:aws:s3:::cur-exports-[ACCOUNT-ID]/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:SourceAccount": "[ACCOUNT-ID]",
          "aws:SourceArn": [
            "arn:aws:cur:us-east-1:[ACCOUNT-ID]:definition/*",
            "arn:aws:bcm-data-exports:us-east-1:[ACCOUNT-ID]:export/*"
          ]
        }
      }
    }
  ]
}
```

### Finaliser l'export

| Champ | Valeur |
|-------|--------|
| S3 path prefix | `cur/` |
| Amazon Athena integration | ✅ Enable |

- Cocher **"I have confirmed that this policy is correct"** → **Save**
- **Create export**

> **Délai** : premier fichier dans le bucket sous 24h.
> ⚠️ La table Glue n'est **PAS** créée automatiquement. L'option "Athena integration" dépose
> seulement les outils de catalogage (`create-table.sql`, `crawler-cfn.yml`) dans le bucket S3.
> Le CREATE DATABASE / CREATE TABLE reste à faire manuellement dans Athena — voir l'annexe 1.

---

## Étape 4 — Activer AWS Resource Explorer

Resource Explorer permet de rechercher et lister toutes les ressources AWS
(EC2, RDS, Lambda, S3, EBS, etc.) dans toutes les régions en une seule vue.
Utile pour l'inventaire des ressources orphelines (livrable 2).

> Si déjà activé sur le compte, passer directement à l'étape 5 — ReadOnlyAccess suffit pour chercher.

1. Console AWS → chercher **"Resource Explorer"** dans la barre de recherche
2. Cliquer **"Turn on Resource Explorer"**
3. Choisir **"Quick setup"** *(recommandé)*
   - Crée automatiquement des index locaux dans toutes les régions
   - Crée un aggregator index dans la région choisie (choisir `eu-west-3` ou `us-east-1`)
   - Crée une vue par défaut sans filtre
4. **Turn on Resource Explorer**

> ⚠️ `resource-explorer-2:*` + `iam:CreateServiceLinkedRole` sont requis pour l'activation
> initiale uniquement — hors ReadOnlyAccess.
> Une fois activé, ReadOnlyAccess couvre les actions de recherche (les permissions
> `ResourceExplorerRead` dans `Finops-allow-audit` sont ajoutées par précaution).
> Sans aggregator index, chaque région est isolée et la recherche multi-région ne fonctionne pas.

---

## Étape 5 — Activer Compute Optimizer + Cost Optimization Hub

Deux services d'analyse gratuits qui accélèrent fortement l'audit. 
Tous deux créent un service-linked role automatiquement.

**Compute Optimizer** — reco de rightsizing (EC2, EBS, Lambda, Auto Scaling) basées sur
les métriques CloudWatch.

> ⚠️ **À activer en premier** — Cost Optimization Hub en dépend (il importe les reco de rightsizing de Compute Optimizer).

1. Console AWS → chercher **"Compute Optimizer"**
2. Cliquer **"Get started"** puis **"Opt in"**
3. Confirmer (crée le service-linked role `AWSServiceRoleForComputeOptimizer`)
4. Preferences --> Rightsizing --> Lookback period: **32 days** (gratuit)

> ⚠️ Activation : `compute-optimizer:UpdateEnrollmentStatus` + `iam:CreateServiceLinkedRole`
> — hors ReadOnlyAccess, à faire par le client.
> ⏳ Compte 12 à 24h après l'opt-in pour que les premières recommandations apparaissent
> (Compute Optimizer a besoin d'historique CloudWatch). À activer **tôt**, donc.
> 🚫 **Ne pas activer "Compute Optimizer Automation"** (bouton "Enable Automation", namespace
> `aco-automation:*`) : cette fonctionnalité *applique automatiquement* les recommandations
> (redimensionne les ressources). Une bannière rouge d'erreur sur ce point peut apparaître — l'ignorer, l'opt-in de base est bien fait.

**Cost Optimization Hub** — centralise toutes les reco d'économies (rightsizing, Savings Plans,
RI, ressources idle) avec montants chiffrés en un seul endroit.

1. Console AWS → **Billing and Cost Management** → menu gauche **Cost Optimization Hub**
2. Cliquer **"Opt in"** (Compute Optimizer doit déjà être activé — sinon message de dépendance)
3. Confirmer (crée le service-linked role `AWSServiceRoleForCostOptimizationHub`)
4. **Régler les préférences** : page Preferences → mode d'estimation des économies
   - Savings estimation mode : **After discounts** (économies nettes, après crédits/SP existants)
   - Term length : **1 year**
   - Payment option : **No upfront**

> ⚠️ Activation : `cost-optimization-hub:UpdateEnrollmentStatus` + `iam:CreateServiceLinkedRole`.
> Préférences : `cost-optimization-hub:UpdatePreferences` (écriture) — 
> La page Preferences déclenche aussi un appel `UpdateEnrollmentStatus` en arrière-plan — d'où
> l'`AccessDenied`

---

### S3 Bucket policy pour les résultats de COMPUTE OPTIMIZER

Créer un bucket avec le préfixe `compute-optimizer-results` (région de l'infra, ex. `eu-west-3`) :
- **Account regional namespace** *(recommandé)* : préfixe `compute-optimizer-results` →
  nom final `compute-optimizer-results-[ACCOUNT-ID]-[region]-an`
- **Global namespace** : `compute-optimizer-results-[ACCOUNT-ID]-[region]`

Puis appliquer la bucket policy ci-dessous.

> ⚠️ Avant de coller : remplacer **tous** les `[ACCOUNT-ID]` par l'account ID (12 chiffres),
> `[region]` par la région de l'infra (ex. `eu-west-3`),
> et **chaque ARN par le nom exact du bucket créé** (avec ou sans suffixe `-an` selon l'option).
> Le JSON ne supporte pas les commentaires.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": "compute-optimizer.amazonaws.com"},
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::compute-optimizer-results-[ACCOUNT-ID]-[region]"
        },
        {
            "Effect": "Allow",
            "Principal": {"Service": "compute-optimizer.amazonaws.com"},
            "Action": "s3:GetBucketPolicyStatus",
            "Resource": "arn:aws:s3:::compute-optimizer-results-[ACCOUNT-ID]-[region]"
        },
        {
            "Effect": "Allow",
            "Principal": {"Service": "compute-optimizer.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": [
                "arn:aws:s3:::compute-optimizer-results-[ACCOUNT-ID]-[region]/compute-optimizer/[ACCOUNT-ID]/*",
                "arn:aws:s3:::compute-optimizer-results-[ACCOUNT-ID]-[region]/*/compute-optimizer/[ACCOUNT-ID]/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "[ACCOUNT-ID]",
                    "s3:x-amz-acl": "bucket-owner-full-control"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:compute-optimizer:[region]:[ACCOUNT-ID]:*"
                }
            }
        }
    ]
}
```

---

## Étape 6 — Créer le workgroup Athena pour les requêtes CUR

0. S'assurer d'être dans la région us-east-1
1. Console AWS → **Amazon Athena**
2. Menu gauche → **Workgroups** → **Create workgroup**

### Remplir comme suit :

| Section | Champ | Valeur |
|---------|-------|--------|
| Workgroup details | Workgroup name | `finops-cur` |
| Workgroup details | Description | Audit FinOps - lecture CUR uniquement |
| Analytics engine | Type | **Athena SQL** *(pas Apache Spark)* |
| Analytics engine | Upgrade | Automatic |
| Authentication | | **AWS Identity and Access Management (IAM)** |
| Query result configuration | Management | **Customer managed** |
| Query result configuration | Query result location | `s3://athena-results-cur-[ACCOUNT-ID]/results/` |
| Query result configuration | Encrypt query results | **SSE_S3** (AES-256, clés gérées par S3 — pas besoin de KMS) |
| Query result configuration | **Override client-side settings** | ✅ cocher |

> **"Customer managed"** est l'option qui affiche le champ d'URI S3.
> "Athena managed" (nouvelle option) ne permet pas de spécifier son propre bucket.
>
> **"Override client-side settings"** force l'utilisation du bucket ci-dessus —
> l'auditeur ne peut pas rediriger les résultats ailleurs.

3. Laisser les autres options par défaut (CloudWatch metrics : on, requester pays : off)
4. **Create workgroup**

### 6b — Configurer le garde-fou de données scannées

> Cette option n'est pas disponible dans le wizard — à faire après la création.

Athena facture ~5$/To scanné. Sans limite, une requête mal écrite sur un CUR de 100 Go
peut scanner des volumes inutiles. Le ~1 Po par défaut ne protège de rien.

1. **Workgroups** → cliquer sur le nom `finops-cur`
2. Onglet **Data usage controls**
3. Section **Per query data usage control** → **Manage**
4. Data limit : **100 GB** (le CUR en Parquet à cette échelle fera 1–5 GB — 100 GB coupe un vrai accident sans jamais bloquer une requête légitime, même sans filtre de partition)
5. Action : **Cancel query**
6. **Save**

> C'est un disjoncteur, pas une cible. Assez haut pour ne jamais bloquer
> une requête légitime, assez bas pour couper l'accident.
> Peut aussi se configurer en CLI :
> `aws athena update-work-group --work-group finops-cur --configuration BytesScannedCutoffPerQuery=107374182400`


> §6c — Workgroup finops-s3 : voir [finops-setup-s3-observability.md](finops-setup-s3-observability.md)

## Étape 7 — Demander le backfill 24 mois du CUR

À soumettre **immédiatement après la création de l'export CUR** (pas besoin d'attendre
le premier fichier — AWS a juste besoin du nom de l'export).

Gratuit (seul S3 est facturé, négligeable). Délai de traitement : 1 à 72h.

> **Permission requise :** AWS managed policy `AWSSupportAccess` — attachée directement au user (Option B, Annexe A). Elle n'est pas incluse dans `Finops-setup`.

1. Console AWS → **Support** → **Create case**
2. Type de case : **Account and billing**
3. Category : **Billing** → **Other billing questions**
4. Subject : `CUR 2.0 backfill request - 24 months`
5. Body (copier-coller, remplacer [ACCOUNT-ID]) :

```
Hello,

We recently created a CUR 2.0 export and would like to request
a historical data backfill.

Details:
- Account ID: [ACCOUNT-ID]
- Export name: finops_cur
- S3 bucket: cur-exports-[ACCOUNT-ID]
- Months requested: 24 months

Thank you.
```

6. Severity : **General guidance** → **Submit**

---
## Étape 8 — S3 Inventory + Server Access Logging

> → Voir [finops-setup-s3-observability.md](finops-setup-s3-observability.md)

## Étape 9 — Activer les Cost allocation tags

Active les clés de tags user-defined pour qu'elles apparaissent comme colonnes
exploitables dans Cost Explorer et le CUR (`resource_tags['user_xxx']`).

> ⚠️ **Non rétroactif** : un tag activé aujourd'hui n'apparaît dans les données de coût
> qu'à partir d'aujourd'hui. À faire **tôt**, même si la stratégie de tagging n'est pas finalisée.
> L'activation se fait au niveau de la **clé** (pas des valeurs).
> Permission : `ce:UpdateCostAllocationTagsStatus` — incluse dans `Finops-setup`.

1. Console AWS → **Billing and Cost Management** → menu gauche **Cost allocation tags**
2. Onglet **User-defined cost allocation tags**
3. Si la liste est vide : les clés n'apparaissent que ~24h après avoir été posées
   sur au moins une ressource. Tagger d'abord, revenir ensuite.
4. Sélectionner les clés pertinentes (ex. `env`, `service`, `client`, `team`) → **Activate**
5. Délai : jusqu'à 24h avant apparition dans Cost Explorer / CUR

---

## Étape 10 — Configurer les Lifecycle rules sur les buckets d'audit

Évite l'accumulation silencieuse de fichiers générés automatiquement.
IAM Permission requise : `s3:PutLifecycleConfiguration` — à ajouter

Pour chaque bucket : **S3** → bucket → onglet **Management** → **Lifecycle rules** → **Create lifecycle rule**

| Bucket | Rule name | Scope | Action | Expiration |
|--------|-----------|-------|--------|-----------|
| `athena-results-cur*` | `expire-athena-results-cur` | All objects | Expire current versions | 30 jours |
| `athena-results-s3*` | `expire-athena-results-s3` | All objects | Expire current versions | 30 jours |
| `cur-exports-*` | `expire-cur-exports` | All objects | Expire current versions | 456 jours |
| `compute-optimizer-results-*` | `expire-compute-optimizer` | All objects | Expire current versions | 90 jours |
| `s3-inventory-*` | `expire-inventory-reports` | All objects | Expire current versions | 90 jours |
| `s3-logging-*` | `expire-logging-reports` | All objects | Expire current versions | 90 jours |

> Versioning désactivé sur ces buckets — "Expire current versions" supprime définitivement.
> `cur-exports` à 456 jours (15 mois) : couvre le backfill 12 mois + marge audit.

## Checklist finale

- [ ] Accès IAM billing activé (étape 0)
- [ ] Customer Policies créées (customer managed)
- [ ] IAM user `finops-auditor` créé avec console access + access keys
- [ ] Managed Policies et Customer policies attachées
- [ ] Bucket `athena-results-cur-[ACCOUNT-ID]` créé (us-east-1)
- [ ] Option: Bucket `athena-results-s3-[ACCOUNT-ID]-[region]` créé (région: lieu du bucket analysé)
- [ ] Export CUR 2.0 `finops_cur` créé (wizard a créé `cur-exports-[ACCOUNT-ID]` + policy)
- [ ] Options CUR cochées : Hourly, Resource IDs, Split cost, Parquet, Create new file, Athena ON
- [ ] AWS Resource Explorer activé (Quick Setup, aggregator index configuré)
- [ ] Compute Optimizer activé (opt-in — reco rightsizing — AVANT le COH)
- [ ] Compute Optimizer - passer la lookback period à 32 jours
- [ ] Cost Optimization Hub activé (opt-in) + préférences réglées (After discounts / 1 year / No upfront)
- [ ] Workgroup Athena `finops-cur` créé (Athena SQL, Customer managed, Override ON)
- [ ] Garde-fou configuré : Per query data usage control → 100 GB → Cancel query
- [ ] Ticket backfill 12 ou 24 mois soumis (juste après création du Data Export CUR2.0)
- [ ] Catalogage Athena effectué (CREATE DATABASE + CREATE TABLE + partition projection) — Annexe A1
- [ ] Cost allocation tags activés
- [ ] CloudWatch Agent activés - Annexe A2
- [ ] Buckets S3 Inventory créés (1 par région) + bucket policies appliquées
- [ ] Inventory configurations créées sur les buckets source (Weekly / CSV / champs optionnels cochés)
- [ ] Configurer les 4 Lifecycle rules sur les buckets d'audit

---


## Annexe A1 — Catalogage Athena CUR

> → Voir [annexe-A1-catalogage-athena.md](annexe-A1-catalogage-athena.md)

## Annexe A1bis / A1ter — Catalogage Athena S3

> → Voir [finops-setup-s3-observability.md](finops-setup-s3-observability.md)

## Annexe A2 — Installer le CloudWatch agent (RAM + disque)

> → Voir [annexe-A2-cloudwatch-agent.md](annexe-A2-cloudwatch-agent.md)

*Document préparé par Clément — audit FinOps  — 2026*