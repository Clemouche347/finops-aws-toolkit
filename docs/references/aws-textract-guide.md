# AWS Textract — Guide pratique

Juin 2026  
*Couvre le fonctionnement, la tarification, l'audit de coûts et les optimisations.*

---

## 1. C'est quoi Textract

Amazon Textract est un service AWS qui extrait automatiquement du texte et des données structurées depuis des documents scannés ou des images. Il va au-delà de l'OCR classique : il comprend la structure du document (formulaires, tableaux, signatures).

**Cas d'usage typiques :**
- Extraction de données depuis des formulaires administratifs
- Lecture de tableaux dans des rapports financiers
- Traitement de documents d'identité
- Numérisation de contrats ou d'actes

**Ce que Textract ne fait pas :**
- Comprendre le sens du document (c'est Comprehend/Bedrock)
- Stocker les résultats (à gérer soi-même)
- Déduplication (aucun mécanisme natif)

---

## 2. Les APIs disponibles

### 2.1 DetectDocumentText

OCR basique. Extrait le texte brut et l'écriture manuscrite. Retourne des blocs de type PAGE, LINE, WORD avec leurs coordonnées géométriques.

Usage : quand tu as juste besoin du texte brut, sans structure.

### 2.2 AnalyzeDocument

Extraction structurée. Quatre features activables indépendamment :

- **Forms** : extrait des paires clé-valeur. Ex : `"Nom du dirigeant" → "Jean Dupont"`. Idéal pour formulaires avec champs étiquetés.
- **Tables** : extrait des données tabulaires avec lignes et colonnes. Ex : un tableau actionnaires avec colonnes nom/actions/pourcentage.
- **Queries** : questions en langage naturel. Ex : `"Quel est le SIREN ?"`. Plus flexible que Forms, mais plus cher.
- **Signatures** : détecte les signatures manuscrites et électroniques.

Chaque feature activée est facturée séparément. Si tu actives Forms + Tables sur une même page, tu paies les deux.

### 2.3 AnalyzeExpense

API spécialisée pour factures et reçus. Plus précise et moins chère que AnalyzeDocument/Forms pour ce cas d'usage spécifique.

### 2.4 AnalyzeID

API spécialisée pour documents d'identité (passeports, permis de conduire). Tarification distincte.

### 2.5 AnalyzeLending

API spécialisée pour dossiers de prêt immobilier. Gère la classification et l'extraction sur les documents types de ce secteur.

---

## 3. Tarification

### 3.1 Principe général

Textract facture **à la page**, avec un tarif qui dépend entièrement de l'API appelée. Pas de tarif fixe mensuel, pas d'engagement.

| API | Tarif approximatif (première tranche) |
|---|---|
| DetectDocumentText | ~1,50 $ / 1 000 pages |
| AnalyzeDocument — Forms | ~50 $ / 1 000 pages |
| AnalyzeDocument — Tables | ~15 $ / 1 000 pages |
| AnalyzeDocument — Forms + Tables | ~65 $ / 1 000 pages |
| AnalyzeExpense | ~8-10 $ / 1 000 pages |
| AnalyzeID | tarif distinct, remises après 100k pages |

L'écart entre DetectDocumentText et AnalyzeDocument/Forms est un facteur **33**. C'est la première question à poser lors d'un audit : quelle API est appelée, et est-ce que c'est justifié ?

### 3.2 Free tier

Valable les 3 premiers mois pour les nouveaux comptes:
- DetectDocumentText : 1 000 pages/mois
- AnalyzeDocument : 100 pages/mois

Une fois expiré, chaque appel console ou programmatique est facturé. **La console AWS appelle les mêmes APIs que le code.** Les demos sur les samples Amazon = facturation réelle si le free tier est épuisé.

Pour vérifier l'état du free tier : Billing > Free Tier > filtrer "Textract".

### 3.3 Remises volume

Les remises s'appliquent au-delà de 1 million de pages/mois pour la plupart des APIs (100k pour AnalyzeID). Peu pertinent pour des volumes PME.

### 3.4 Facturation sur échec

AWS ne facture que les pages traitées avec succès. Une requête en erreur sans données extraites n'est pas facturée.

---

## 4. Synchrone vs Asynchrone

### Synchrone (DetectDocumentText / AnalyzeDocument)

- 1 page à la fois (image JPEG, PNG ou PDF 1 page)
- Réponse immédiate
- Timeout possible sur documents lourds
- Adapté : flux temps réel, documents courts

### Asynchrone (StartDocumentTextDetection / StartDocumentAnalysis)

- Jusqu'à 3 000 pages en un seul appel
- AWS traite en arrière-plan
- Notification via SNS quand terminé
- Obligatoire pour les PDFs multipages
- Même tarif que le synchrone

Pour des documents de plusieurs pages (contrats, rapports), l'async est le seul mode viable. Un PDF de 20 pages soumis en async = 1 appel API, 20 pages facturées.

---

## 5. Visibilité des coûts

C'est le point le plus piégeux de Textract dans un contexte d'audit.

### Ce que Cost Explorer montre

- Le coût total Textract sur la période
- Potentiellement la répartition par type d'opération via la colonne `line_item_operation` dans CUR 2.0

### Ce que CloudTrail montre

- Qui a appelé Textract (IAM user ou role applicatif)
- Quand
- Quelle API (AnalyzeDocument, DetectDocumentText, etc.)
- Depuis quelle région

**Limite importante :** CloudTrail exclut certains paramètres de requête (pour des raisons de confidentialité). Le nombre de pages par appel n'est pas dans les logs.

### Ce qui n'est pas visible nativement

- Le nombre exact de pages par appel
- Le coût par document traité
- L'identité du document source (quel fichier)

Pour obtenir cette granularité, il faut une instrumentation custom : Lambda qui croise les événements CloudTrail avec les métadonnées des objets S3 correspondants.

### Permissions CloudTrail nécessaires pour l'audit

```
cloudtrail:LookupEvents
cloudtrail:DescribeTrails
cloudtrail:GetTrail
```

Note : `cloudtrail:LookupEvents` est couvert par la policy `ReadOnlyAccess` (confirmé v185, mai 2026). "View Event History" dans la console appelle `LookupEvents` en arrière-plan.

Pour filtrer les événements Textract dans Event History : Event name = `AnalyzeDocument` (ou `DetectDocumentText`, `StartDocumentAnalysis`). Limite : 90 jours d'historique.

---

## 6. Optimisations possibles

### 6.1 Utiliser l'API la moins chère qui suffit

C'est le levier le plus simple et le plus impactant.

Avant d'utiliser AnalyzeDocument, se poser la question : est-ce que j'ai vraiment besoin d'extraction structurée, ou est-ce que le texte brut suffit ? Si le texte brut suffit, DetectDocumentText est 33x moins cher.

De même : n'activer que les features réellement nécessaires. Forms seul coûte 50 $/1k pages. Ajouter Tables inutilement monte à 65 $/1k pages.

### 6.2 Cache des résultats

Le gaspillage le plus courant : retraiter le même document plusieurs fois.

**Principe :** stocker le résultat Textract (en S3 ou DynamoDB) avec le hash du fichier source comme clé. Avant tout appel Textract, vérifier si le hash est déjà connu.

**Hash et stockage :**
- SHA256 ou MD5 calculé sur le fichier source
- S3 calcule automatiquement le MD5 des objets (champ ETag pour les uploads single-part) — exploitable sans dev supplémentaire
- DynamoDB : table `document_hash` → `textract_result_location`

**Limite importante :** le cache par hash fonctionne uniquement pour des fichiers **identiques à l'octet près**. Deux scans physiques du même document produiront des fichiers différents (compression JPEG variable, bruit, luminosité) et donc des hashs différents. Le cache est pertinent pour des fichiers re-soumis numériquement, pas pour des scans physiques.

### 6.3 Vérification avant upload (frontend)

Pour éviter à la fois l'upload S3 et l'appel Textract :

```
1. Utilisateur sélectionne le fichier dans l'interface
2. Hash SHA256 calculé côté navigateur (en mémoire, avant upload)
3. Appel API backend : "ce hash existe déjà ?"
4. Backend vérifie DynamoDB
   -> Trouvé : retourne le résultat existant, rien n'est uploadé
   -> Pas trouvé : upload S3 + appel Textract + stockage résultat et hash
```

C'est l'optimisation la plus complète mais elle nécessite du dev frontend + backend.

### 6.4 Filtrage des pages inutiles

Textract facture à la page. Sur un PDF de 20 pages dont seules 5 contiennent des données exploitables, envoyer le PDF entier = 4x le coût nécessaire.

Solution : logique de pré-filtrage upstream qui identifie et extrait uniquement les pages pertinentes avant l'envoi à Textract. Peut réduire les coûts de 40-70% sur des documents multipages à contenu hétérogène.

### 6.5 Qualité des documents en entrée

Pré-traiter les scans avant envoi : correction d'inclinaison, amélioration du contraste, résolution 150-300 DPI. Des documents de mauvaise qualité nécessitent des retraitements, ce qui double les coûts.

---

## 7. Ce qui n'existe pas nativement

Points à avoir en tête pour ne pas chercher ce qui n'existe pas :

| Ce qu'on cherche | Réalité |
|---|---|
| Bouton "activer la déduplication" | N'existe pas. Dev custom requis. |
| Cache automatique des résultats Textract | N'existe pas. A implémenter avec S3 + DynamoDB. |
| Nombre de pages par appel dans CloudTrail | Non disponible. Estimation via coût / tarif unitaire. |
| Différence de tarif sync vs async | Aucune différence. Même prix à la page. |
| Vérification de doublon avant upload dans S3 | Non natif. S3 propose l'ETag (MD5) après l'upload, pas avant. |

---

## 8. Architecture type avec cache

```
[Utilisateur]
     |
     | upload fichier
     v
[Backend / API]
     |
     | 1. calcul hash SHA256 (fichier en mémoire)
     | 2. lookup DynamoDB : hash connu ?
     |
     |-- OUI --> retourner résultat stocké (0 cout Textract)
     |
     |-- NON --> upload S3
                    |
                    v
              [AWS Textract]
                    |
                    v
              résultat JSON
                    |
                    v
              stocker dans DynamoDB
              (hash -> résultat ou référence S3)
                    |
                    v
              retourner résultat à l'utilisateur
```

**Composants nécessaires :**
- S3 : stockage des fichiers sources
- Textract : extraction
- DynamoDB : index hash → résultat
- Lambda (optionnel) : orchestration si traitement asynchrone
- SNS (optionnel) : notification fin de traitement async

**Ce que S3 fournit gratuitement :** l'ETag de chaque objet est le MD5 du fichier (pour les uploads single-part). Récupérable via `aws s3api head-object`. Utilisable comme hash sans calcul supplémentaire si la vérification se fait après l'upload.

---

## 9. Checklist audit Textract

Pour auditer l'utilisation de Textract sur un compte AWS :

**Dans Cost Explorer**
- Coût total Textract sur 6 mois
- Tendance mensuelle : stable, croissante, pics ?
- Répartition par région (double traitement possible si multi-région)

**Dans CloudTrail**
- Quelles APIs sont appelées (AnalyzeDocument vs DetectDocumentText)
- Qui appelle : role applicatif ou IAM user nominatif (= tests manuels des devs)
- Fréquence des appels : patterns réguliers ou pics inexpliqués

**Questions à poser en entretien technique**
- Les résultats Textract sont-ils mis en cache ou recalculés à chaque accès ?
- Les PDFs multipages sont-ils envoyés entiers ou page par page ?
- Y a-t-il une logique de filtrage des pages non pertinentes ?
- Quelle API est utilisée, et pourquoi ce choix vs une API moins chère ?
- Des tests manuels sont-ils effectués en console ?

**Estimation du gain potentiel (exemple)**

Volume mensuel : 10 000 pages en AnalyzeDocument/Forms = 500 USD / mois.
Hypothèse 30% de re-soumissions sans cache : gaspillage estimé = 150 $ / mois, soit 1 800 $ / an.

---

*Tarifs indicatifs, région eu-west-3. Vérifier aws.amazon.com/textract/pricing pour les valeurs exactes à jour.*
