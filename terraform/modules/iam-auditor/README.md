# Module `iam-auditor`

Creates the IAM user `finops-auditor` and all its customer managed policies,
then attaches the required AWS managed policies.

Optional client deliverable — alternative to the existing CloudFormation template.
Must be applied in the target account by a user with sufficient IAM permissions.

Source of truth: `iam/annexe-a-iam-permissions.md`.

## Profiles

| Profile | Usage | Attached policies |
|---------|-------|-------------------|
| `admin` (default) | Initial FinOps infrastructure setup | `Finops-deny-data-access`, `Finops-allow-audit`, `Finops-optin`, `Finops-setup`, `Finops-cloudwatch-agent`, `ReadOnlyAccess`, `AWSBillingReadOnlyAccess`, `AWSSupportAccess` |
| `audit` | Read-only audit + Athena queries | `Finops-deny-data-access`, `Finops-allow-audit`, `ReadOnlyAccess`, `AWSBillingReadOnlyAccess` |

## Optional policies

| Variable | Policy created | Note |
|----------|----------------|------|
| `enable_iam_policy = true` | `Finops-IAM` | Allows IAM policy modification -- enable only when explicitly needed |
| `enable_tagging_policy = true` | `Finops-tagging-all-resources` | Multi-service tagging across all account resources |

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `user_name` | `string` | `finops-auditor` | Name of the IAM user created. |
| `profile` | `string` | `admin` | IAM profile: `audit` or `admin`. |
| `enable_iam_policy` | `bool` | `false` | Create and attach `Finops-IAM`. |
| `enable_tagging_policy` | `bool` | `false` | Create and attach `Finops-tagging-all-resources`. |
| `resource_prefix` | `string` | `""` | Optional prefix prepended to the user name and all policy names (hyphen separator, e.g. `"test"` gives `"test-finops-auditor"`, `"test-Finops-allow-audit"`). Athena and Glue ARNs inside the policies are updated accordingly. |
| `tags` | `map(string)` | `{}` | Tags applied to the IAM user and all customer managed policies. |

## Outputs

| Output | Description |
|--------|-------------|
| `user_arn` | IAM user ARN |
| `user_name` | IAM user name |
| `attached_policy_arns` | Map `{key => ARN}` of all attached policies |

## Example

```hcl
module "iam_auditor" {
  source = "../modules/iam-auditor"

  profile = "admin"
}
```

## What this module does NOT do

- **Does not activate IAM billing access** -- root action only, AWS console
  (Account -> IAM user and role access to Billing Information -> Activate IAM Access).
  Without this step, the auditor sees no billing data even with the correct policies.

- **Does not create the console password** -- perform manually after `terraform apply`:
  IAM -> Users -> `finops-auditor` -> Security credentials -> Console sign-in -> Enable.
  Uncheck "Users must create a new password at next sign-in".

- **Does not create access keys** -- perform manually:
  IAM -> Users -> `finops-auditor` -> Security credentials -> Access keys -> Create access key.
  Use case: "Other". Download the CSV immediately (Secret Key cannot be retrieved later).

- **Does not transmit credentials** -- use a one-time secret link
  (e.g. onetimesecret.com). Never send by email in plain text.

Full procedure: `iam/annexe-a-iam-permissions.md`.

## Notes

- The module uses `data.aws_caller_identity` to retrieve the account ID and substitute it
  in scoped ARNs. No account ID variable needed.
- The SSM restriction in `Finops-deny-data-access` uses a region wildcard (`*`) --
  valid for multi-region deployments without an extra variable.