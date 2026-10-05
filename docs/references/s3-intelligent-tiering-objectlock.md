# S3 Intelligent-Tiering et Object Lock

Version: Juin 2026

## Partie 1 : S3 Intelligent-Tiering

### 1.1 Le principe

Intelligent-Tiering est une classe de stockage S3 qui déplace automatiquement les objets entre plusieurs tiers selon leur fréquence d'accès réelle. Pas besoin de connaître les patterns d'accès à l'avance. AWS surveille chaque objet et fait le travail.

C'est précisément le cas d'usage pour lequel AWS a créé cette classe : quand on ne sait pas comment les données seront accédées, ou quand les patterns changent dans le temps.

Économies typiques : 30 à 50% sur le stockage Standard à l'échelle d'un parc réel.

---

### 1.2 Les tiers automatiques

Trois tiers s'activent automatiquement, sans configuration, avec les mêmes performances (latence milliseconde, même débit) :

| Tier | Condition de bascule | Coût stockage (eu-west-3) |
|---|---|---|
| Frequent Access | Objet accédé récemment | ~0,023$/GB/mois (= Standard) |
| Infrequent Access | 30 jours sans accès | ~0,0125$/GB/mois (-46%) |
| Archive Instant Access | 90 jours sans accès | ~0,004$/GB/mois (-83%) |

Si un objet est à nouveau accédé après avoir migré vers un tier inférieur, il remonte automatiquement en Frequent Access. Aucun frais de récupération sur ces trois tiers.

Deux tiers optionnels supplémentaires (Archive Access et Deep Archive Access) nécessitent une activation explicite. Ils offrent des économies plus importantes mais avec une latence de récupération de plusieurs heures. A ne pas activer pour des données qui doivent rester accessibles rapidement.

---

### 1.3 Le seul coût : le frais de monitoring

Intelligent-Tiering facture **0,0025$ par 1 000 objets et par mois** sur chaque objet géré, qu'il bouge ou non entre les tiers. C'est fixe, indépendant de la taille de l'objet.

C'est là que tout se joue : ces frais de monitoring peuvent dépasser l'économie de stockage pour les petits objets.

---

### 1.4 Le piège des petits objets

**Règle AWS depuis septembre 2024 :** les objets sous 128 KB ne peuvent pas être transités vers Intelligent-Tiering via une lifecycle rule. Ils restent en Standard de fait.

**Le seuil de rentabilité réel est plus haut :** pour qu'un objet qui transite en Infrequent Access génère une économie supérieure au frais de monitoring, il faut que sa taille dépasse environ **238 KB**. En pratique, en dessous de 500 KB à 1 MB, le monitoring annule souvent l'économie.

Exemple concret :
- 1 million d'objets de 128 KB en Intelligent-Tiering
- Frais de monitoring : 1 000 × 0,0025$ = **2,50$/mois**
- Économie de stockage si 60% passent en Infrequent : environ **0,81$/mois**
- Résultat : Intelligent-Tiering coûte plus cher que Standard

A contrario :
- 1 million d'objets de 2 MB
- Frais de monitoring : toujours 2,50$/mois
- Économie de stockage : **plusieurs centaines de dollars/mois**
- Résultat : Intelligent-Tiering est très rentable

**Règle pratique :** Intelligent-Tiering est pertinent pour les objets > 500 KB à 1 MB avec accès imprévisible. En dessous, rester en Standard ou utiliser une lifecycle policy classique vers Standard-IA.

---

### 1.5 Le filtre par taille dans une lifecycle rule

On n'a pas besoin de séparer les petits et gros objets dans deux buckets différents. Une lifecycle rule peut filtrer par taille dans le même bucket avec `ObjectSizeGreaterThan` :

```json
{
  "Rules": [{
    "ID": "intelligent-tiering-large-objects",
    "Status": "Enabled",
    "Filter": { "ObjectSizeGreaterThan": 512000 },
    "Transitions": [{ "Days": 0, "StorageClass": "INTELLIGENT_TIERING" }]
  }]
}
```

`512000` = 500 KB en bytes. Les objets sous 500 KB restent en Standard, les autres passent en Intelligent-Tiering. Un seul bucket, zéro modification du code applicatif, zéro déplacement physique des données.

`Days: 0` signifie que la règle s'applique dès l'upload.

Note sur la syntaxe : `ObjectSizeGreaterThan` et `ObjectSizeLessThan` **excluent** les valeurs exactes. Un objet de exactement 512 000 bytes ne sera pas transité.

---

### 1.6 Coût de la transition initiale

Passer des objets existants en Intelligent-Tiering via une lifecycle rule n'est pas gratuit. La transition est facturée par objet (opération PUT par objet transité). Sur un bucket avec beaucoup d'objets, ce coût one-shot peut être notable.

A calculer avant de recommander : nombre d'objets × coût par PUT. Vérifier sur la page de pricing S3 le coût des lifecycle transitions pour la région concernée.

Ordre de grandeur: environ 0,01$ pour 1 000 objets (en eu-west-3).
Pour 100 000 objets transités en Intelligent-Tiering : 100 × 0,01$ = 1$ de coût one-shot

---

### 1.7 Quand ne pas recommander Intelligent-Tiering

- Objets accédés de façon prévisible et fréquente (assets applicatifs, configs servies à chaque requête) : ils restent en Frequent Access, le monitoring est payé pour rien
- Objets de courte durée de vie (créés et supprimés en moins de 30 jours) : pas de bénéfice, frais de monitoring payé pour rien
- Petits objets nombreux (logs, JSONs de quelques Ko, thumbnails) : monitoring > économie
- Buckets système (logs, CUR, backups gérés) : risque d'interférence avec des process attendus
- Pattern d'accès prévisible et connu : une lifecycle policy classique (Standard → IA → Glacier) est plus simple et plus rapide à atteindre le tier cible qu'Intelligent-Tiering qui attend les signaux d'accès

---

### 1.8 Recommandation

Avant de recommander Intelligent-Tiering, utiliser l'inventaire S3 pour vérifier :

1. La taille moyenne des objets par bucket (champ Size)
2. Le type de données (documents Textract = bons candidats ; petits JSONs = mauvais candidats)
3. La présence d'un Object Lock (voir Partie 2)

---

## Partie 2 : Object Lock et WORM

### 2.1 Le principe

Object Lock est un mécanisme qui rend un objet S3 **immuable pendant une période définie** : personne ne peut le supprimer ni l'écraser, même un admin, même le root du compte, même AWS Support.

Le modèle sous-jacent s'appelle **WORM : Write Once, Read Many**. On écrit une fois, on peut lire autant de fois qu'on veut, mais on ne modifie ni ne supprime pas. C'est une garantie au niveau du stockage lui-même, pas une simple restriction de permissions IAM.

Object Lock nécessite que le versioning soit activé sur le bucket. Une fois Object Lock activé sur un bucket, il est impossible de désactiver Object Lock ou de suspendre le versioning.

---

### 2.2 Pourquoi ça existe

**Conformité réglementaire** : certains secteurs ont des obligations légales de conserver des données sans altération possible. Object Lock a été évalué par Cohasset Associates pour les régulations financières américaines (SEC 17a-4, CFTC, FINRA). Les obligations peuvent venir du droit commercial (conservation des documents comptables), du droit des sociétés (registres de mouvements de titres, BSPCE), ou d'exigences contractuelles de clients soumis à régulation financière.

**Protection anti-ransomware** : même si un attaquant compromet le compte AWS et obtient des droits de suppression, il ne peut pas effacer les objets lockés pendant leur période de rétention.

---

### 2.3 Les deux modes de rétention

**Governance mode**
- La plupart des utilisateurs ne peuvent pas supprimer l'objet
- Un utilisateur avec la permission `s3:BypassGovernanceRetention` peut contourner la protection
- La date de rétention peut être réduite ou supprimée par un utilisateur privilégié
- Usage : tests, cas où un override reste nécessaire, migration progressive

**Compliance mode**
- Aucun utilisateur ne peut supprimer ni modifier l'objet pendant la rétention
- Pas même le root du compte
- Pas même AWS Support (AWS n'a pas l'autorité de contourner Object Lock Compliance)
- La date de rétention ne peut être que prolongée, jamais réduite
- Usage : obligations réglementaires strictes, archivage légal

Règle pratique : **toujours tester en Governance mode avant de déployer en Compliance**. Une erreur de configuration en Compliance mode (ex. 10 ans au lieu de 10 jours) est irréparable jusqu'à l'expiration.

---

### 2.4 Les deux mécanismes de protection

**Retention period** : une date d'expiration fixe posée sur l'objet. A cette date, la protection expire automatiquement. L'objet n'est pas supprimé automatiquement, il devient simplement suppressible.

**Legal hold** : même protection qu'une retention period, mais sans date d'expiration. Reste actif jusqu'à ce qu'un utilisateur avec `s3:PutObjectLegalHold` le retire explicitement. Utilisé pour les situations sans durée définie (contentieux, audit en cours).

Les deux peuvent coexister sur le même objet. Si une retention period expire mais qu'un legal hold est toujours actif, l'objet reste protégé.

---

### 2.5 Ce qu'Object Lock ne protège pas

Object Lock protège des versions d'objets, pas des clés. Il est toujours possible de :

- Créer une **nouvelle version** d'un objet (le PUT réussit, une nouvelle version est créée avec ses propres paramètres de rétention, l'ancienne version lockée reste intacte)
- Poser un **delete marker** sur un objet locké (S3 se comporte comme si l'objet était supprimé pour les applications, mais la version lockée reste physiquement et continue d'être facturée)

Les delete markers eux-mêmes ne sont pas protégés par Object Lock.

---

### 2.6 Impact sur les lifecycle rules et les classes de stockage

**Bonne nouvelle : Object Lock est compatible avec les transitions de classe.**

Object Lock est maintenu quelle que soit la classe de stockage, y compris durant les transitions via lifecycle rules. Passer un objet locké de Standard vers Intelligent-Tiering ou Glacier Instant ne casse pas la protection WORM.

**Mais attention au stockage froid avec des obligations de disponibilité rapide.**

Le problème n'est pas technique mais opérationnel : si un document sous Object Lock finit en Glacier Flexible Retrieval (standard: 3-5h de latence) ou Deep Archive (standard: 12h- bulk: 48h), et qu'une obligation réglementaire ou judiciaire exige de le produire rapidement, la latence devient un problème.

**Règle pour les données avec Object Lock :**
- Glacier Instant Retrieval ou Intelligent-Tiering (accès milliseconde) : sûr
- Glacier Flexible ou Deep Archive : seulement si la latence de récupération est acceptable pour le cas d'usage

Une lifecycle rule peut créer des delete markers sur des objets lockés, mais la version lockée ne sera pas supprimée tant que la rétention est active.

---

### 2.7 Le cas extrême : supprimer le compte AWS

La seule façon de supprimer un objet en mode Compliance avant expiration de sa rétention est de fermer le compte AWS.

Quand un compte AWS est fermé, il y a une période de grâce de 90 jours pendant laquelle il peut être réactivé. Après ces 90 jours, AWS supprime définitivement toutes les ressources du compte, y compris les objets en Compliance mode, quelle que soit leur date de rétention restante.

Ce n'est pas une option pratique pour corriger une erreur de configuration :-)

---

### 2.8 Pièges classiques à éviter

**Ne jamais tester en Compliance mode.** Toujours commencer en Governance pour valider les durées, puis basculer en Compliance pour la production.

**Vérifier les durées de rétention avant de les poser.** Une rétention de 10 ans au lieu de 10 jours est irréversible en Compliance mode. Personne ne peut la corriger.

**Ne pas confondre Object Lock et permissions IAM.** Les deux sont indépendants. Des permissions IAM restrictives n'équivalent pas à Object Lock : un utilisateur suffisamment privilégié peut toujours contourner des restrictions IAM. Seul Object Lock Compliance est véritablement inviolable.

**Un bucket avec Object Lock ne peut pas être utilisé comme destination de Server Access Logging.** A noter pour la configuration d'audit : ne pas pointer les logs vers un bucket locké.

**Object Lock protège des versions, pas des clés.** Comprendre la différence version / clé / delete marker est essentiel pour ne pas être surpris lors de tests de suppression.

---

### 2.9 Pour un audit

Questions à se poser  :

1. "Est-ce que des buckets ont Object Lock activé ?" — visible dans S3 Inventory si le champ Object Lock est coché, ou via `aws s3api get-object-lock-configuration --bucket nom-bucket`
2. "En mode Governance ou Compliance ?"
3. "Quelles sont les obligations de conservation légale ?"
4. "Y a t-il une exigence de disponibilité rapide des documents en cas d'audit ?"

Si Object Lock Compliance est présent : ces objets ne peuvent pas être supprimés, seulement transités vers une classe moins chère. 

---

## Synthèse décision rapide

| Situation | Recommandation |
|---|---|
| Objets > 1 MB, accès imprévisible | Intelligent-Tiering |
| Objets < 500 KB nombreux | Rester en Standard |
| Pattern d'accès connu et prévisible | Lifecycle policy classique (Standard → IA → Glacier) |
| Objets sous Object Lock Compliance | Transition de classe possible, suppression impossible |
| Données légales à produire rapidement | Glacier Instant ou Intelligent-Tiering uniquement (pas Flexible ni Deep Archive) |
| Données légales sans contrainte de délai | Deep Archive envisageable après confirmation |
| Buckets système (logs, CUR) | Exclure d'Intelligent-Tiering |
