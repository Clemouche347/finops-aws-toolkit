# Module `cloudwatch-agent`

Crée le paramètre SSM Parameter Store contenant la configuration JSON du CloudWatch Agent.

La config par défaut collecte `mem_used_percent` et `disk_used_percent` toutes les 300 s,
avec `InstanceId` + `InstanceType` en dimensions — le strict nécessaire pour le rightsizing
mémoire/disque via Compute Optimizer.

## Paramètre SSM créé

| Champ | Valeur |
|-------|--------|
| Name | `AmazonCloudWatchAgent-Config` (défaut) |
| Type | `String` |
| Scope IAM | `parameter/AmazonCloudWatchAgent*` |

## Variables

| Variable | Type | Défaut | Description |
|----------|------|--------|-------------|
| `parameter_name` | `string` | `AmazonCloudWatchAgent-Config` | Nom du paramètre SSM. Doit commencer par `AmazonCloudWatchAgent` (scope de la policy `Finops-cloudwatch-agent`). |
| `agent_config_json` | `string` | `null` | JSON de configuration. Si null, utilise la config standard RAM + disque 300 s. Passer ici le JSON issu du wizard si le client a une config personnalisée. |
| `resource_prefix` | `string` | `""` | Accepté pour cohérence d'interface. **Non appliqué au nom du paramètre SSM** — voir exception SSM ci-dessous. |
| `tags` | `map(string)` | `{}` | Tags appliqués au paramètre SSM. |

### Exception SSM

Le nom du paramètre `AmazonCloudWatchAgent-Config` est une convention imposée par le CloudWatch Agent — le document SSM Run Command `AmazonCloudWatch-ManageAgent` le recherche par ce nom exact. Préfixer ce paramètre casserait la résolution de la configuration par l'agent sans modifier en parallèle les commandes de déploiement. `resource_prefix` est donc déclaré dans ce module pour cohérence d'interface mais n'est pas appliqué au nom du paramètre.

## Outputs

| Output | Description |
|--------|-------------|
| `parameter_name` | Nom du paramètre SSM |
| `parameter_arn` | ARN du paramètre SSM |

## Ce que ce module ne fait PAS

- **N'installe pas le CloudWatch Agent** sur les instances EC2 — action SSM Run Command manuelle
  (document `AWS-ConfigureAWSPackage`, action `Install`, name `AmazonCloudWatchAgent`).
- **Ne crée pas le rôle IAM EC2** `CloudWatchAgent` — action manuelle console IAM
  (policies `CloudWatchAgentServerPolicy` + `AmazonSSMManagedInstanceCore`).
- **N'applique pas la configuration** aux instances — action SSM Run Command manuelle
  (document `AmazonCloudWatch-ManageAgent`, location `AmazonCloudWatchAgent-Config`).
- **Ne déploie pas via SSM Automation** — voir annexe A2 pour la procédure complète.

Procédure complète : `docs/guides/setup/annexe-A2-cloudwatch-agent.md`.
