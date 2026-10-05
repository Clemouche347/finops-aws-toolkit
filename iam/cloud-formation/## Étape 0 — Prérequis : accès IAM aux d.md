## Étape 0 — Prérequis : accès IAM aux données de facturation

Par défaut, les IAM users ne voient pas les données de coût/facturation, même avec `ReadOnlyAccess`.
À activer une seule fois par le root ou account admin

1. Console AWS → cliquer sur le nom du compte (en haut à droite) → **Account**
2. Descendre jusqu'à la section **"IAM user and role access to Billing Information"**
3. Cliquer **Edit**
4. Cocher **"Activate IAM Access"**
5. **Update**

> Sans cette étape, l'auditeur ne voit aucun élément de **Billing & Cost Management**
> (Cost Explorer, Data Exports, factures, budgets, etc.), même avec les bonnes policies.

## Étape 1 — Stack CloudFormation

**CloudFormation > Create Stack**

| Champ | Valeur |
|---|---|
| Template source | Upload a template file |
| Fichier | `finops-cf-iam-generic.yaml` |
| Stack name | *(à définir)* |
| AttachCloudwatchAgent | `true` |
| AuditUserPassword | *(à définir)* |
| ResourcePrefix | *(libre)* |

**Configure stack options** : laisser tel quel.

Avant de soumettre, cocher :
> I acknowledge that AWS CloudFormation might create IAM resources with custom names.

Cliquer **Submit**.

### Etape 2 — Créer les Access Keys (accès CLI/API)

1. Sur la page du user (example :`finops-auditor`) → onglet **Security credentials**
2. Section **Access keys** → **Create access key**
3. Use case : **Other** *(pas "CLI" — "Other" évite les warnings et redirections inutiles)*
4. Description tag : `FinOps audit 2026`
5. **Create access key**
6. ⚠️ **Télécharger le CSV** — le Secret Access Key ne sera plus visible après

### Etape 3 — Transmettre les credentials à l'auditeur

1. URL de connexion console : `https://[ACCOUNT-ID].signin.aws.amazon.com/console`
2. Username : `finops-auditor`
3. Mot de passe
4. Access Key ID
5. Secret Access Key
6. Region principale à configurer : `eu-west-3` (Paris) ou la région principale de l'infra

---