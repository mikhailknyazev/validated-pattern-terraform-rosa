# CloudWatch Audit Log Forwarding IAM Configuration (DEPRECATED)
# Reference: https://access.redhat.com/solutions/7002219
#
# ⚠️  DEPRECATED: This legacy audit logging IAM configuration is deprecated.
# Use the new control plane log forwarding IAM resources instead (22-control-plane-log-forwarding.tf).
#
# Migration: Set enable_control_plane_log_forwarding = true and enable_audit_logging = false
# The new mechanism uses ROSA's managed log forwarder service with STS assume role instead of OIDC federation.
#
# This configuration creates an IAM role and policy for CloudWatch audit log forwarding.
# The role uses OIDC federation to allow the OpenShift audit log exporter service account to assume the role.
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# NOTE: If you see a "Provider produced inconsistent final plan" error from the time provider in the
# oidc_config_and_provider module, this is a known issue where the upstream module's time_sleep resource
# sees the OIDC endpoint URL format change. This typically resolves on the next apply. The normalization
# here only affects our IAM trust policy and does not modify the upstream module's behavior.

# IAM Policy for CloudWatch Logging
# Grants permissions to create log groups, log streams, and write log events to CloudWatch
resource "aws_iam_policy" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  name        = "${var.cluster_name}-rosa-cloudwatch-audit-logging"
  path        = "/"
  description = "IAM policy for ROSA HCP CloudWatch audit log forwarding"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cloudwatch-audit-logging-policy"
    Purpose   = "CloudWatchAuditLogging"
    ManagedBy = "Terraform"
  })
}

# IAM Role for CloudWatch Audit Logging
# Uses OIDC federation to allow the OpenShift audit log exporter service account to assume this role
# Service account: system:serviceaccount:openshift-config-managed:cloudwatch-audit-exporter
# Reference: https://access.redhat.com/solutions/7002219
# Note: The service account is different from regular CloudWatch logging (which uses openshift-logging:cluster-logging)
resource "aws_iam_role" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  name = "${var.cluster_name}-rosa-cloudwatch-audit-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_endpoint_url_normalized}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:openshift-config-managed:cloudwatch-audit-exporter"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cloudwatch-audit-logging-role"
    Purpose   = "CloudWatchAuditLogging"
    ManagedBy = "Terraform"
  })
}

# Attach the CloudWatch logging policy to the role
resource "aws_iam_role_policy_attachment" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  role       = aws_iam_role.cloudwatch_audit_logging[0].name
  policy_arn = aws_iam_policy.cloudwatch_audit_logging[0].arn
}
