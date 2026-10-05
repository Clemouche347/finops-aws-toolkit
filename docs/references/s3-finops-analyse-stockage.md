# Analyser S3 pour un audit FinOps

Rédigé à partir d'une session de travail de juin 2026.

Ce document couvre comment analyser le stockage S3 dans le cadre d'un audit de coûts : quels outils existent, ce que chacun apporte, leurs limites, et les pièges IAM rencontrés en pratique. À lire posément.

---

## 1. La question de fond : pourquoi analyser S3 ?

Dans un audit FinOps, S3 est rarement le plus gros poste de dépense pour une structure avec 2-3 k$/mois de facture AWS totale. 

Mais c'est un poste facile à laisser dériver, et les leviers d'optimisation sont simples à expliquer :

- des objets qui s'accumulent sans politique d'expiration (lifecycle)
- du versioning activé sans expiration des anciennes versions
- des objets froids restés en classe Standard alors qu'ils pourraient passer en Standard-IA ou Glacier
- des buckets orphelins d'anciens environnements

Le réflexe à garder : **regarder S3 vite (10-15 min via Storage Lens), poser une recommandation crédible, ne pas y passer une demi-journée tant que la facture réelle n'est pas vue.**

---

## 2. Le concept clé : la classe de stockage est par objet

Erreur de débutant à éviter : croire qu'un bucket "est" dans une classe de stockage.

**La classe de stockage est définie objet par objet, pas au niveau du bucket.** Un même bucket peut contenir des objets en Standard, d'autres en Standard-IA, d'autres en Glacier Instant Retrieval, etc.

C'est précisément ce que les lifecycle policies orchestrent : elles font transiter automatiquement les objets d'une classe à une autre selon des règles d'âge ou de conditions.

Exemple de lifecycle policy typique pour des documents :

- accès fréquent les 30 premiers jours → rester en Standard
- accès rare au-delà → transition vers Standard-IA à J+30 (environ -46% sur le coût de stockage vs Standard)
- archivage au-delà de 90 jours → Glacier Instant Retrieval si rappel occasionnel nécessaire

---

## 3. Les trois outils d'analyse S3

Trois outils complémentaires, qui ne répondent pas à la même question.

### 3.1 S3 Storage Lens — la vue macro

Tableau de bord consolidé sur l'ensemble des buckets. Donne en un coup d'œil :

- la taille par bucket
- quels buckets ont du versioning actif
- quels buckets n'ont aucune lifecycle policy
- la distribution des classes de stockage

C'est l'outil de départ : 10 minutes pour avoir une vue d'ensemble et repérer les anomalies grossières.

Le tier gratuit (28 métriques, rétention 14 jours) suffit largement pour un audit ponctuel.

**Piège IAM important :** l'accès root ne fonctionne PAS pour consulter un dashboard Storage Lens. Il faut obligatoirement un IAM user avec les permissions explicites.

Permissions nécessaires pour la lecture du dashboard :
- `s3:ListStorageLensConfigurations`
- `s3:GetStorageLensConfiguration`
- `s3:GetStorageLensDashboard`

Ces trois actions sont couvertes par la policy managée `ReadOnlyAccess` (qui inclut `s3:Get*` et `s3:List*`).

### 3.2 S3 Inventory — l'inventaire détaillé objet par objet

Génère un rapport (CSV, ORC ou Parquet) listant tous les objets d'un bucket avec leurs métadonnées, sur une base quotidienne ou hebdomadaire.

C'est une première base pour dimensionner finement une transition de classe : on a la liste réelle, objet par objet.

Champs utiles à inclure pour un audit de coûts :
- **Size** — indispensable, c'est la base du coût
- **Last modified** — pour repérer les objets non modifiés depuis longtemps (ne pas confondre avec **Last accessed**)
- **Storage class** — pour voir la répartition Standard / IA / Glacier
- **Lifecycle expiration date** — montre si une règle existe déjà

Champs inutiles pour un audit de coûts (sécurité / conformité / ops) : Encryption, Replication status, Object Lock, ACL, Owner, Permissions, Checksum, Multipart upload, Bucket key status.

Cas particulier de l'**ETag** : c'est l'empreinte MD5 de l'objet (deux objets avec le même ETag ont le même contenu). En théorie utile pour détecter des doublons — par exemple des documents retraités plusieurs fois par Textract. En pratique pour un audit : le gain en stockage est marginal, et la détection du vrai gaspillage Textract (retraitement) ne passe pas par l'inventaire S3 mais par les logs Textract ou CloudTrail. C'est une piste dans un deuxième temps, pas une priorité. Le cocher ne coûte rien, mais ne pas y consacrer de temps.

Coher éventuellement **Object Lock** afin d'analyser si certains objets ou leurs versions ne pourraient pas être transférés ou supprimées pour des raisons légales par example.

Pour le scope des versions : choisir **Current versions only**. "Include all versions" multiplie le volume du rapport et n'est utile que si on audite spécifiquement l'accumulation de versions. Si Storage Lens révèle du versioning sans expiration, on le note comme recommandation séparée — pas besoin de lister toutes les versions dans l'inventaire.

Premier rapport disponible sous 48h maximum.

### 3.3 Cost Explorer / CUR — le coût réel par classe

Group by `Usage Type` dans Cost Explorer fait apparaître les lignes par classe de stockage : `TimedStorage-ByteHrs` (Standard), `IntelligentTieringFAStorage`, `GlacierStorage`, etc.

C'est ce qui montre ce que le stockage coûte réellement aujourd'hui, par classe. À croiser avec l'inventaire pour prioriser : un bucket énorme mais en Glacier coûte peut-être moins qu'un petit bucket en Standard très sollicité.

---

## 4. Le piège central : LastModified n'est PAS LastAccessed

C'est l'un des points les plus importants.

### Ce que LastModified mesure vraiment

`LastModifiedDate` = date de la dernière **écriture** (PUT, COPY, upload). Ce n'est PAS la date de dernière lecture.

### S3 ne stocke pas de date de dernier accès

Contrairement à un filesystem Linux avec son `atime`, **un GET sur un objet S3 ne met à jour aucune métadonnée.** Il n'existe nativement aucune "date de dernier accès" dans S3.

### Pourquoi c'est critique pour les recommandations de classe

Le choix de la classe de stockage dépend de la **fréquence d'accès en lecture**, pas de la date de modification.

Un fichier jamais modifié depuis 2 ans mais lu quotidiennement n'a rien à faire en Glacier. Donc `LastModified` seul est **insuffisant** pour recommander une transition de classe.

### Ce qu'on peut dire honnêtement

Plutôt que de recommander une transition sur la seule base de LastModified :

> "Sans logs d'accès activés, on ne peut pas mesurer la fréquence de lecture. LastModified indique l'activité d'écriture, pas de lecture. Pour des documents type Textract, le pattern probable est : écriture unique à l'upload, lecture rare ensuite — ce qui justifierait une transition. Mais c'est une hypothèse métier à valider."

### La recommandation rigoureuse

Plutôt que de recommander une lifecycle policy à l'aveugle, recommander d'**activer S3 Server Access Logging maintenant**, pour disposer de données d'accès réelles dans 30-60 jours, et décider des transitions ensuite. C'est plus solide.

---

## 5. Mesurer les accès réels : les options

### 5.1 S3 Server Access Logging — l'option retenue

Logue chaque requête (GET, PUT, DELETE) sur un bucket, avec timestamp, objet, opération. C'est ce qui permet de répondre à "qui accède à quoi et quand".

**Limite fondamentale : aucune donnée rétroactive.** Les logs n'existent qu'à partir de l'activation. Si jamais activé, on part de zéro au moment du setup. Raison de plus pour l'activer dès le setup de l'infra d'audit, pour avoir du recul au moment du livrable.

Coût : **pas de frais d'activation.** On paie uniquement le stockage standard des fichiers de logs. À l'échelle d'une petite entreprise, négligeable — moins d'1$/mois.

### 5.2 CloudTrail data events — l'alternative payante

CloudTrail peut logger les accès objets S3 (GetObject, PutObject...), avec des infos plus riches. Mais c'est **désactivé par défaut** et **payant** (environ 0,10$ / 100 000 events). À ne pas activer pour un simple audit de coûts.

---

## 6. Inventory et Logging sont complémentaires, pas redondants

Question piège que je me suis posée : "si j'ai le Server Access Logging, l'Inventory ne sert plus à rien ?"

Non. Les deux répondent à des questions différentes :

| Outil | Question à laquelle il répond | Type de vue |
|---|---|---|
| **S3 Inventory** | Qu'est-ce qui existe, quelle taille, quelle classe ? | Statique (le contenu) |
| **Server Access Logging** | Qui accède à quoi et quand ? | Dynamique (les accès) |

Pour une recommandation lifecycle solide il faut les deux :
- l'Inventory pour cartographier ce qui existe et identifier les candidats à une transition
- le Logging pour valider que ces objets ne sont effectivement pas lus avant de recommander Glacier

L'un sans l'autre est incomplet : Inventory sans logs = on ne sait pas si les objets sont accédés ; logs sans Inventory = on sait qui accède mais pas le volume ni le coût.

---

## 7. Détails de configuration retenus

### S3 Inventory

- **Status** : Enable
- **Object versions** : Current versions only
- **Frequency** : Weekly (suffit pour un audit)
- **Format** : CSV (le plus simple à ouvrir)
- **Champs** : Size, Last modified, Storage class, Lifecycle expiration date, Object Lock
- **Destination** : un bucket dédié, même région que le bucket source

### Server Access Logging

- **Log object key format** : prendre le format **partitionné**
  `[Account]/[Region]/[Bucket]/[YYYY]/[MM]/[DD]/...`
  plutôt que le format à plat. Le partitionnement par date permet à Athena de filtrer sans scanner tous les fichiers — utile pour les requêtes type "quels objets lus le mois dernier".
- **Source of date** : **S3 event time** (pas "log file delivery time"). La date doit refléter le moment de l'accès réel, pas le moment où AWS a livré le fichier de log (qui peut avoir plusieurs heures de retard). Sinon les partitions ne correspondent pas aux vrais timestamps.

### Contraintes communes aux deux

- Le bucket destination doit être dans **la même région ET le même compte** que le bucket source.
- Un client ayant deux régions, il faut **deux buckets destination**, un par région.
- Plusieurs buckets source peuvent pointer vers le même bucket destination ; les logs sont séparés par bucket source (via le TargetPrefix).

---

## 8. Les pièges IAM rencontrés

Ces actions ne sont pas couvertes par les policies de lecture standard et déclenchent un "You don't have permission" :

| Action | À quoi elle sert |
|---|---|
| `s3:PutInventoryConfiguration` | Activer l'inventaire sur le bucket source |
| `s3:PutBucketLogging` | Activer le server access logging sur le bucket source |
| `s3:GetBucketLogging` | Vérifier la config logging existante avant écrasement |
| `s3:PutBucketPolicy` | Poser la bucket policy sur le bucket destination |
| `s3:CreateBucket` | Créer le bucket destination |
| `s3:PutBucketPublicAccessBlock` | Configurer le Block Public Access du destination |

### Le cas sensible : PutBucketPolicy

`s3:PutBucketPolicy` est une action **puissante et potentiellement dangereuse**. Elle permet de réécrire entièrement les règles d'accès d'un bucket : rendre public, autoriser un compte externe, supprimer des restrictions existantes.

Point important : `PutBucketPolicy` **remplace la policy entière** — ce n'est pas un patch. Il n'existe pas d'action `ModifyBucketPolicy` ; c'est `PutBucketPolicy` dans tous les cas, que le bucket ait déjà une policy ou non. Donc si le bucket destination a déjà une policy, elle est écrasée.

Deux garde-fous limitent le risque :
1. **Block Public Access** (activé par défaut depuis 2023) empêche toute policy de rendre des objets publics, même posée.
2. Une bucket policy ne **bypasse pas** les permissions IAM de l'utilisateur. Se donner des droits dans une bucket policy ne donne pas ces droits si la policy IAM ne les accorde pas — les deux doivent autoriser.

### La bonne pratique

Ne JAMAIS demander `s3:PutBucketPolicy` sur les buckets applicatifs. Uniquement sur le(s) bucket(s) destination dédié(s), créés exprès et vides, via un scope de ressource restreint :

```
"Resource": "arn:aws:s3:::*s3inventory*"
```

Version de policy allégée et suffisante pour gérer les buckets destination :

```json
{
  "Sid": "InventoryDestinationManagement",
  "Effect": "Allow",
  "Action": [
    "s3:CreateBucket",
    "s3:GetBucketPolicy",
    "s3:PutBucketPolicy",
    "s3:PutBucketPublicAccessBlock"
  ],
  "Resource": "arn:aws:s3:::*s3inventory*"
}
```

### Sur les ACLs : ne plus les utiliser

`s3:PutBucketAcl` n'est PAS nécessaire pour S3 Inventory — AWS utilise une bucket policy, pas des ACLs.

Plus largement, les ACLs S3 sont obsolètes. Depuis avril 2023, tout nouveau bucket a `Object Ownership` réglé sur **Bucket owner enforced** par défaut : les ACLs sont désactivées, le propriétaire du bucket possède tous les objets, et l'accès se gère exclusivement par policies. AWS recommande explicitement de garder les ACLs désactivées.

Conséquences :
- `s3:PutBucketAcl` : à retirer des policies write. Potentiellement bloquée de toute façon si Bucket owner enforced est actif.
- `s3:GetBucketAcl` : action de lecture inoffensive. Pas nécessaire pour l'inventaire moderne, mais peut servir à vérifier si un vieux bucket a encore des ACLs actives. Pas la peine de lancer un refactoring de toutes les policies pour la retirer.

---

## 9. Format de bucket policy — rappel de syntaxe

Une bucket policy doit toujours être enveloppée dans `Version` + `Statement`. Une erreur fréquente : la console AWS génère parfois un Statement seul, sans l'enveloppe, ce qui provoque "Missing Statement / Invalid Policy Element".

Structure correcte d'une bucket policy autorisant S3 à écrire l'inventaire :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InventoryAndAnalyticsPolicy",
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": ["s3:PutObject"],
      "Resource": ["arn:aws:s3:::finops-s3-inventory-XXXX/*"],
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "arn:aws:s3:::bucket-source"
        },
        "StringEquals": {
          "aws:SourceAccount": "[Account ID]",
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
```

---

## 10. Activation en batch (script à fournir)

Pas de fonction native "appliquer une config sur tous les buckets en un clic". Mais c'est scriptable. Le point d'attention : router chaque bucket vers le bucket destination de SA région.

### Limite à connaître

On peut avoir jusqu'à 1 000 configurations d'inventaire par bucket. Aucune limite gênante ici.

### Inventory en batch, multi-régions

```bash
DEST_PARIS="arn:aws:s3:::finops-s3-inventory-eu-west-3"
DEST_FRANKFURT="arn:aws:s3:::finops-s3-inventory-eu-central-1"

for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
  region=$(aws s3api get-bucket-location \
    --bucket $bucket --query "LocationConstraint" --output text)

  if [ "$region" == "eu-central-1" ]; then
    DEST=$DEST_FRANKFURT
  else
    DEST=$DEST_PARIS
  fi

  aws s3api put-bucket-inventory-configuration \
    --bucket $bucket \
    --id "finops-audit" \
    --inventory-configuration '{
      "IsEnabled": true,
      "IncludedObjectVersions": "Current",
      "Destination": {"S3BucketDestination": {"Format": "CSV", "Bucket": "'$DEST'"}},
      "Schedule": {"Frequency": "Weekly"},
      "OptionalFields": ["Size", "LastModifiedDate", "StorageClass"]
    }'
done
```

Note : via la console, AWS pose automatiquement la bucket policy sur le destination. **Via CLI, il faut la poser manuellement** (cf. section 9).

### Server Access Logging en batch, multi-régions

```bash
LOG_BUCKET_PARIS="finops-s3-logs-eu-west-3"
LOG_BUCKET_FRANKFURT="finops-s3-logs-eu-central-1"

for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
  region=$(aws s3api get-bucket-location \
    --bucket $bucket --query "LocationConstraint" --output text)

  [ "$region" == "eu-central-1" ] && LOG_BUCKET=$LOG_BUCKET_FRANKFURT || LOG_BUCKET=$LOG_BUCKET_PARIS

  aws s3api put-bucket-logging \
    --bucket $bucket \
    --bucket-logging-status '{
      "LoggingEnabled": {
        "TargetBucket": "'$LOG_BUCKET'",
        "TargetPrefix": "'$bucket'/"
      }
    }'
done
```

Le `TargetPrefix` par nom de bucket sépare proprement les logs dans le bucket destination.

---

## 11. Le point sur la vérification CloudWatch

La console S3 suggère d'utiliser CloudWatch pour "vérifier la santé" du server access logging. C'est une bonne pratique de production, pas un prérequis d'audit.

La raison : le logging peut mettre plus d'une heure à prendre effet, et si AWS n'arrive pas à écrire les logs (bucket policy incorrecte, mauvaise région, bucket supprimé), **il n'y a aucune alerte native** — les logs sont silencieusement perdus. Les "request metrics" CloudWatch sur le bucket destination permettent de détecter ces échecs de livraison via une métrique d'erreurs.

Pour l'audit : pas nécessaire. Il suffit de vérifier manuellement que des fichiers de logs apparaissent bien dans le bucket destination dans les 24h suivant l'activation.

---

## 12. Synthèse — la séquence logique

1. **Storage Lens** d'abord (10 min) : vue macro, repérer les anomalies grossières.
2. **Cost Explorer / Usage Type** : combien coûte réellement S3, par classe.
3. **S3 Inventory** (résultats 24-48h) : cartographie objet par objet, classes et tailles.
4. **Server Access Logging** activé tôt : pour disposer dans 30-60 jours de la fréquence d'accès réelle, seule donnée qui justifie vraiment une transition de classe.
5. **Recommandation prudente** : ne pas affirmer "ces objets sont froids" sur la seule base de LastModified. Proposer plutôt d'activer le logging et décider des transitions ensuite.

## 13.Versions

Penser au lifecycle sur les versions

