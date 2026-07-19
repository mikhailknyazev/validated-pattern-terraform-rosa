# CloudWatch Logging for OpenShift Logging Operator
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/4.logging.tf
# This configuration creates an IAM role and policy for the OpenShift Logging Operator to send logs to CloudWatch.
# The role uses OIDC federation to allow the OpenShift Logging Operator service account to assume the role.
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# NOTE: This is separate from audit logging (SIEM) which uses openshift-config-managed:cloudwatch-audit-exporter
# This role is for the OpenShift Logging Operator which uses openshift-logging:cluster-logging service account

# IAM Policy for CloudWatch Logging
# Grants permissions to create log groups, log streams, and write log events to CloudWatch
resource "aws_iam_policy" "cloudwatch_logging" {
  count = local.persists_through_sleep && var.enable_cloudwatch_logging ? 1 : 0

  name        = "${var.cluster_name}-rosa-cloudwatch"
  path        = "/"
  description = "IAM policy for ROSA HCP OpenShift Logging Operator CloudWatch logging"

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
    Name      = "${var.cluster_name}-rosa-cloudwatch-logging-policy"
    Purpose   = "CloudWatchLogging"
    ManagedBy = "Terraform"
  })
}

# IAM Role for CloudWatch Logging
# Uses OIDC federation to allow the OpenShift Logging Operator service account to assume this role
# Service account: system:serviceaccount:openshift-logging:logging
# Note: This is different from audit logging which uses openshift-config-managed:cloudwatch-audit-exporter
# The ClusterLogForwarder uses the "logging" service account (not "cluster-logging")
resource "aws_iam_role" "cloudwatch_logging" {
  count = local.persists_through_sleep && var.enable_cloudwatch_logging ? 1 : 0

  name                 = substr("${var.cluster_name}-rosa-cloudwatch-role-iam", 0, 64)
  permissions_boundary = var.custom_permissions_boundary_arn

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
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:openshift-logging:logging"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cloudwatch-logging-role"
    Purpose   = "CloudWatchLogging"
    ManagedBy = "Terraform"
  })
}

# Attach the CloudWatch logging policy to the role
resource "aws_iam_role_policy_attachment" "cloudwatch_logging" {
  count = local.persists_through_sleep && var.enable_cloudwatch_logging ? 1 : 0

  role       = aws_iam_role.cloudwatch_logging[0].name
  policy_arn = aws_iam_policy.cloudwatch_logging[0].arn
}
