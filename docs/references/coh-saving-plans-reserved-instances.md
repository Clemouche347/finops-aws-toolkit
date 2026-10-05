# FinOps — COH, Savings Plans, Reserved Instances

Juin 2026

---

## 1. Cost Optimization Hub (COH)

### Ce que c'est
Couche d'agrégation centralisée lancée en novembre 2023. Sa seule valeur : agréger et dédupliquer des recommandations qui viennent d'autres services AWS :
- AWS Compute Optimizer (rightsizing EC2, migrations Graviton, ressources idle, EBS, RDS, ECS...) 
- AWS Billing & Cost Management (recommandations Savings Plans et Reserved Instances).

### Ce qu'il apporte vs Compute Optimizer seul

Il déduplique les recommandations qui se chevauchent (ex. une instance EC2 qui apparaît à la fois dans "rightsizing" et "idle"), pour éviter de compter deux fois les économies potentielles. Il tient compte des remises existantes (SP/RI) pour estimer les gains nets.


### Utilité pour l'audit

Utile en première lecture ou pour recouper l'information.

---

## 2. Savings Plans (SP)

### Principe
Engagement en **$/heure de spend AWS** sur 1 ou 3 ans, en échange d'une remise sur le tarif On-Demand. AWS applique automatiquement la remise à l'usage éligible, dans la limite du montant engagé.

### Les 3 types

| Type | Ce qui est fixé | Flexibilité | Remise max | Couvre |
|---|---|---|---|---|
| **Compute SP** | Rien (spend horaire seulement) | Maximale — family instance, région, OS, taille, tenancy  | ~66% | EC2 + Fargate + Lambda |
| **EC2 Instance SP** | Famille d'instance + région | Taille,  OS, tenancy flexibles | ~72% | EC2 uniquement |
| **SageMaker SP** | — | Usage SageMaker | ~64% | SageMaker uniquement |

**Règle de décision simple** : si le workload peut évoluer (changement de famille, de région, ajout Lambda/Fargate) → Compute SP. Si la famille est figée pour longtemps et qu'on veut maximiser la remise → EC2 Instance SP.

### Achats et annulation
- Durée : 1 an ou 3 ans (non résiliable sauf fenêtre de 7 jours post-achat si < 100$/h et même mois calendaire)
- Payment : All Upfront (remise max) / Partial Upfront / No Upfront
- Retour possible sous 7 jours si ≤ 100$/h d'engagement et même mois

---

## 3. Reserved Instances (RI)

### Principe
Engagement sur des attributs fixes  
Remise ~40-60% on-demand. Pas flexible entre tailles —   
Changement de type = perte de couverture. À utiliser pour des charges stables et prévisibles où tu sais que la taille ne change pas.

**RI Standard:** fixé: instance family, OS, tenancy, région. Flexible: size,AZ  
**RI Convertible:** fixé : région. Flexible: famille/OS/tenancy modifiables

### Attributs qui définissent un RI
| Attribut | Exemple | Impact |
|---|---|---|
| Instance type | `m5.large` | Famille + taille fixées |
| Région | `eu-west-1` | Scope géographique |
| OS | Linux / Windows | Windows coûte plus cher |
| Tenancy | `default` / `dedicated` | Dédié = surcoût |
| Scope | Regional / Zonal | Voir ci-dessous |

**Point clé : AWS matche par attributs, pas par ID.** Si tu termines une instance et en recrées une avec la même config, le RI s'applique automatiquement à la nouvelle instance. Aucune action manuelle nécessaire.

### Standard vs Convertible

| | Standard RI | Convertible RI |
|---|---|---|
| Remise max | ~72% | ~54% |
| Modifiable | Non | Oui (échange contre autre type) |
| Revendable | Oui (Marketplace AWS) | Non |
| Cas d'usage | Workload stable et figé | Workload susceptible d'évoluer |

### Scope : Regional vs Zonal

| | Regional RI | Zonal RI |
|---|---|---|
| Application | Toute instance de la famille dans la région | Instance dans l'AZ précise uniquement |
| Garantie de capacité | Non | Oui |
| Recommandation défaut | ✓ Plus sûr | Uniquement si garantie de capacité nécessaire |

### RI Marketplace — vaut-il le coup ?
Possible d'acheter des RI Standard revendus par d'autres comptes. Avantage : parfois un terme résiduel court (6–18 mois) adapté au besoin. 
Risques :  
- Terme résiduel court → vérifier la durée restante
- Non modifiable

### Services couverts par les RI (hors EC2)
RDS, ElastiCache, OpenSearch, Redshift, MemoryDB, DynamoDB.

---

## 4. SP vs RI — tableau de décision

| Situation | Recommandation |
|---|---|
| Workload stable, famille et taille figées depuis 6+ mois | RI Standard — remise maximale |
| Workload en évolution prévisible (resize, changement famille) | Compute SP |
| Lambda ou Fargate à couvrir | Compute SP obligatoire (RI ne couvre pas) |
| Besoin de garantie de capacité dans une AZ précise | RI Zonal uniquement |
| Workload pas encore stabilisé (< 6 mois) | Aucun engagement — observer d'abord |

---

## 5. Comment mesurer la couverture

### Deux métriques distinctes à ne pas confondre

**Coverage** : quel % de mon usage On-Demand est couvert par un SP ou RI ?
- Objectif : > 80%
- En dessous → opportunité d'achat

**Utilization** : les SP/RI que j'ai achetés sont-ils consommés à 100% ?
- En dessous de 100% → je paie pour de la capacité inutilisée
- Optimiser les deux simultanément, pas l'un au détriment de l'autre

### Où les trouver dans Cost Explorer

| Rapport | Chemin | Couvre |
|---|---|---|
| SP Coverage | Billing → Savings Plans → Coverage Report | SP uniquement |
| RI Coverage | Cost Explorer → Saved Reports → RI Coverage | RI uniquement |
| SP Utilization | Billing → Savings Plans → Utilization Report | SP uniquement |
| RI Utilization | Cost Explorer → Reserved Instances → Utilization | RI uniquement |

**Il n'existe pas de rapport unifié SP+RI dans une seule vue de coverage.**

### Recommandations d'achat

| Section | Chemin | Contenu |
|---|---|---|
| SP Recommendations | Cost Explorer → Savings Plans → Recommendations | SP uniquement |
| RI Recommendations | Cost Explorer → Reserved Instances → Recommendations | RI EC2 + RDS + ElastiCache + OpenSearch + Redshift + MemoryDB + DynamoDB |

Paramètre clé pour les deux : **look-back period**. Utiliser 30 jours minimum ou 60 pour lisser les anomalies. 7 jours sur-représente les pics récents.

SP ou RI, pas d'option calendaire : toujours glissant à partir de la date d'achat (1-an ou 3-ans).

---

## 6. Pièges à retenir

| Piège | Explication |
|---|---|
| Acheter trop tôt | Si le workload n'est pas stable, on paie un engagement pour une ressource supprimée 3 mois plus tard |
| Confondre coverage et utilization | Coverage = suis-je couvert ? Utilization = est-ce que j'utilise ce que j'ai acheté ? Ce sont deux problèmes opposés |
| SP appliqué heure par heure | Une instance qui tourne 12h/24h → couverture SP effective à 50% seulement |
| RI Zonal non utilisé dans l'AZ visée | Si l'instance bascule dans une autre AZ, le RI Zonal ne s'applique pas → coût gaspillé |


Un SP n'est pas un pool d'heures. C'est un engagement à payer X USD/heure, toutes les heures, pendant 1 ou 3 ans — qu'il y ait de l'usage ou non.
On ne peut pas reporter le commitment non utilisé d'une heure sur une autre heure.

---

## 7. Application audit

**Questions clés à se poser :**
- "SP ou RI actifs ?"
- "Workloads de prod tournent-ils 24/7 sans interruption depuis 6+ mois ?"
- "instances EC2 ou RDS dont la taille ne changera pas avant 12 mois ?"

**Si SP/RI absents et workload stable** → quick win probable, à quantifier dans le rapport.

**Si SP/RI présents** → vérifier utilization d'abord. Un RI sous-utilisé = problème prioritaire avant tout nouvel achat.

**Règle de prudence** : ne jamais recommander un achat SP/RI si le workload n'a pas au moins 3–6 mois d'historique stable. Sur un compte jeune ou en restructuration, recommander d'observer avant d'engager.
