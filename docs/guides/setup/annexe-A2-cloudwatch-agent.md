## Annexe 3 — Installer le CloudWatch agent (RAM + disque)

> **Pour qui :** finops admin.
> Modification des rôles EC2, installation d'un binaire par instance, coût de custom metrics.
> Permet d'avoir la mesure RAM/disque dans CloudWatch et en input de Compute Optimizer.
> Sans agent, Compute Optimizer ne dispose d'aucune donnée RAM ("Data Unavailable") ni d'espace
> disque utilisé. Le rightsizing s'appuie alors uniquement sur CPU, réseau et disk I/O —
> le rightsizing mémoire et espace disque ne peut pas être chiffré.

**Pourquoi :** AWS ne mesure ni la RAM ni l'espace disque nativement (l'hyperviseur ne voit pas
l'intérieur de l'instance). Le CloudWatch agent les collecte et les pousse vers CloudWatch.

**Méthode recommandée : AWS Systems Manager (SSM)** — pas de SSH, pas de binaire à télécharger
à la main, déployable sur plusieurs instances d'un coup.

> ⏳ **À installer le plus tôt possible** : Compute Optimizer a besoin d'au moins **30h de
> métriques** accumulées (+ jusqu'à 24h d'analyse) avant que la RAM apparaisse dans ses
> recommandations. Agent installé en début de mission = données mémoire exploitables
> pour le livrable capacité.

### Prérequis

- Les instances EC2 ont le **SSM agent** installé (déjà présent sur Amazon Linux 2/2023 et
  les AMI Windows récentes) et apparaissent dans **Systems Manager → Fleet Manager / Managed Nodes**.
- Si une instance n'apparaît pas : il lui manque le rôle SSM ou l'accès réseau aux endpoints SSM.

### Permissions requises

Customer managed policy **`Finops-cloudwatch-agent`** — voir **Annexe A**.
Elle scope la création de rôle sur `CloudWatchAgent*` — d'où le nom imposé à l'étape 1.

### Étape 1 — Rôle IAM sur les instances

1. IAM → **Roles** → **Create role** → trusted entity : **AWS service** → **EC2**
2. Attacher les 2 policies managées :
   - `CloudWatchAgentServerPolicy` (écrire les métriques vers CloudWatch)
   - `AmazonSSMManagedInstanceCore` (gestion via SSM)
3. Nommer le rôle **`CloudWatchAgent`** ⚠️ nom imposé — la policy `Finops-cloudwatch-agent`
   n'autorise la création/attachement que sur `CloudWatchAgent*` → **Create**
4. Attacher le rôle aux instances : EC2 → sélectionner l'instance → **Actions → Security →
   Modify IAM role** → choisir `CloudWatchAgent`

### Étape 2 — Installer l'agent via SSM Run Command

1. Console **Systems Manager** → **Run Command** → **Run a command**
2. Document : chercher **`AWS-ConfigureAWSPackage`**
3. Action : `Install` · Name : `AmazonCloudWatchAgent`
4. Targets : sélectionner les instances (ou par tag)
5. Enable CloudWatch logs (optionnel)
6. **Run**

> Recommandation : si le parc EC2 grandit, passer par SSM Automation plutôt que Run Command,
> avec un document d'automatisation qui installe + configure l'agent en une seule opération,
> déclenchable par tag.

### Étape 3 — Créer la configuration de l'agent

Deux options :

**A — Wizard (sur une instance, génère le JSON) :**
```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```
Choisir **Standard** (option 2) : inclut mémoire, paging, processeur, disque logique/physique.
Puis stocker le JSON généré dans Parameter Store (étape ci-dessous).

**B — JSON minimal (RAM + disque)** à stocker dans Parameter Store :
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

> `append_dimensions` permet d'avoir les InstanceId dans CloudWatch — sinon on a uniquement
> les hostnames AWS autogénérés qui ne disent pas grand-chose.

> Intervalle **300 s (5 min)** suffit largement pour du FinOps (on veut des moyennes/pics sur
> plusieurs jours, pas la seconde). La haute résolution (1s/15s) coûte 4× plus en appels API
> sans valeur ajoutée ici. `mem_used_percent` + `disk_used_percent` = le strict nécessaire
> pour analyser le rightsizing.

Création du paramètre :
1. Systems Manager → **Parameter Store** → **Create parameter**
2. Name : `AmazonCloudWatchAgent-Config` · Type : `String` · Value : le JSON ci-dessus → **Create**

> Le nom doit commencer par `AmazonCloudWatchAgent` — la policy `Finops-cloudwatch-agent`
> (write) et la whitelist de la deny `Finops-deny-data-access` (read) sont scopées sur
> `parameter/AmazonCloudWatchAgent*`.

### Étape 4 — Appliquer la configuration via SSM

1. Systems Manager → **Run Command** → document **`AmazonCloudWatch-ManageAgent`**
2. Action : `configure` · Mode : `ec2` · Optional Configuration Source : `ssm` ·
   Optional Configuration Location : `AmazonCloudWatchAgent-Config` *(nom exact du paramètre créé)*
3. Targets : les mêmes instances → **Run**

### Étape 5 — Vérifier

Après ~5 min :
CloudWatch → **Metrics** → namespace **`CWAgent`** → les métriques `mem_used_percent`
et `disk_used_percent` doivent apparaître.

> Pour localiser l'agent, ne pas chercher dans SSM Fleet Manager (la colonne "Agent version"
> = version du SSM agent, pas du CW agent). Le namespace `CWAgent` dans CloudWatch Metrics
> est la preuve de fonctionnement.

### Coût

- Agent : gratuit (open source).
- Custom metrics : **~0,30 $/métrique/mois** (premières 10 000). Attention au comptage :
  chaque combinaison de dimensions = une métrique distincte, et `"resources": ["*"]` crée
  une métrique disque **par filesystem**. Compter plutôt 3-5 métriques par instance Linux
  typique. Pour une petite infra (5-15 instances) : quelques dollars/mois. Négligeable,
  mais non nul — à signaler au client, puisqu'on installe ça *pour* le FinOps.
- Rétention CloudWatch : à 300 s d'intervalle, les points sont conservés 63 jours
  en l'état, puis agrégés à 1 h (conservés 455 jours).

> **Positionnement :** dans le cadre du setup (user finops-admin, policies Annexe A),
> c'est l'auditeur qui déploie l'agent — c'est une action d'instrumentation, pas une
> modification applicative. Si le client préfère le faire lui-même, cette annexe sert
> de mode opératoire à lui transmettre. Si l'agent n'est pas en place au moment de
> l'audit, le livrable capacité s'appuie sur Compute Optimizer sans données RAM,
> et l'installation de l'agent devient une recommandation du rapport.
