# Checklist
*Juin 2026*

right-sizing
- [ ] Analyse des métriques de conso réelle de chaque instance de calcul (EC2, RDS, ElastiCache...)
- [ ] identifier instances surdimensionnées qui pourraient tourner sur un type moins cher

Engagements
- [ ] Modelisation de la conso historique
- [ ] projection de la conso future
- [ ] calculer le niveau d'engagement optimal
- [ ] Reco SP et RI et Spot instances

Ressources orphelines 
- [ ] EBS non attachés
- [ ] snapshots datant de +ieurs années, 
- [ ] EIP non utilisées
- [ ] Load balancers sans cible active

Stockage et lifecycle 
- [ ] Reco de lifecycles
- [ ] recherche et identification de versions obsolètes, 
- [ ] Recherche et identiication de fragments multiparts non finalisés, 
- [ ] Recherche et identification de doublons

Data transfer
- [ ] Recherche et cartographie de transferts inter-AZ
- [ ] data processing NAT Gateway
- [ ] egress internet
- [ ] vpc endpoints pour éviter le NAT
- [ ] placements d'instances en single AZ quand c'est possible
- [ ] CloudFront pour réduire l'egress
- [ ] Compression

Optimisation compute et serverless
- [ ] instances Graviton pour les workloads comptatibles
- [ ] Spot Instances pour les workloads tolerants aux interruptions
- [ ] Migration vers Lambda ou Fargate pour ne payer que l'usage réel

CloudWatch
- [ ] monitoring, analytics,

Textract

Environnements non-prod
- [ ] environnements de développement, de recette et de staging qui tournent 24h/24, 7j/7
- [ ] reco auto-stop/start (via AWS instance Scheduler, Lambda ou simple cron)

Rapport Final

Etat des lieux
- [ ] Repartition des dépenses par service
- [ ] Repartition des dépenses par région
- [ ] Repartition des dépenses 
- [ ] Pareto :  les 20 % de services qui pèsent 80 % de la facture.

Liste des gaspillages
- [ ] chaque resource problématique nommée avec cout mensuel et cout après optimization

Reco rightsizing
- [ ] Instance par instance
- [ ] Nouveau type recommandé
- [ ] économies attendues
- [ ] niveau de risque de l'opération

Modelisation engagements
- [ ] Simulation chiffrée des Savings Plans ou Reserved Instances optimaux
- [ ] sur 1 et 3 ans,
- [ ] analyse de sensibilité.

Plan d'action
- [ ] Quick wins (zéro risque, gains immédiats) 
- [ ] optimisations moyen terme, 
- [ ] transformations structurelles. 
- [ ] estimation d'effort pour chaque action.

Synthèse financière
- [ ] Total des économies mensuelles et annuelles attendues, 
- [ ] ROI par action
- [ ] Calendrier de mise en œuvre recommandé.