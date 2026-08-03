# Secrets Manager IAM Configuration
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/3.secrets.tf
# This configuration creates an IAM role and policy for External Secrets Operator to access AWS
# Secrets Manager via OIDC (IRSA).
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# SECURITY: This implementation uses explicit secret ARN lists instead of wildcards for maximum security.
# Only explicitly listed secrets are accessible via GetSecretValue. ListSecrets requires "*" but actual
# secret access is restricted by the explicit ARN list.

# Data source for cluster credentials secret (lookup by name to avoid circular dependency)
# Secret name follows pattern: ${cluster_name}-credentials
data "aws_secretsmanager_secret" "cluster_credentials" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0
  name  = "${var.cluster_name}-credentials"
}

# Data sources for additional secrets (if provided)
# Lookup secrets by name to get exact ARNs for the IAM policy
data "aws_secretsmanager_secret" "additional" {
  for_each = local.persists_through_sleep && var.enable_secrets_manager_iam && var.additional_secrets != null ? toset(var.additional_secrets) : toset([])
  name     = each.value
}

# Build list of all secret ARNs (default + additional)
locals {
  # Default secret ARN (cluster credentials - from data source lookup)
  default_secret_arn = local.persists_through_sleep && var.enable_secrets_manager_iam && length(data.aws_secretsmanager_secret.cluster_credentials) > 0 ? data.aws_secretsmanager_secret.cluster_credentials[0].arn : null

  # Additional secret ARNs from data source lookups
  additional_secret_arns = local.persists_through_sleep && var.enable_secrets_manager_iam && var.additional_secrets != null ? [
    for secret_name in var.additional_secrets :
    data.aws_secretsmanager_secret.additional[secret_name].arn
  ] : []

  # Combine all secret ARNs (filter out nulls)
  all_secret_arns = compact(concat(
    local.default_secret_arn != null ? [local.default_secret_arn] : [],
    local.additional_secret_arns
  ))
}

# IAM Policy for Secrets Manager
# Grants permissions to access specific secrets via explicit ARN list
# Uses explicit ARNs for GetSecretValue (secure) and "*" for ListSecrets (required by GitOps)
resource "aws_iam_policy" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  name        = "${var.cluster_name}-rosa-secretsmanager"
  path        = "/"
  description = "IAM policy for External Secrets Operator to access AWS Secrets Manager (restricted to explicit secret ARNs)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Restrict to explicit list of secret ARNs for maximum security
        Resource = local.all_secret_arns
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        # ListSecrets requires "*" but actual secret access is restricted above
        # This allows GitOps to list secrets but only access those in the explicit ARN list
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
