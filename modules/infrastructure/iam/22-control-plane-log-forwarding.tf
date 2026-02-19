# Control Plane Log Forwarding IAM Configuration
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/security_and_compliance/rosa-forwarding-control-plane-logs
# This configuration creates an IAM role and policies for ROSA control plane log forwarding.
# The role uses STS assume role to allow ROSA's central log distribution role to assume this role.
#
# NOTE: This replaces the legacy audit logging implementation (20-cloudwatch-audit-logging.tf)
# which used OIDC federation with cluster service accounts. The new mechanism uses ROSA's
# managed log forwarder service outside the cluster.

# IAM Role for Control Plane Log Forwarding
# Role name must include "CustomerLogDistribution" as per ROSA documentation
# ROSA's central log distribution role assumes this role to forward logs
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_iam_role" "control_plane_log_forwarding" {
  count = var.enable_control_plane_log_forwarding ? 1 : 0

  name = "${var.cluster_name}-CustomerLogDistribution-RH"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::859037107838:role/ROSA-CentralLogDistributionRole-241c1a86"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-CustomerLogDistribution-RH"
    Purpose                = "ControlPlaneLogForwarding"
    ManagedBy              = "Terraform"
    persists_through_sleep = "true"
  })
}

# CloudWatch IAM Policy for Control Plane Log Forwarding
# Grants permissions to write logs to CloudWatch log group
# Uses constructed ARN pattern to avoid circular dependency (log group created in cluster module)
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_iam_policy" "control_plane_log_forwarding_cloudwatch" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_cloudwatch_enabled ? 1 : 0

  name        = "${var.cluster_name}-rosa-control-plane-log-forwarding-cloudwatch"
  path        = "/"
  description = "IAM policy for ROSA HCP control plane log forwarding to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreatePutLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        # Use constructed ARN pattern - cluster module must create log group with matching name
        # Default pattern: ${cluster_name}-control-plane-logs
        Resource = "arn:aws:logs:*:*:log-group:${var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"}:*"
      },
      {
        Sid    = "DescribeLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-rosa-control-plane-log-forwarding-cloudwatch-policy"
    Purpose                = "ControlPlaneLogForwarding"
    ManagedBy              = "Terraform"
    persists_through_sleep = "true"
  })
}

# Attach CloudWatch policy to the role
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_iam_role_policy_attachment" "control_plane_log_forwarding_cloudwatch" {
  count = var.enable_control_plane_log_forwarding && var.control_plane_log_cloudwatch_enabled ? 1 : 0

  role       = aws_iam_role.control_plane_log_forwarding[0].name
  policy_arn = aws_iam_policy.control_plane_log_forwarding_cloudwatch[0].arn
}
