#!/usr/bin/env bash
PROFILE=
OUT="s3-audit.tsv"

echo -e "Bucket\tRegion\tVersioning\tLifecycle\tSizeBytes\tObjectCount" > "$OUT"

for B in $(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[].Name' --output text); do
  # region
  REG=$(aws s3api get-bucket-location --bucket "$B" --profile "$PROFILE" --query 'LocationConstraint' --output text)
  [ "$REG" = "None" ] && REG="us-east-1"

  # versioning
  VER=$(aws s3api get-bucket-versioning --bucket "$B" --profile "$PROFILE" --query 'Status' --output text)
  [ "$VER" = "None" ] && VER="Disabled"

  # lifecycle (existe ou pas)
  if aws s3api get-bucket-lifecycle-configuration --bucket "$B" --profile "$PROFILE" >/dev/null 2>&1; then
    LC="Yes"
  else
    LC="No"
  fi

  # CloudWatch: size (StandardStorage) + object count (AllStorageTypes)
  SIZE=$(aws cloudwatch get-metric-statistics --profile "$PROFILE" --region "$REG" \
    --namespace AWS/S3 --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value="$B" Name=StorageType,Value=StandardStorage \
    --start-time "$(date -u -d '2 days ago' +%Y-%m-%dT00:00:00)" \
    --end-time "$(date -u +%Y-%m-%dT00:00:00)" \
    --period 86400 --statistics Average \
    --query 'Datapoints[-1].Average' --output text 2>/dev/null)

  CNT=$(aws cloudwatch get-metric-statistics --profile "$PROFILE" --region "$REG" \
    --namespace AWS/S3 --metric-name NumberOfObjects \
    --dimensions Name=BucketName,Value="$B" Name=StorageType,Value=AllStorageTypes \
    --start-time "$(date -u -d '2 days ago' +%Y-%m-%dT00:00:00)" \
    --end-time "$(date -u +%Y-%m-%dT00:00:00)" \
    --period 86400 --statistics Average \
    --query 'Datapoints[-1].Average' --output text 2>/dev/null)

  echo -e "$B\t$REG\t$VER\t$LC\t${SIZE:-None}\t${CNT:-None}" >> "$OUT"
done

column -t -s $'\t' "$OUT"