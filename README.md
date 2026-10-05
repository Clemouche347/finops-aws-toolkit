# finops-aws-toolkit

AWS FinOps toolkit for auditing cloud costs on SaaS workloads.

## What's in here

- `iam-policies/` — least-privilege policies for FinOps infra setup and running (billing, Compute Optimizer, Cost Optimization Hub, CloudWatch, tagging)
- `athena-queries/` — CUR 2.0 SQL queries ready to run (cost by service, orphaned resources, CloudWatch log group analysis, NAT Gateway waste)
- `scripts/` — CLI scripts for discovery (unattached EBS, idle Elastic IPs, log groups without retention)
- `docs/` — methodology notes (what to look at, in what order, and why)

## Scope

Designed for:
- Single AWS account, 1-3 regions
- SaaS workloads (Node.js, RDS, ElastiCache, Lambda, S3)
- Monthly spend in the 1k-10k€ range
- Teams with no prior FinOps setup (no CUR, no tagging, no Savings Plans)

## Quick start

1. Deploy the IAM policies in `iam-policies/` to create a read-only FinOps user
2. Activate CUR 2.0 (Data Exports) and point it to an S3 bucket in us-east-1
3. Catalog the Athena table manually — the wizard only deposits a `create-table.sql`, it does not create the table
4. Run the queries in `athena-queries/` after the first Parquet file arrives (~24h)

## Things that aren't obvious until you actually run into them

- `MSCK REPAIR TABLE` silently fails with CUR 2.0 because S3 prefixes use uppercase (`BILLING_PERIOD=`). Use `ALTER TABLE ADD PARTITION` explicitly or `TBL PROJECTIONS`
- RAM and disk are not native CloudWatch metrics. You need the CloudWatch Agent with `append_dimensions: { InstanceId }` for Compute Optimizer to correlate memory data.
- The IAM action for RDS auth is `rds-db:connect`, not `rds:Connect`.
- Cost Explorer API costs $0.01 per paginated request. The console is free.

## Status

Work in progress. Queries and policies are added as they're built and validated on real accounts.

## License

MIT, see [LICENSE](LICENSE).