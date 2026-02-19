######################
# Control Plane Log Forwarding Resources
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/security_and_compliance/rosa-forwarding-control-plane-logs
# These resources are created in the cluster module as they are cluster-specific infrastructure
# (similar to EFS storage). IAM resources are in the IAM module.
######################

# Note: s3_bucket_name local is defined in 10-main.tf for use across multiple files

# CloudWatch Log Group for Control Plane Logs
# Log group name must match the pattern used in IAM module policy
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_cloudwatch_log_group" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_cloudwatch_enabled ? 1 : 0

  name = var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"

  # Optional: Set retention period (default is never expire)
  # retention_in_days = 30

  tags = merge(local.common_tags, {
    Name                   = var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"
    Purpose                = "ControlPlaneLogForwarding"
    ManagedBy              = "Terraform"
    persists_through_sleep = "true"
  })
}

# S3 Bucket for Control Plane Logs
# Persists through sleep operation (not gated by persists_through_sleep)
# Bucket name is auto-generated if not provided: <cluster_name>-control-plane-logs-<random_suffix>
resource "aws_s3_bucket" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled ? 1 : 0

  bucket = local.s3_bucket_name

  # Allow Terraform to delete all objects and versions when destroying the bucket
  # Required because bucket may contain log files from ROSA control plane log forwarder
  # Note: For versioned buckets, null_resource.s3_bucket_cleanup handles explicit version deletion
  force_destroy = true

  tags = merge(local.common_tags, {
    Name                   = local.s3_bucket_name
    Purpose                = "ControlPlaneLogForwarding"
    ManagedBy              = "Terraform"
    persists_through_sleep = "true"
  })
}

# S3 Bucket Versioning (optional, but recommended for log storage)
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_s3_bucket_versioning" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled ? 1 : 0

  bucket = aws_s3_bucket.control_plane_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption (AES256 / SSE-S3)
# Persists through sleep operation (not gated by persists_through_sleep)
#
# We use AWS-managed SSE-S3 (AES256) rather than customer-managed KMS (SSE-KMS) because:
# - ROSA's central log distribution role (arn:aws:iam::859037107838:role/ROSA-CentralLogDistributionRole-*)
#   writes to this bucket from a different AWS account. Using KMS would require granting that cross-account
#   role kms:Decrypt and kms:GenerateDataKey permissions on our key.
# - Granting decrypt access to an external account's IAM role is a security trade-off we choose to avoid.
# - SSE-S3 provides encryption at rest without exposing key access to ROSA's account. AWS manages the keys.
resource "aws_s3_bucket_server_side_encryption_configuration" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled ? 1 : 0

  bucket = aws_s3_bucket.control_plane_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Lifecycle - expire objects after retention period for cost control
# Persists through sleep operation (not gated by persists_through_sleep)
# When control_plane_log_s3_retention_days is null, no lifecycle rule (retain indefinitely)
resource "aws_s3_bucket_lifecycle_configuration" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled && var.control_plane_log_s3_retention_days != null ? 1 : 0

  bucket = aws_s3_bucket.control_plane_logs[0].id

  rule {
    id     = "expire-control-plane-logs"
    status = "Enabled"

    expiration {
      days = var.control_plane_log_s3_retention_days
    }

    # Expire noncurrent versions (from versioning) after same period
    noncurrent_version_expiration {
      noncurrent_days = var.control_plane_log_s3_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.control_plane_logs]
}

# S3 Bucket Policy
# Allows ROSA's central log distribution role to write to the bucket
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_s3_bucket_policy" "control_plane_logs" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled ? 1 : 0

  bucket = aws_s3_bucket.control_plane_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCentralLogDistributionWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::859037107838:role/ROSA-CentralLogDistributionRole-241c1a86"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.control_plane_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket.control_plane_logs
  ]
}
