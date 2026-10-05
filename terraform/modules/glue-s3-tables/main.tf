data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.region
  prefix_under = var.resource_prefix != "" ? "${var.resource_prefix}_" : ""

  bucket_enum = join(",", var.source_bucket_names)

  # Root for access logs: [logging-bucket]/[account-id]/[region]/ (bucket added via partition projection)
  access_logs_base = "s3://${var.s3_logging_bucket_name}/${local.account_id}/${local.region}/"

  # Root for inventory: [inventory-bucket]/ (bucket added via partition projection)
  inventory_base = "s3://${var.s3_inventory_bucket_name}/"
}

# =============================================================
# Glue database — region of the analyzed buckets (provider)
# =============================================================

resource "aws_glue_catalog_database" "finops_s3" {
  name        = "${local.prefix_under}finops_s3"
  description = "FinOps — server access logs et S3 Inventory"
  tags        = var.tags
}

# =============================================================
# access_logs external table
# Fixed schema, 27 columns (RegexSerDe), stable AWS format.
# Partition projection year/month/day — no MSCK needed.
# =============================================================

# aws_glue_catalog_table does not support a tags argument
resource "aws_glue_catalog_table" "access_logs" {
  name          = "${local.prefix_under}access_logs"
  database_name = aws_glue_catalog_database.finops_s3.name
  table_type    = "EXTERNAL_TABLE"

  partition_keys {
    name = "bucket"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = local.access_logs_base
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
      parameters = {
        "input.regex" = "([^ ]*) ([^ ]*) \\[(.*?)\\] ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (-|[0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (\"[^\"]*\"|-) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)"
      }
    }

    columns {
      name = "bucketowner"
      type = "string"
    }
    columns {
      name = "bucket_name"
      type = "string"
    }
    columns {
      name = "requestdatetime"
      type = "string"
    }
    columns {
      name = "remoteip"
      type = "string"
    }
    columns {
      name = "requester"
      type = "string"
    }
    columns {
      name = "requestid"
      type = "string"
    }
    columns {
      name = "operation"
      type = "string"
    }
    columns {
      name = "key"
      type = "string"
    }
    columns {
      name = "request_uri"
      type = "string"
    }
    columns {
      name = "httpstatus"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "bytessent"
      type = "bigint"
    }
    columns {
      name = "objectsize"
      type = "bigint"
    }
    columns {
      name = "totaltime"
      type = "string"
    }
    columns {
      name = "turnaroundtime"
      type = "string"
    }
    columns {
      name = "referrer"
      type = "string"
    }
    columns {
      name = "useragent"
      type = "string"
    }
    columns {
      name = "versionid"
      type = "string"
    }
    columns {
      name = "hostid"
      type = "string"
    }
    columns {
      name = "sigv"
      type = "string"
    }
    columns {
      name = "ciphersuite"
      type = "string"
    }
    columns {
      name = "authtype"
      type = "string"
    }
    columns {
      name = "endpoint"
      type = "string"
    }
    columns {
      name = "tlsversion"
      type = "string"
    }
    columns {
      name = "accesspointarn"
      type = "string"
    }
    columns {
      name = "aclrequired"
      type = "string"
    }
    columns {
      name = "sourceregion"
      type = "string"
    }
  }

  parameters = {
    "EXTERNAL"                 = "TRUE"
    "projection.enabled"       = "true"
    "projection.bucket.type"   = "enum"
    "projection.bucket.values" = local.bucket_enum
    "projection.year.type"     = "integer"
    "projection.year.range"    = "${var.access_logs_year_start},2035"
    "projection.year.digits"   = "4"
    "projection.month.type"    = "integer"
    "projection.month.range"   = "1,12"
    "projection.month.digits"  = "2"
    "projection.day.type"      = "integer"
    "projection.day.range"     = "1,31"
    "projection.day.digits"    = "2"
    # $${bucket}/$${year}/… → ${bucket}/${year}/… in AWS, read by Athena as projection variables
    "storage.location.template" = "${local.access_logs_base}$${bucket}/$${year}/$${month}/$${day}/"
  }
}

# =============================================================
# inventory external table
# Variable schema (OpenCSVSerde + SymlinkTextInputFormat).
# Empty columns by default — populate from the fileSchema field
# of the manifest.json after the first S3 Inventory snapshot.
# =============================================================

resource "aws_glue_catalog_table" "inventory" {
  name          = "${local.prefix_under}inventory"
  database_name = aws_glue_catalog_database.finops_s3.name
  table_type    = "EXTERNAL_TABLE"

  partition_keys {
    name = "bucket"
    type = "string"
  }
  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = local.inventory_base
    input_format  = "org.apache.hadoop.hive.ql.io.SymlinkTextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
    }

    dynamic "columns" {
      for_each = var.inventory_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  parameters = {
    "EXTERNAL"                    = "TRUE"
    "projection.enabled"          = "true"
    "projection.bucket.type"      = "enum"
    "projection.bucket.values"    = local.bucket_enum
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy-MM-dd-HH-mm"
    "projection.dt.range"         = "${var.inventory_projection_start},NOW"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "DAYS"
    # $${bucket}/${dt} → ${bucket}/${dt} in AWS
    "storage.location.template" = "${local.inventory_base}$${bucket}/${var.inventory_prefix}/hive/dt=$${dt}/"
  }
}
