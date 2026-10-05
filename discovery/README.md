

```bash
aws sts get-caller-identity

`export AWS_PROFILE=xxxxxxxxx`
```
Ces commandes listent l'inventaire pas les couts
Faire tourner ces Commandes CLI sur les régions dans lesquelles le client a des resources: 
Elles tournent avec ReadOnly, **ne renvoient aucune donnée applicative**
(le CLI est régional, contrairement à Cost Explorer)

> Les orphelins sont aussi visibles dans la console EC2 (Volumes filtrés sur "available", Elastic IPs, Snapshots)et Trusted Advisor → onglet Cost Optimization en sort déjà une partie automatiquement. Le CLI n'est pas indispensable.

### 1 EBS non attachés (gaspillage classique)
```bash
aws ec2 describe-volumes \
  --region eu-west-3 \
  --filters "Name=status,Values=available" \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,Type:VolumeType,Created:CreateTime}' \
  --output table
```

> `status=available` = disque non rattaché à une instance = il dort et tu paies.
> gp3 ≈ $0.08/Go/mois, gp2 ≈ $0.10. 5-15 volumes orphelins = $50-200/mois typiques.

### 2 Elastic IP inutilisées
```bash
aws ec2 describe-addresses \
  --region eu-west-3 \
  --query 'Addresses[?AssociationId==`null`].{IP:PublicIp,Alloc:AllocationId}' \
  --output table
```

> Depuis le 1er février 2024, AWS facture toutes les IPv4 publiques, , EIP attachée à une instance qui tourne comprise. Le changement de règle de 2024 a justement supprimé la gratuité de l'EIP attachée. Depuis le 1er février 2024, il y a un tarif de 0,005 USD par IP par heure pour toutes les adresses IPv4 publiques, qu'elles soient attachées à un service ou non.

### 3 Snapshots (volume source disparu)
```bash
aws ec2 describe-snapshots \
  --region eu-west-3 \
  --owner-ids self \
  --query 'Snapshots[*].{ID:SnapshotId,Vol:VolumeId,Size:VolumeSize,Date:StartTime}' \
  --output table
```

### 4 Instances EC2 — état réel
```bash
aws ec2 describe-instances \
  --region eu-west-3 \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```
> Donne le parc compute, les types (= taille = coût), et le tag Name (dev/staging/prod ?).
> Cherche des instances `stopped` (paient quand même les EBS attachés) et des types
> surdimensionnés

### 5 NAT Gateways (coût fixe sournois)
```bash
aws ec2 describe-nat-gateways \
  --region eu-west-3 \
  --query 'NatGateways[*].{ID:NatGatewayId,State:State,VPC:VpcId}' \
  --output table
```
> ~0.048 USD/h à Paris dès qu'il existe, soit ~35 USD/mois par NAT, même inutilisé.
> Croise avec Cost Explorer : `NatGateway-Hours` présent mais `NatGateway-Bytes`
> quasi nul = NAT qui tourne pour rien. Quick win classique.
>

### 6 Lambda — comprendre à quoi elles servent (sans voir le code)
La deny policy bloque `lambda:GetFunction` = le **code** ne peut être téléchargé
mais on voit: 

```bash
aws lambda list-functions \
  --region eu-west-3 \
  --query 'Functions[*].{Name:FunctionName,Runtime:Runtime,Mem:MemorySize,Timeout:Timeout}' \
  --output table
```
> `list-functions` = liste + runtime + mémoire + timeout. Souvent le nom suffit à
> deviner le rôle (`pdf-ocr-trigger`, `invoice-extract`...). Mémoire × durée × invocations
> = le coût

```bash
aws lambda list-event-source-mappings \
  --region eu-west-3 \
  --query 'EventSourceMappings[*].{Func:FunctionArn,Source:EventSourceArn,State:State}' \
  --output table
```
> Les **triggers** : déclenchée par S3 (upload doc) ? SQS ? Confirme le pattern
> pipeline upload→OCR de ta prep. `GetFunctionConfiguration` (non bloqué a priori)
> donne en plus le rôle IAM et les variables d'env non sensibles.

### 7 Log groups CloudWatch sans rétention. 

```bash
aws logs describe-log-groups \
  --region eu-west-3 \
  --query 'logGroups[?retentionInDays==`null`].[logGroupName,storedBytes]' \
  --output table
```

retentionInDays=null = rétention infinie = stockage qui gonfle sans fin. Quick win direct : poser une expiration.

### 8 Volumes EBS attachés à des instances stopped
```bash
aws ec2 describe-instances \
  --region eu-west-3 \
  --filters "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Type:InstanceType,Name:Tags[?Key==`Name`]|[0].Value,Since:StateTransitionReason,Volumes:BlockDeviceMappings[*].Ebs.VolumeId}' \
  --output table
```
> Instance `stopped` = pas de coût compute, mais les EBS attachés restent facturés au Go/mois.
> Une instance éteinte depuis des mois avec un gros volume root = gaspillage silencieux.
> `Since` donne la date d'arrêt (texte "User initiated") pour prioriser : éteinte depuis 2 jours
> vs 8 mois. Croise les `VolumeId` avec leur taille (section 1) pour chiffrer.

### 9 mais aussi...

#### IPv4 publiques détaillées

```bash
aws ec2 describe-addresses --region eu-west-3 \
  --query 'Addresses[*].{IP:PublicIp,Assoc:AssociationId,Instance:InstanceId,Type:NetworkBorderGroup}' --output table
``` 

Ça liste toutes les EIP et leur attachement. incluent aussi les IP auto-assignées aux instances/NAT/ALB, que tu ne vois pas toutes ici. 

La vraie chasse IPv4 passe par AWS IPAM "Public IP insights" (console), plus complet que le CLI.

#### NAT — vérifier s'ils servent.  Confirme le compte exact et croise avec le trafic.

```bash
aws ec2 describe-nat-gateways --region eu-west-3 \
  --query 'NatGateways[?State==`available`].{ID:NatGatewayId,VPC:VpcId,Subnet:SubnetId}' --output table
```

Puis comptes les VPC : X NAT pour combien de VPC ? Si 1 seul VPC multi-AZ, bcp de NAT c'est suspect.

#### Aurora ServerlessV2 — le plancher ACU.

```bash
aws rds describe-db-clusters --region eu-west-3 \
  --query 'DBClusters[*].{ID:DBClusterIdentifier,Engine:Engine,MinACU:ServerlessV2ScalingConfiguration.MinCapacity,MaxACU:ServerlessV2ScalingConfiguration.MaxCapacity,MultiAZ:MultiAZ}' --output table
```

Le MinACU est exactement ce qui tourne H24. S'il est à 2 ou 4 alors que la nuit est morte, voilà le gras.

EBS — ajouter la taille pour chiffrer direct. il faut le total Go × prix.

Elastic Load Balancers — combien, quel type. 

```bash
aws elbv2 describe-load-balancers --region eu-west-3 \
  --query 'LoadBalancers[*].{Name:LoadBalancerName,Type:Type,State:State.Code,Scheme:Scheme}' --output table
```

Un ALB inutilisé (0 cible saine) coûte quand même son heure fixe.