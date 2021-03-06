# Environment config and data buckets

resource "aws_s3_bucket" "env" {
  bucket = var.envbucket
  acl    = "private"
  tags = {
    Name = "${var.app_name}-env"
  }
  # If KMS enabled, use the key. Otherwise do not apply SSE
  dynamic "server_side_encryption_configuration" {
    for_each = var.kms ? [1] : []
    content {
      rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = var.kms ? aws_kms_key.ashirt.0.arn : ""
          sse_algorithm     = "aws:kms"
        }
      }
    }
  }
}

resource "aws_s3_bucket" "data" {
  bucket        = var.appdata
  acl           = "private"
  force_destroy = true
  tags = {
    Name = "${var.app_name}-data"
  }
  dynamic "server_side_encryption_configuration" {
    for_each = var.kms ? [1] : []
    content {
      rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = var.kms ? aws_kms_key.ashirt.0.arn : ""
          sse_algorithm     = "aws:kms"
        }
      }
    }
  }
}

# Environment files

resource "aws_s3_bucket_object" "webenv" {
  bucket = aws_s3_bucket.env.id
  key    = "web/.env"
  source = ".env.web"
  etag   = filemd5(".env.web")
}

resource "aws_s3_bucket_object" "dbenv" {
  bucket  = aws_s3_bucket.env.id
  key     = "db/.env"
  content = "DB_URI=ashirt:${random_password.db_password.result}@tcp(${aws_rds_cluster.ashirt.endpoint}:3306)/ashirt"
}

resource "aws_s3_bucket_object" "appenv" {
  bucket  = aws_s3_bucket.env.id
  key     = "app/.env"
  content = "APP_PORT=${var.app_port}\nAPP_IMGSTORE_BUCKET_NAME=${var.appdata}\nAPP_IMGSTORE_REGION=${var.region}"
}
