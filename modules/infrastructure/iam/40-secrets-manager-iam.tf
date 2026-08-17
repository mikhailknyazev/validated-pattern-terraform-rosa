# Secrets Manager IAM Configuration
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/3.secrets.tf
# This configuration creates an IAM role and policy for External Secrets Operator to access AWS
# Secrets Manager via OIDC (IRSA).
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# SECURITY: GetSecretValue/DescribeSecret are scoped to named secrets via ARN name-prefix patterns
# (AWS appends a random suffix to secret ARNs). ListSecrets requires "*".
# Do NOT look up secrets with data sources here: {cluster}-credentials is created later by the
# cluster module — greenfield apply must not require the secret to already exist.

data "aws_region" "secrets_manager" {}

# Build secret ARN allowlist without requiring secrets to exist yet.
# Pattern: arn:aws:secretsmanager:region:account:secret:NAME-*
locals {
  secrets_manager_secret_arn_prefix = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.secrets_manager.id}:${data.aws_caller_identity.current.account_id}:secret"

  # Default: cluster credentials secret created by cluster identity-provider module
  default_secret_arn_pattern = "${local.secrets_manager_secret_arn_prefix}:${var.cluster_name}-credentials-*"

  # Optional extras (same name-prefix pattern; secrets may be created outside this module)
  additional_secret_arn_patterns = var.additional_secrets != null ? [
    for secret_name in var.additional_secrets :
    "${local.secrets_manager_secret_arn_prefix}:${secret_name}-*"
  ] : []

  all_secret_arns = concat(
    [local.default_secret_arn_pattern],
    local.additional_secret_arn_patterns
  )
}

# IAM Policy for Secrets Manager
# Grants permissions to access specific secrets via name-prefix ARN patterns
resource "aws_iam_policy" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  name        = "${var.cluster_name}-rosa-secretsmanager"
  path        = "/"
  description = "IAM policy for External Secrets Operator to access AWS Secrets Manager (restricted to named secret ARN patterns)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = local.all_secret_arns
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        # ListSecrets requires "*" but actual secret access is restricted above
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-secretsmanager-policy"
    Purpose   = "SecretsManager"
    ManagedBy = "Terraform"
  })
}

# IAM Role for Secrets Manager
# Uses OIDC federation for External Secrets Operator:
#   system:serviceaccount:external-secrets-operator:external-secrets-sa
resource "aws_iam_role" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  name                 = substr("${var.cluster_name}-rosa-secretsmanager-role-iam", 0, 64)
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
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:external-secrets-operator:external-secrets-sa"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-secretsmanager-role-iam"
    Purpose   = "SecretsManager"
    ManagedBy = "Terraform"
  })
}

# Attach the Secrets Manager policy to the role
resource "aws_iam_role_policy_attachment" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  role       = aws_iam_role.secrets_manager[0].name
  policy_arn = aws_iam_policy.secrets_manager[0].arn

  depends_on = [
    aws_iam_policy.secrets_manager,
    aws_iam_role.secrets_manager
  ]
}
