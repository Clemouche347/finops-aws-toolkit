# CloudWatch Agent

Juin 2026

---

## 1. Pourquoi installer l'agent CloudWatch ?

AWS ne mesure **jamais nativement** la RAM ni l'espace disque d'une instance EC2.
L'hyperviseur AWS n'a pas accès à l'intérieur du système d'exploitation — il voit seulement
le CPU (%), le réseau (Mbps), et les I/O disque (IOPS (input/output operations per second))

| Métrique | Sans agent | Avec agent |
|---|---|---|
| CPU utilization | ✅ Natif CloudWatch | ✅ Natif |
| Network in/out | ✅ Natif CloudWatch | ✅ Natif |
| RAM — `mem_used_percent` | ❌ Jamais disponible | ✅ Via CWAgent |
| Espace disque — `disk used_percent` | ❌ Jamais disponible | ✅ Via CWAgent |

Note: l'espace disque est utile pour l'analyse capacité des EBS.

> **Impact FinOps direct :** sans agent, Compute Optimizer affiche "Data Unavailable" sur la RAM.
> Le rightsizing mémoire ne peut pas être chiffré.
> Avec l'agent, Compute Optimizer intègre automatiquement les métriques RAM
> après 30h de données — **à condition que la dimension `InstanceId` soit présente** (voir section 4).

---

## 2. Architecture — les trois composants

Trois éléments doivent être en place pour que le flux fonctionne :

| Composant | Rôle | Où ça vit |
|---|---|---|
| **SSM Agent** | Canal de commande vers l'instance, sans SSH ni port 22 | Pré-installé Amazon Linux 2/2023 |
| **CloudWatch Agent** | Collecte RAM + disque, pousse vers CloudWatch | Installé via SSM Run Command |
| **Parameter Store** | Stocke la config JSON (quelles métriques, quel intervalle) | SSM → Parameter Store |

**Flux complet :**

```
EC2 instance → CloudWatch Agent (collecte RAM/disk) → CloudWatch namespace CWAgent → Compute Optimizer (RAM, rightsizing)
```

---

## 3. IAM — deux entités distinctes, ne pas confondre

> ⚠️ **Erreur classique :** attacher `CloudWatchAgentServerPolicy` au user humain.
> Cette policy est faite pour être portée par l'**instance EC2**, pas par un humain.
> Elle n'a aucun effet sur un user IAM.

| Entité | Type | Policies | Pour quoi faire |
|---|---|---|---|
| Rôle EC2 `ec2-cloudwatch-agent` | IAM role (instance profile) | `CloudWatchAgentServerPolicy` + `AmazonSSMManagedInstanceCore` | L'agent tourne et pousse les métriques vers CloudWatch |
| Ops humain | IAM user | `finops-cloudwatch-agent` (customer policy) | Créer le rôle & l'attacher aux instances, pousser la config dans Parameter Store, déployer l'agent |
| Auditeur (`finops-auditor`) | IAM user | `cloudwatch:GetMetricData` + `cloudwatch:ListMetrics` | Lire les métriques en ReadOnly — n'installe rien |

### Rôle EC2 — policies AWS managed à attacher

Ces deux policies existent nativement chez AWS, rien à créer :

- `AmazonSSMManagedInstanceCore` — autorise l'instance à être pilotée via SSM (installation, configuration de l'agent)
- `CloudWatchAgentServerPolicy` — autorise l'agent à lire les métadonnées de l'instance et à écrire les métriques vers CloudWatch

### Policy ops humain — `finops-cloudwatch-agent`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SSMCloudWatchAgentDeploy",
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeInstanceInformation",
                "iam:GetInstanceProfile"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SSMSendCommandCWAgentOnly",
            "Effect": "Allow",
            "Action": "ssm:SendCommand",
            "Resource": [
                "arn:aws:ssm:*:*:document/AWS-ConfigureAWSPackage",
                "arn:aws:ssm:*:*:document/AmazonCloudWatch-ManageAgent",
                "arn:aws:ec2:*:*:instance/*"
            ]
        },
        {
            "Sid": "SSMParameterStore",
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ssm:GetParameter",
                "ssm:AddTagsToResource",
                "ssm:DeleteParameter"
            ],
            "Resource": "arn:aws:ssm:*:*:parameter/AmazonCloudWatchAgent*"
        },
        {
            "Sid": "CreateCWAgentRole",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:CreateInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:PassRole",
                "iam:TagRole",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeleteRole",
                "iam:DeleteInstanceProfile"
            ],
            "Resource": [
                "arn:aws:iam::*:role/CloudWatchAgent*",
                "arn:aws:iam::*:instance-profile/CloudWatchAgent*"
            ]
        },
        {
            "Sid": "AttachCWAgentPoliciesOnly",
            "Effect": "Allow",
            "Action": [
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy"
            ],
            "Resource": "arn:aws:iam::*:role/CloudWatchAgent*",
            "Condition": {
                "ArnEquals": {
                    "iam:PolicyARN": [
                        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
                        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
                    ]
                }
            }
        },
        {
            "Sid": "EC2InstanceProfile",
            "Effect": "Allow",
            "Action": [
                "ec2:AssociateIamInstanceProfile",
                "ec2:DescribeIamInstanceProfileAssociations"
            ],
            "Resource": "*"
        }
    ]
}
```

**Next** → Policy name : `Finops-cloudwatch-agent` → **Create policy**


> **Note `iam:PassRole` :** AWS flag cette permission car avec `Resource: *` elle permet de passer
> n'importe quel rôle à EC2. En production, restreindre à l'ARN du rôle exact :
> `arn:aws:iam::*:role/ec2-cloudwatch-agent` avec condition `iam:PassedToService: ec2.amazonaws.com`.

---

## 4. Config JSON de l'agent — version complète recommandée

Stockée dans SSM Parameter Store sous le nom `AmazonCloudWatchAgent-Config`.
L'agent la lit au démarrage.

```json
{
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 300
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["*"],
        "metrics_collection_interval": 300
      }
    }
  }
}
```

### Pourquoi `append_dimensions` avec `InstanceId` est obligatoire

**C'est une condition stricte de Compute Optimizer**.

> La doc AWS (officielle) : *"If the InstanceId dimension is missing or you overwrite it with a custom
> dimension name, Compute Optimizer can't collect memory utilization data for your instance."*

Sans `InstanceId` dans les dimensions :
- CloudWatch reçoit les métriques, elles sont visibles dans le namespace CWAgent
- Mais Compute Optimizer **ne peut pas faire le lien** entre la métrique RAM et l'instance EC2
- Résultat : "Data Unavailable" pour la RAM dans Compute Optimizer, comme si l'agent n'était pas installé

### Paramètres expliqués

| Paramètre | Valeur | Pourquoi |
|---|---|---|
| `namespace` | `CWAgent` | Namespace visible dans CloudWatch → Metrics |
| `InstanceId` | `${aws:InstanceId}` | **Obligatoire pour Compute Optimizer** — fait le lien métrique ↔ instance |
| `InstanceType` | `${aws:InstanceType}` | Utile pour filtrer dans CloudWatch par type d'instance |
| `mem_used_percent` | measurement RAM | % RAM utilisée — suffisant pour rightsizing |
| `disk used_percent` | `resources: ["*"]` | Tous les points de montage |
| `metrics_collection_interval` | 300 (5 min) | Suffisant pour FinOps — évite les coûts haute résolution |

### Ce que tu vois dans CloudWatch après installation

CloudWatch → Metrics → All metrics → namespace **CWAgent** (apparaît 2–5 min après démarrage).

Avec `append_dimensions`, deux groupes de dimensions apparaissent :

- `host` → ancien format (hostname interne)
- `host, InstanceId, InstanceType` → nouveau format avec instance ID lisible

> ⚠️ **Points de montage `disk` :** l'agent remonte une ligne par point de montage.
> Sur une instance Amazon Linux standard, tu verras 6 lignes : `/`, `/boot/efi`, `/dev`, `/run`, `/tmp`, `/dev/shm`.
> Pour le FinOps, regarder **uniquement `/`** (partition `nvme0n1p1`, filesystem `xfs`) —
> c'est là que vivent les données applicatives.
> Les autres (`tmpfs`, `devtmpfs`) sont des filesystems virtuels en mémoire, sans intérêt FinOps.

---

## 5. Installer l'agent sur des instances existantes — risque ?

**Réponse courte : risque très faible, aucun downtime.**

L'installation via SSM Run Command est non-destructive :

| Point | Détail |
|---|---|
| **Downtime applicatif** | Aucun — l'agent s'installe en parallèle des processus existants |
| **Redémarrage instance** | Non requis |
| **Interruption réseau** | Aucune |
| **Overhead CPU** | Négligeable — < 1% en collecte toutes les 5 min |
| **Overhead RAM** | ~50 MB — perceptible sur t3.micro (1 GB), transparent sur t3.small et au-dessus |
| **Overhead disque** | Quelques MB pour les logs de l'agent |
| **Impact application** | Aucun — processus totalement isolé |

> **Note :** sur `t3.micro` (1 GB RAM), les ~50 MB de l'agent représentent ~5% 
> de la mémoire totale. Risque théorique si l'instance est déjà saturée — 
> mais sans agent, cette saturation est précisément invisible. 
> Le déploiement est le seul moyen de le savoir.

**À communiquer au CTO avant l'installation :**
- Prévenir l'équipe qu'une opération SSM sera faite (traçabilité)
- Vérifier que les instances n'ont pas de politique de sécurité bloquant l'installation de packages
- L'opération est réversible : un Run Command `AWS-ConfigureAWSPackage` avec `Action: Uninstall` supprime l'agent proprement

---

## 6. Procédure pas à pas

### Étape 1 — Créer le rôle IAM pour les instances EC2

IAM → Roles → Create role → AWS service → EC2

Attacher les deux policies managées :
- `AmazonSSMManagedInstanceCore`
- `CloudWatchAgentServerPolicy`

Nommer le rôle : `ec2-cloudwatch-agent`

### Étape 2 — Attacher le rôle aux instances existantes

EC2 → sélectionner l'instance → **Actions → Security → Modify IAM role** → choisir `ec2-cloudwatch-agent` → Save

Pas besoin de redémarrer. Le rôle prend effet immédiatement pour les nouveaux appels API.

### Étape 3 — Vérifier que les instances apparaissent dans SSM Fleet Manager

Systems Manager → **Fleet Manager → Managed Nodes**

Si une instance n'apparaît pas :
- Vérifier que `AmazonSSMManagedInstanceCore` est bien attachée au rôle
- Vérifier la connectivité réseau vers les endpoints SSM 
- Attendre 2–3 min après l'attachement du rôle

 > Pour utiliser CloudWatch agent, il faut soit un subnet public avec accès Internet, soit un subnet privé avec des Interface endpoints* ou un NAT Gateway. Donc effectivement : pour > collecter des métriques qui permettent d'économiser, tu dois d'abord dépenser.

* Pour SSM + CloudWatch agent, il faut 4 Interface Endpoints :
`ssm`, `ec2messages`, `ssmmessages` (pour SSM)
`monitoring` (pour CloudWatch)
~USD 29/mois

### Étape 4 — Créer la config dans Parameter Store

Systems Manager → **Parameter Store → Create parameter**

- Name : `AmazonCloudWatchAgent-Config`
- Type : `String`
- Value : le JSON complet de la section 4 (avec `append_dimensions`)

### Étape 5 — Installer l'agent via SSM Run Command

SSM → **Run Command** → Run command

- Document : `AWS-ConfigureAWSPackage`
- Action : `Install`
- Name : `AmazonCloudWatchAgent`
- Targets : sélectionner les instances

> **Multi-instances :** dans Targets, choisir "Choose instances manually" pour cocher
> toutes les instances d'un coup, ou "Specify instance tags" pour cibler par tag
> (ex. `Environment = prod`). Un seul Run Command exécute en parallèle sur tout le parc.

→ **Run** → attendre Success sur chaque instance

### Étape 6 — Appliquer la configuration

SSM → **Run Command** → Run command

- Document : `AmazonCloudWatch-ManageAgent`
- Action : `configure`
- Mode : `ec2`
- Optional Configuration Source : `ssm`
- Optional Configuration Location : `AmazonCloudWatchAgent-Config`
- Targets : les mêmes instances

→ **Run** → attendre Success

> **ASG / nouvelles instances :** Run Command est one-shot.
> Pour un déploiement automatique sur les instances futures,
> configurer une SSM Association (State Manager) avec ciblage par tag —

### Etape 6bis 
pour les futures instances (ASG), créer une SSM Association via la console :
SSM → State Manager → Create association

Document : AWS-ConfigureAWSPackage
Targets : "Key = tag, Value = Environment/prod"
Schedule : rate(30 days) (install + update automatique)

Puis une deuxième association pour la config :

Document : AmazonCloudWatch-ManageAgent
Mêmes targets par tag
Schedule : none (ou rate(7 days) pour que la config se réapplique)


### Étape 7 — Vérifier que l'agent tourne

SSM → **Run Command** → document `AWS-RunShellScript`

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status
```

Résultat attendu :

```json
{
  "status": "running",
  "configstatus": "configured",
  "version": "1.300067.0b1404"
}
```

### Étape 8 — Vérifier les métriques dans CloudWatch

CloudWatch → Metrics → All metrics → namespace **CWAgent**

Apparaît 2–5 min après le démarrage de l'agent. Vérifier la présence de `mem_used_percent`
avec la dimension `InstanceId`.

---

## 7. Lien avec Compute Optimizer

Compute Optimizer lit automatiquement le namespace `CWAgent` sans configuration supplémentaire,
**à condition que la dimension `InstanceId` soit présente** (voir section 4).

| Point | Détail |
|---|---|
| **30h de données minimum** | Compute Optimizer génère ses premières recommandations après 30h d'accumulation. Pas de recommandation instantanée. |
| **Sans `InstanceId`** | Compute Optimizer ne fait pas le lien avec l'instance. RAM affichée "Data Unavailable" même si l'agent tourne. |
| **Avec `InstanceId`** | CPU + RAM + réseau + disque I/O → rightsizing complet sur toutes les dimensions. |

---

## 8. Troubleshooting

| Symptôme | Cause probable | Solution |
|---|---|---|
| Instance absente de Fleet Manager | `AmazonSSMManagedInstanceCore` manquant ou réseau SSM bloqué | Attacher le rôle → attendre 2–3 min |
| `ParameterNotFound` dans les logs | Parameter Store vide ou nom incorrect dans le champ Location | Vérifier le nom exact : `AmazonCloudWatchAgent-Config` |
| `status: stopped` après ManageAgent | Config non appliquée ou JSON invalide | Relire les logs Run Command + valider le JSON |
| `configstatus: not configured` | Étape Parameter Store non faite avant le Run Command | Créer le paramètre SSM, puis relancer ManageAgent |
| CWAgent absent dans CloudWatch | Agent stopped ou < 5 min écoulées | Vérifier status via `AWS-RunShellScript`, attendre 5 min |
| Compute Optimizer : Data Unavailable (RAM) | `InstanceId` absent des dimensions, ou < 30h de données | Vérifier `append_dimensions` dans le JSON + attendre 30h |
| 6 lignes `disk` au lieu d'1 | Comportement normal — une ligne par point de montage | Ne garder que `/` (nvme0n1p1) pour l'analyse FinOps |

---

## 9. Coût

- **Agent :** gratuit (open source)
- **Custom metrics CloudWatch :** ~0,30 $/métrique/mois (premières 10 000)
- Pour ~12 instances × 2 métriques → quelques dollars/mois
- Négligeable, mais à signaler au client puisqu'on installe ça pour le FinOps
- instances en subnet privé sans sortie internet: 35 USD / mois par instance (Interface Endpoints)

## Autres
Si le client dit qu'il a déjà CloudWatchAgent installé, mais uniquement métrique mémoire sans disque: --> juste mettre à jour la config
Ce qu'on fait :
Créer/écraser le paramètre SSM AmazonCloudWatchAgent-Config avec le JSON complet (mem + disk + append_dimensions)
Rejouer uniquement l'association AmazonCloudWatch-ManageAgent avec optionalRestart: yes
