data "aws_caller_identity" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  prefix_dash    = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
  prefix_under   = var.resource_prefix != "" ? "${var.resource_prefix}_" : ""
  user_name_full = "${local.prefix_dash}${var.user_name}"

  # ARNs of conditional policies, null if not created
  optin_arn            = one([for p in aws_iam_policy.optin : p.arn])
  setup_arn            = one([for p in aws_iam_policy.setup : p.arn])
  cloudwatch_agent_arn = one([for p in aws_iam_policy.cloudwatch_agent : p.arn])
  iam_arn              = one([for p in aws_iam_policy.iam : p.arn])
  tagging_arn          = one([for p in aws_iam_policy.tagging : p.arn])

  all_policy_arns = merge(
    {
      deny_data_access         = aws_iam_policy.deny_data_access.arn
      allow_audit              = aws_iam_policy.allow_audit.arn
      read_only_access         = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      billing_read_only_access = "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"
    },
    var.profile == "admin" ? {
      optin            = aws_iam_policy.optin["enabled"].arn
      setup            = aws_iam_policy.setup["enabled"].arn
      cloudwatch_agent = aws_iam_policy.cloudwatch_agent["enabled"].arn
      support_access   = "arn:aws:iam::aws:policy/AWSSupportAccess"
    } : {},
    var.enable_iam_policy ? { iam = aws_iam_policy.iam["enabled"].arn } : {},
    var.enable_tagging_policy ? { tagging = aws_iam_policy.tagging["enabled"].arn } : {},
  )
}

# --- IAM user ---

resource "aws_iam_user" "finops" {
  name = local.user_name_full
  tags = var.tags
}

# --- Always-created policies (audit + admin) ---

resource "aws_iam_policy" "deny_data_access" {
  name        = "${local.prefix_dash}Finops-deny-data-access"
  description = "Deny access to sensitive application data; allows only FinOps buckets and the CloudWatch Agent parameter."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyS3GetObjectExceptFinopsBuckets"
        Effect = "Deny"
        Action = "s3:GetObject"
        NotResource = [
          "arn:aws:s3:::*cur-exports*/*",
          "arn:aws:s3:::*athena-results*/*",
          "arn:aws:s3:::*compute-optimizer-results*/*",
          "arn:aws:s3:::*s3-inventory*/*",
          "arn:aws:s3:::*s3-logging*/*",
          "arn:aws:s3:::*s3-finops*/*",
        ]
      },
      {
        Sid    = "DenySensitiveDataAccess"
        Effect = "Deny"
        Action = [
          "rds-db:Connect",
          "secretsmanager:GetSecretValue",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "lambda:GetFunction",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
        ]
        Resource = "*"
      },
      {
        # Restricts SSM reads to CloudWatch Agent parameters only
        # Region is the client infra region (var.aws_region) — adjust for multi-region
        Sid    = "DenySSMGetParameterExceptCloudWatchAgent"
        Effect = "Deny"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        NotResource = "arn:aws:ssm:*:${local.account_id}:parameter/AmazonCloudWatchAgent*"
      },
    ]
  })
  tags = var.tags
}

resource "aws_iam_policy" "allow_audit" {
  name        = "${local.prefix_dash}Finops-allow-audit"
  description = "FinOps audit permissions: Athena queries in finops workgroups, Cost Explorer/COH/BCM read access, Compute Optimizer export."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaRunQueriesInWorkgroup"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:CreateNamedQuery",
        ]
        Resource = [
          "arn:aws:athena:us-east-1:${local.account_id}:workgroup/${local.prefix_under}finops-cur",
          "arn:aws:athena:*:${local.account_id}:workgroup/${local.prefix_under}finops-s3",
        ]
      },
      {
        Sid    = "S3AthenaComputeOptimizerResultsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        Resource = [
          "arn:aws:s3:::*athena-results*/*",
          "arn:aws:s3:::*compute-optimizer-results*/*",
        ]
      },
      {
        Sid    = "ResourceExplorerRead"
        Effect = "Allow"
        Action = [
          "resource-explorer-2:Search",
          "resource-explorer-2:GetView",
          "resource-explorer-2:ListViews",
          "resource-explorer-2:ListIndexes",
          "resource-explorer-2:GetIndex",
          "resource-explorer-2:ListSupportedResourceTypes",
          "resource-explorer-2:BatchGetView",
        ]
        Resource = "*"
      },
      {
        Sid    = "BillingRecentNamespacesRead"
        Effect = "Allow"
        Action = [
          "bcm-data-exports:List*",
          "bcm-data-exports:Get*",
          "bcm-recommended-actions:List*",
          "cost-optimization-hub:List*",
          "cost-optimization-hub:Get*",
        ]
        Resource = "*"
      },
      {
        Sid    = "CostExplorerPurchaseAnalyzer"
        Effect = "Allow"
        Action = [
          "ce:StartCommitmentPurchaseAnalysis",
          "ce:GetCommitmentPurchaseAnalysis",
          "ce:ListCommitmentPurchaseAnalyses",
          "ce:GetSavingsPlansPurchaseRecommendation",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetRightsizingRecommendation",
          "ce:StartSavingsPlansPurchaseRecommendationGeneration",
        ]
        Resource = "*"
      },
      {
        Sid    = "ComputeOptimizerExport"
        Effect = "Allow"
        Action = [
          "compute-optimizer:ExportEC2InstanceRecommendations",
          "compute-optimizer:ExportEBSVolumeRecommendations",
          "compute-optimizer:ExportLambdaFunctionRecommendations",
          "compute-optimizer:ExportECSServiceRecommendations",
          "compute-optimizer:ExportRDSDatabaseRecommendations",
          "compute-optimizer:ExportIdleRecommendations",
          "compute-optimizer:ExportAutoScalingGroupRecommendations",
          "compute-optimizer:ExportLicenseRecommendations",
          "compute-optimizer:DescribeRecommendationExportJobs",
        ]
        Resource = "*"
      },
      {
        Sid    = "FinopsCloudTrailInvestigation"
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
        ]
        Resource = "arn:aws:cloudtrail:*:${local.account_id}:trail/*finops*"
      },
    ]
  })
  tags = var.tags
}

# --- Admin profile policies ---

resource "aws_iam_policy" "optin" {
  for_each    = var.profile == "admin" ? toset(["enabled"]) : toset([])
  name        = "${local.prefix_dash}Finops-optin"
  description = "Enable FinOps services: Resource Explorer, Compute Optimizer, Cost Optimization Hub, CUR 2.0."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateServiceLinkedRolesForFinOpsServices"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "resource-explorer-2.amazonaws.com",
              "compute-optimizer.amazonaws.com",
              "cost-optimization-hub.bcm.amazonaws.com",
            ]
          }
        }
      },
      {
        Sid    = "DataExportsCreate"
        Effect = "Allow"
        Action = [
          "bcm-data-exports:CreateExport",
          "bcm-data-exports:ListExports",
          "bcm-data-exports:GetExport",
          "bcm-data-exports:TagResource",
          "bcm-data-exports:UntagResource",
          "bcm-data-exports:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid      = "CurLegacyRequiredByCur2Wizard"
        Effect   = "Allow"
        Action   = "cur:PutReportDefinition"
        Resource = "*"
      },
      {
        Sid      = "ResourceExplorerOptIn"
        Effect   = "Allow"
        Action   = "resource-explorer-2:*"
        Resource = "*"
      },
      {
        Sid    = "ComputeOptimizerOptIn"
        Effect = "Allow"
        Action = [
          "compute-optimizer:UpdateEnrollmentStatus",
          "compute-optimizer:GetEnrollmentStatus",
        ]
        Resource = "*"
      },
      {
        Sid    = "CostOptimizationHubOptIn"
        Effect = "Allow"
        Action = [
          "cost-optimization-hub:UpdateEnrollmentStatus",
          "cost-optimization-hub:ListEnrollmentStatuses",
          "cost-optimization-hub:UpdatePreferences",
          "cost-optimization-hub:GetPreferences",
        ]
        Resource = "*"
      },
    ]
  })
  tags = var.tags
}

resource "aws_iam_policy" "setup" {
  for_each    = var.profile == "admin" ? toset(["enabled"]) : toset([])
  name        = "${local.prefix_dash}Finops-setup"
  description = "Create FinOps audit infrastructure: S3 buckets, Athena workgroups, Glue tables, cost allocation tags."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConfigureFinopsBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucket",
        ]
        Resource = [
          "arn:aws:s3:::*cur-exports*",
          "arn:aws:s3:::*compute-optimizer-results*",
          "arn:aws:s3:::*athena-results*",
          "arn:aws:s3:::*s3-inventory*",
          "arn:aws:s3:::*s3-logging*",
          "arn:aws:s3:::*finops*",
        ]
      },
      {
        Sid    = "CreateAthenaWorkgroup"
        Effect = "Allow"
        Action = [
          "athena:CreateWorkGroup",
          "athena:UpdateWorkGroup",
          "athena:TagResource",
          "athena:GetWorkGroup",
          "athena:DeleteWorkGroup"
        ]
        Resource = "arn:aws:athena:*:${local.account_id}:workgroup/*finops*"
      },
      {
        Sid    = "GlueCatalogingWrite"
        Effect = "Allow"
        Action = [
          "glue:CreateDatabase",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:BatchCreatePartition",
          "glue:DeleteDatabase"
        ]
        Resource = [
          "arn:aws:glue:*:*:catalog",
          "arn:aws:glue:*:*:database/*finops*",
          "arn:aws:glue:*:*:table/*finops*/*",
          "arn:aws:glue:*:*:userDefinedFunction/*finops*/*"
        ]
      },
      {
        Sid    = "CostExplorerConfig"
        Effect = "Allow"
        Action = [
          "ce:ListCostAllocationTags",
          "ce:UpdateCostAllocationTagsStatus",
          "ce:UpdatePreferences",
          "ce:GetPreferences",
          "ce:CreateReport",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3AccessLogging"
        Effect = "Allow"
        Action = [
          "s3:PutInventoryConfiguration",
          "s3:PutBucketLogging",
          "s3:GetBucketLogging",
        ]
        Resource = "arn:aws:s3:::*"
      },
    ]
  })
  tags = var.tags
}

resource "aws_iam_policy" "cloudwatch_agent" {
  for_each    = var.profile == "admin" ? toset(["enabled"]) : toset([])
  name        = "${local.prefix_dash}Finops-cloudwatch-agent"
  description = "Deploy and configure CloudWatch Agent via SSM: EC2 role, instance profile, SSM parameter."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMCloudWatchAgentDeploy"
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "iam:ListAttachedRolePolicies",
          "iam:GetInstanceProfile",
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMSendCommandCWAgentOnly"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ssm:*:*:document/AWS-ConfigureAWSPackage",
          "arn:aws:ssm:*:*:document/AmazonCloudWatch-ManageAgent",
          "arn:aws:ec2:*:*:instance/*",
        ]
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:AddTagsToResource",
          "ssm:DeleteParameter",
        ]
        Resource = "arn:aws:ssm:*:*:parameter/AmazonCloudWatchAgent*"
      },
      {
        Sid    = "CreateCWAgentRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:PassRole",
          "iam:TagRole",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteRole",
          "iam:DeleteInstanceProfile",
        ]
        Resource = [
          "arn:aws:iam::*:role/*CloudWatchAgent*",
          "arn:aws:iam::*:instance-profile/*CloudWatchAgent*",
        ]
      },
      {
        Sid    = "AttachCWAgentPoliciesOnly"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
        ]
        Resource = "arn:aws:iam::*:role/*",
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
              "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
            ]
          }
        }
      },
      {
        Sid    = "EC2InstanceProfile"
        Effect = "Allow"
        Action = [
          "ec2:AssociateIamInstanceProfile",
          "ec2:DescribeIamInstanceProfileAssociations",
        ]
        Resource = "*"
      },
    ]
  })
  tags = var.tags
}

# --- Optional policies ---

resource "aws_iam_policy" "iam" {
  for_each    = var.enable_iam_policy ? toset(["enabled"]) : toset([])
  name        = "${local.prefix_dash}Finops-IAM"
  description = "⚠️ Allows creation/modification of customer managed policies and their attachment to the FinOps user. Elevated privilege."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateAuditUser"
        Effect = "Allow"
        Action = [
          "iam:CreateUser",
          "iam:CreateLoginProfile",
          "iam:CreateAccessKey",
          "iam:TagUser",
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/${local.user_name_full}"
      },
      {
        Sid    = "CreateAndAttachPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/*"
      },
      {
        Sid    = "AttachPoliciesToAuditUser"
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/${local.user_name_full}"
      },
    ]
  })
  tags = var.tags
}

resource "aws_iam_policy" "tagging" {
  for_each    = var.enable_tagging_policy ? toset(["enabled"]) : toset([])
  name        = "${local.prefix_dash}Finops-tagging-all-resources"
  description = "Multi-service tagging across all account resources."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TaggingAPIAllResources"
        Effect = "Allow"
        Action = [
          "tag:TagResources",
          "tag:UntagResources",
        ]
        Resource = "*"
      },
      {
        Sid    = "ServiceSpecificTagging"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags", "ec2:DeleteTags",
          "ecs:TagResource", "ecs:UntagResource",
          "eks:TagResource", "eks:UntagResource",
          "ecr:TagResource", "ecr:UntagResource",
          "lambda:TagResource", "lambda:UntagResource",
          "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
          "s3:PutBucketTagging", "s3:PutObjectTagging", "s3:DeleteObjectTagging",
          "s3:PutObjectVersionTagging", "s3:DeleteObjectVersionTagging",
          "elasticache:AddTagsToResource", "elasticache:RemoveTagsFromResource",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
          "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
          "mq:CreateTags", "mq:DeleteTags",
          "logs:TagLogGroup", "logs:UntagLogGroup", "logs:TagResource", "logs:UntagResource",
          "cloudwatch:TagResource", "cloudwatch:UntagResource",
          "dynamodb:TagResource", "dynamodb:UntagResource",
          "sns:TagResource", "sns:UntagResource",
          "sqs:TagQueue", "sqs:UntagQueue",
          "kinesis:AddTagsToStream", "kinesis:RemoveTagsFromStream",
          "firehose:TagDeliveryStream", "firehose:UntagDeliveryStream",
          "kms:TagResource", "kms:UntagResource",
          "secretsmanager:TagResource", "secretsmanager:UntagResource",
          "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource",
          "glue:TagResource", "glue:UntagResource",
          "athena:TagResource", "athena:UntagResource",
          "cloudfront:TagResource", "cloudfront:UntagResource",
          "route53:ChangeTagsForResource",
          "route53resolver:TagResource", "route53resolver:UntagResource",
          "bedrock:TagResource", "bedrock:UntagResource",
          "sagemaker:AddTags", "sagemaker:DeleteTags",
          "cognito-idp:TagResource", "cognito-idp:UntagResource",
          "cognito-identity:TagResource", "cognito-identity:UntagResource",
          "events:TagResource", "events:UntagResource",
          "states:TagResource", "states:UntagResource",
          "apigateway:TagResource", "apigateway:UntagResource",
          "appsync:TagResource", "appsync:UntagResource",
          "es:AddTags", "es:RemoveTags",
          "kafka:TagResource", "kafka:UntagResource",
          "backup:TagResource", "backup:UntagResource",
          "wafv2:TagResource", "wafv2:UntagResource",
          "network-firewall:TagResource", "network-firewall:UntagResource",
          "codecommit:TagResource", "codecommit:UntagResource",
          "codepipeline:TagResource", "codepipeline:UntagResource",
          "codedeploy:TagResource", "codedeploy:UntagResource",
          "cloudtrail:AddTags", "cloudtrail:RemoveTags",
          "config:TagResource", "config:UntagResource",
          "iam:TagUser", "iam:UntagUser",
          "iam:TagRole", "iam:UntagRole",
          "iam:TagPolicy", "iam:UntagPolicy",
        ]
        Resource = "*"
      },
    ]
  })
  tags = var.tags
}

# --- Attachments ---

resource "aws_iam_user_policy_attachment" "policies" {
  for_each   = local.all_policy_arns
  user       = aws_iam_user.finops.name
  policy_arn = each.value
}
