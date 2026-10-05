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

---

## Étape 1 — Créer les policies et l'utilisateur IAM finops

> **Ordre recommandé :** créer d'abord les customer managed policies
> puis le(s) finops user(s) en  attachant les policies en une fois — plus propre que créer le user
> puis revenir éditer les policies. Les access keys en dernier.


### Les policies pour la création de l'infra nécessaires à la mission

>  ces 5 customer policies (A B C D E) couvrent exactement le périmètre nécessaire des outils finops
>  créer les policies unes à une

Console AWS → **IAM** → **Policies** → **Create policy** → onglet **JSON**


### NON-REQUIS - Policy A — `Finops-IAM` (optionnelle)

> ⚠️ Le détenteur de cette policy peut créer/modifier/supprimer n'importe quelle customer managed policy du compte et l'attacher au user finops-auditor


Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAuditUser",
      "Effect": "Allow",
      "Action": [
        "iam:CreateUser",
        "iam:CreateLoginProfile",
        "iam:CreateAccessKey",
        "iam:TagUser"
      ],
      "Resource": "arn:aws:iam::*:user/finops-auditor"          # Remplacer * par [ACCOUNT ID]
    },
    {
      "Sid": "CreateAndAttachPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:ListPolicyVersions",
        "iam:TagPolicy"
      ],
      "Resource": "arn:aws:iam::*:policy/*"                    # Remplacer * par [ACCOUNT ID]
    },
    {
      "Sid": "AttachPoliciesToAuditUser",
      "Effect": "Allow",
      "Action": [
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy"
      ],
      "Resource": "arn:aws:iam::*:user/finops-auditor"         # Remplacer * par [ACCOUNT ID]
    }
  ]
}
```

**Next** → Policy name : `Finops-IAM` → **Create policy**

### Policy B — `Finops-tagging-all-resources` (optionnelle)

Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TaggingAPIAllResources",
      "Effect": "Allow",
      "Action": [
        "tag:TagResources",
        "tag:UntagResources"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ServiceSpecificTagging",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ecs:TagResource",
        "ecs:UntagResource",
        "eks:TagResource",
        "eks:UntagResource",
        "ecr:TagResource",
        "ecr:UntagResource",
        "lambda:TagResource",
        "lambda:UntagResource",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "s3:PutBucketTagging",
        "s3:PutObjectTagging",
        "s3:DeleteObjectTagging",
        "s3:PutObjectVersionTagging",
        "s3:DeleteObjectVersionTagging",
        "elasticache:AddTagsToResource",
        "elasticache:RemoveTagsFromResource",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "mq:CreateTags",
        "mq:DeleteTags",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "logs:TagResource",
        "logs:UntagResource",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "sns:TagResource",
        "sns:UntagResource",
        "sqs:TagQueue",
        "sqs:UntagQueue",
        "kinesis:AddTagsToStream",
        "kinesis:RemoveTagsFromStream",
        "firehose:TagDeliveryStream",
        "firehose:UntagDeliveryStream",
        "kms:TagResource",
        "kms:UntagResource",
        "secretsmanager:TagResource",
        "secretsmanager:UntagResource",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "glue:TagResource",
        "glue:UntagResource",
        "athena:TagResource",
        "athena:UntagResource",
        "cloudfront:TagResource",
        "cloudfront:UntagResource",
        "route53:ChangeTagsForResource",
        "route53resolver:TagResource",
        "route53resolver:UntagResource",
        "bedrock:TagResource",
        "bedrock:UntagResource",
        "sagemaker:AddTags",
        "sagemaker:DeleteTags",
        "cognito-idp:TagResource",
        "cognito-idp:UntagResource",
        "cognito-identity:TagResource",
        "cognito-identity:UntagResource",
        "events:TagResource",
        "events:UntagResource",
        "states:TagResource",
        "states:UntagResource",
        "apigateway:TagResource",
        "apigateway:UntagResource",
        "appsync:TagResource",
        "appsync:UntagResource",
        "es:AddTags",
        "es:RemoveTags",
        "kafka:TagResource",
        "kafka:UntagResource",
        "backup:TagResource",
        "backup:UntagResource",
        "wafv2:TagResource",
        "wafv2:UntagResource",
        "network-firewall:TagResource",
        "network-firewall:UntagResource",
        "codecommit:TagResource",
        "codecommit:UntagResource",
        "codepipeline:TagResource",
        "codepipeline:UntagResource",
        "codedeploy:TagResource",
        "codedeploy:UntagResource",
        "cloudtrail:AddTags",
        "cloudtrail:RemoveTags",
        "config:TagResource",
        "config:UntagResource",
        "iam:TagUser",
        "iam:UntagUser",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

**Next** → Policy name : `Finops-tagging-all-resources` → **Create policy**


### Policy C — `Finops-optin` (activation des services)


Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateServiceLinkedRolesForFinOpsServices",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": [
            "resource-explorer-2.amazonaws.com",
            "compute-optimizer.amazonaws.com",
            "cost-optimization-hub.bcm.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DataExportsCreate",
      "Effect": "Allow",
      "Action": [
        "bcm-data-exports:CreateExport",
        "bcm-data-exports:ListExports",
        "bcm-data-exports:GetExport",
        "bcm-data-exports:TagResource",
        "bcm-data-exports:UntagResource",
        "bcm-data-exports:ListTagsForResource"
      ],
      "Resource": "*"
    },

    {
      "Sid": "CurLegacyRequiredByCur2Wizard",
      "Effect": "Allow",
      "Action": "cur:PutReportDefinition",
      "Resource": "*"
    },
    {
      "Sid": "ResourceExplorerOptIn",
      "Effect": "Allow",
      "Action": "resource-explorer-2:*",
      "Resource": "*"
    },
    {
      "Sid": "ComputeOptimizerOptIn",
      "Effect": "Allow",
      "Action": [
        "compute-optimizer:UpdateEnrollmentStatus",
        "compute-optimizer:GetEnrollmentStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CostOptimizationHubOptIn",
      "Effect": "Allow",
      "Action": [
        "cost-optimization-hub:UpdateEnrollmentStatus",
        "cost-optimization-hub:ListEnrollmentStatuses",
        "cost-optimization-hub:UpdatePreferences",
        "cost-optimization-hub:GetPreferences"
      ],
      "Resource": "*"
    }
  ]
}
```

**Next** → Policy name : `Finops-optin` → **Create policy**

### Policy D — `Finops-setup` (création de l'infra d'audit)

Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    	{
			"Sid": "ConfigureFinopsBucket",
			"Effect": "Allow",
			"Action": [
				"s3:CreateBucket",
				"s3:GetBucketPolicy",
				"s3:PutBucketPolicy",
				"s3:PutBucketPublicAccessBlock",
				"s3:GetBucketAcl",
				"s3:PutBucketAcl",
        "s3:PutEncryptionConfiguration",
        "s3:PutLifecycleConfiguration",
        "s3:DeleteBucketPolicy",
        "s3:DeleteBucket"
			],
			"Resource": [ 
      "arn:aws:s3:::*cur-exports*",
			"arn:aws:s3:::*compute-optimizer-results*",
      "arn:aws:s3:::*athena-results*",
      "arn:aws:s3:::*s3-inventory*",
      "arn:aws:s3:::*s3-logging*",
      "arn:aws:s3:::*finops*"

			]
		},
    {
      "Sid": "CreateAthenaWorkgroup",
      "Effect": "Allow",
      "Action": [
        "athena:CreateWorkGroup",
        "athena:UpdateWorkGroup",
        "athena:TagResource",
        "athena:GetWorkGroup",
        "athena:DeleteWorkGroup"
      ],
      "Resource": "arn:aws:athena:*:*:workgroup/finops*"    # Remplacer le deuxieme * par [ACCOUNT ID]
    },
    {
      "Sid": "GlueCatalogingWrite",
      "Effect": "Allow",
      "Action": [
        "glue:CreateDatabase",
        "glue:CreateTable",
        "glue:UpdateTable",
        "glue:DeleteTable",
        "glue:BatchCreatePartition",
        "glue:DeleteDatabase"
      ],
      "Resource": [
        "arn:aws:glue:*:*:catalog",
        "arn:aws:glue:*:*:database/finops_*",
        "arn:aws:glue:*:*:table/finops_*/*",
        "arn:aws:glue:*:*:userDefinedFunction/finops_*/*"
      ]
    },
    {
      "Sid": "CostExplorerConfig",
      "Effect": "Allow",
      "Action": [
        "ce:ListCostAllocationTags",
        "ce:UpdateCostAllocationTagsStatus",
        "ce:UpdatePreferences",
        "ce:GetPreferences",
        "ce:CreateReport"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3AccessLogging",
      "Effect": "Allow",
      "Action": [ 
        "s3:PutInventoryConfiguration",
        "s3:PutBucketLogging",
        "s3:GetBucketLogging"
  ],
      "Resource": "arn:aws:s3:::*"
   }
  ]
}
```

**Next** → Policy name : `Finops-setup` → **Create policy**

> `ce:UpdateCostAllocationTagsStatus` pour activer les cost allocation tags (Non rétroactif) 
> `ce:updatePreferences` et `ce:GetPreferences` pour activer Resource-level data at daily granularity

### NON REQUIS - Policy E — `Finops-cloudwatch-agent` 

Remplacer tout le contenu par :

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SSMCloudWatchAgentDeploy",
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeInstanceInformation",
                "iam:ListAttachedRolePolicies",
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
                "arn:aws:iam::*:role/*CloudWatchAgent*",
                "arn:aws:iam::*:instance-profile/*CloudWatchAgent*"
            ]
        },
        {
            "Sid": "AttachCWAgentPoliciesOnly",
            "Effect": "Allow",
            "Action": [
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy"
            ],
            "Resource": "arn:aws:iam::*:role/*",
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

> Caution :  IAM matches case-sensitively. `CloudWatchAgent`

**Next** → Policy name : `Finops-cloudwatch-agent` → **Create policy**

---

### Policy F — `Finops-deny-data-access` (Deny)

Cette policy bloque l'accès aux données applicatives sensibles,
tout en conservant l'accès aux buckets finops et paramètres nécessaires à la mission

1. Console AWS → **IAM** → **Policies** → **Create policy** → onglet **JSON**
2. Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyS3GetObjectExceptFinopsBuckets",
      "Effect": "Deny",
      "Action": "s3:GetObject",
      "NotResource": [
        "arn:aws:s3:::*cur-exports*/*",
        "arn:aws:s3:::*athena-results*/*",
        "arn:aws:s3:::*compute-optimizer-results*/*",
        "arn:aws:s3:::*s3-inventory*/*",
        "arn:aws:s3:::*finops*/*",
        "arn:aws:s3:::*s3-logging*/*"
      ]
    },
    {
      "Sid": "DenySensitiveDataAccess",
      "Effect": "Deny",
      "Action": [
        "rds-db:Connect",
        "secretsmanager:GetSecretValue",
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem",
        "lambda:GetFunction",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    },
		{
			"Sid": "DenySSMGetParameterExceptCloudWatchAgent",
			"Effect": "Deny",
			"Action": [
				"ssm:GetParameter",
				"ssm:GetParameters",
				"ssm:GetParametersByPath"
			],
			 "NotResource": "arn:aws:ssm:*:*:parameter/AmazonCloudWatchAgent*" # Remplacer le premier * par [ACCOUNT ID]
		}
  ]
}
```

**Next** → Policy name : `Finops-deny-data-access` → **Create policy**


> **Ce que cette policy fait :**
> - Interdit `s3:GetObject` sur tous les buckets, **sauf** les 3 buckets finops
> - Interdit la connexion aux bases de données, secrets, code Lambda, logs applicatifs
> - Interdit la lecture de paramètres SSM sauf pour la config du CloudWatch agent


### Policy G — `Finops-allow-audit` (Allow)

1. Console AWS → **IAM** → **Policies** → **Create policy** → onglet **JSON**
2. Remplacer tout le contenu par :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AthenaRunQueriesInWorkgroup",
      "Effect": "Allow",
      "Action": [
        "athena:StartQueryExecution",
        "athena:StopQueryExecution",
        "athena:CreateNamedQuery"
      ],
      "Resource": [
        "arn:aws:athena:us-east-1:*:workgroup/finops-cur",      # Remplacer * par [ACCOUNT ID] 12 CHIFFRES
        "arn:aws:athena:*:*:workgroup/finops-s3"
                  ]        
    },
    {
      "Sid": "S3AthenaComputeOptimizerResultsWrite",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
     "Resource": [
                "arn:aws:s3:::*athena-results*/*",
                "arn:aws:s3:::*compute-optimizer-results*/*"
            ]
    },
    {
      "Sid": "ResourceExplorerRead",
      "Effect": "Allow",
      "Action": [
        "resource-explorer-2:Search",
        "resource-explorer-2:GetView",
        "resource-explorer-2:ListViews",
        "resource-explorer-2:ListIndexes",
        "resource-explorer-2:GetIndex",
        "resource-explorer-2:ListSupportedResourceTypes",
        "resource-explorer-2:BatchGetView"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BillingRecentNamespacesRead",
      "Effect": "Allow",
      "Action": [
        "bcm-data-exports:List*",
        "bcm-data-exports:Get*",
        "bcm-recommended-actions:List*",
        "cost-optimization-hub:List*",
        "cost-optimization-hub:Get*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CostExplorerPurchaseAnalyzer",
      "Effect": "Allow",
      "Action": [
        "ce:StartCommitmentPurchaseAnalysis",
        "ce:GetCommitmentPurchaseAnalysis",
        "ce:ListCommitmentPurchaseAnalyses",
        "ce:GetSavingsPlansPurchaseRecommendation",
        "ce:GetReservationPurchaseRecommendation",
        "ce:GetRightsizingRecommendation",
        "ce:StartSavingsPlansPurchaseRecommendationGeneration"
      ],
      "Resource": "*"
    },
    {
        "Sid": "ComputeOptimizerExport",
        "Effect": "Allow",
        "Action": [
        "compute-optimizer:ExportEC2InstanceRecommendations",
        "compute-optimizer:ExportEBSVolumeRecommendations",
        "compute-optimizer:ExportLambdaFunctionRecommendations",
        "compute-optimizer:ExportECSServiceRecommendations",
        "compute-optimizer:ExportRDSDatabaseRecommendations",
        "compute-optimizer:ExportIdleRecommendations",
        "compute-optimizer:ExportAutoScalingGroupRecommendations",
        "compute-optimizer:ExportLicenseRecommendations",
        "compute-optimizer:DescribeRecommendationExportJobs"
        ],
        "Resource": "*"
      },
      {
      "Sid": "FinopsCloudTrailInvestigation",
      "Effect": "Allow",
      "Action": [
        "cloudtrail:CreateTrail",
        "cloudtrail:DeleteTrail",
        "cloudtrail:StartLogging",
        "cloudtrail:StopLogging",
        "cloudtrail:GetEventSelectors",
        "cloudtrail:PutEventSelectors",
        "cloudtrail:GetTrailStatus",
        "cloudtrail:DescribeTrails"
      ],
      "Resource": "arn:aws:cloudtrail:*:*:trail/*finops*"
      }
  ]
}
```

3. **Next** → Policy name : `Finops-allow-audit` → **Create policy**

> **Ce que cette policy fait :**
> - Autorise l'exécution de requêtes Athena **uniquement** dans le workgroup `finops-cur` (us-east-1)
> - Autorise l'écriture des résultats Athena et exports Compute Optimizer dans les  buckets dédiés (`*athena-results*`, `*compute-optimizer-results*`)
> - Autorise la lecture complète de Resource Explorer (recherche multi-région, vues, index)
> - Autorise la lecture des exports CUR 2.0 (`bcm-data-exports`), des actions recommandées (`bcm-recommended-actions`) et du Cost Optimization Hub
> - Autorise les analyses d'engagement Savings Plans / RI et les recommandations de rightsizing via Cost Explorer
> - Autorise l'export des recommandations Compute Optimizer (EC2, EBS, Lambda, ECS, RDS, Auto Scaling, Idle, Licences) et le suivi des jobs d'export




### 1.1 — Créer l'utilisateur et attacher les policies

Le wizard IAM se déroule en 4 étapes : Specify user details → Set permissions → Review and create → Retrieve password.

**Step 1 — Specify user details**
1. Console AWS → **IAM** → **Users** → **Create user**
2. User name : example : **`finops-auditor`**
3. Cocher **"Provide user access to the AWS Management Console"**
   - Console password : générer automatiquement ou définir manuellement
   - Décocher "Users must create a new password at next sign-in"
4. Cliquer **Next**

**Step 2 — Set permissions**
5. Choisir **"Attach policies directly"**
   *(ne pas choisir "Add user to group")*
6. Cocher les **policies** :

OPTION A : **finops-audit**
   - `Finops-deny-data-access` (customer managed — créée ci dessus)
   - `Finops-allow-audit` (customer managed — créée ci-dessus)
   - `ReadOnlyAccess` (AWS managed — filtrer par "AWS managed - job function")
   - `AWSBillingReadOnlyAccess` (AWS managed — `cur:DescribeReportDefinitions` + billing console)


OPTION B : **finops-admin** (Recommandée pour le setup et l'activation des outils finops)
   - `Finops-deny-data-access` (customer managed — créée ci dessus)
   - `Finops-allow-audit` (customer managed — créée ci-dessus)
   - `ReadOnlyAccess` (AWS managed — filtrer par "AWS managed - job function")
   - `AWSBillingReadOnlyAccess` (AWS managed — `cur:DescribeReportDefinitions` + billing console)
et aussi:
   - `Finops-IAM -optionnel` ⚠️ 
   - `Finops-tagging-all-ressources` (customer managed) - optionnel
   - `Finops-cloudwatch-agent` (customer managed)
   - `AWSSupportAccess` (AWS managed)
   - `Finops-setup` (customer managed)
   - `Finops-optin` (customer managed)


7. **Permissions boundary** : laisser vide
8. **Tags** : passer
9. **Next**

**Step 3 — Review and create**
10. Vérifier que les policies sont attachées → **Create user**

**Step 4 — Retrieve password**
11. ⚠️ **Télécharger ou copier le mot de passe** avant de fermer — visible une seule fois

> **Note IAM :** les policies Allow se cumulent, elles ne s'écrasent pas.
> `ReadOnlyAccess` donne les droits en lecture. `Finops-allow-audit` ajoute les droits
> d'exécution Athena. La Deny s'applique en dernier et l'emporte sur tout Allow.
> Il n'y a pas de conflit entre les policies Allow.

### 1.2 — Créer les Access Keys (accès CLI/API)

> Ne pas créer les access keys pendant le wizard — le flow est moins propre.
> Revenir sur la page du user une fois créé.

1. Sur la page du user (example :`finops-auditor`) → onglet **Security credentials**
2. Section **Access keys** → **Create access key**
3. Use case : **Other** *(pas "CLI" — "Other" évite les warnings et redirections inutiles)*
4. Description tag : `FinOps audit 2026`
5. **Create access key**
6. ⚠️ **Télécharger le CSV immédiatement** — le Secret Access Key ne sera plus visible après

### 1.3 — Transmettre les credentials à l'auditeur

⚠️ Ne jamais envoyer par email en clair.

**Options recommandées :**
- [onetimesecret.com](https://onetimesecret.com) — lien à usage unique, gratuit, aucun compte nécessaire
- 1Password / Bitwarden — partage sécurisé si déjà utilisé

**Ce qu'il faut transmettre :**

1. URL de connexion console : `https://[ACCOUNT-ID].signin.aws.amazon.com/console`
2. Username : `finops-auditor`
3. Mot de passe
4. Access Key ID
5. Secret Access Key *(message séparé ou lien usage unique)*
6. Region principale à configurer : `eu-west-3` (Paris) ou la région principale de l'infra

---