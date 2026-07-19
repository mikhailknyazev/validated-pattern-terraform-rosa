# Cert Manager IAM Configuration
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/6.cert-manager.tf
# This configuration creates an IAM role and policy for cert-manager to use AWS Private CA.
# The role uses OIDC federation to allow the cert-manager service account to assume the role.
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL

# IAM Policy for Cert Manager
# Grants permissions to interact with AWS Private CA (ACM-PCA)
resource "aws_iam_policy" "cert_manager" {
  count = local.persists_through_sleep && var.enable_cert_manager_iam ? 1 : 0

  name        = "${var.cluster_name}-rosa-cert-manager"
  path        = "/"
  description = "IAM policy for cert-manager to use AWS Private CA"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "awspcaissuer"
        Effect = "Allow"
        Action = [
          "acm-pca:DescribeCertificateAuthority",
          "acm-pca:GetCertificate",
          "acm-pca:IssueCertificate"
        ]
        # Allow access to all Private CAs (can be restricted to specific ARN if needed)
        # To restrict, use: Resource = var.aws_private_ca_arn
        # Handle both null and empty string cases - use "*" if not provided or empty
        Resource = var.aws_private_ca_arn != null && var.aws_private_ca_arn != "" ? [var.aws_private_ca_arn] : ["*"]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cert-manager-policy"
    Purpose   = "CertManager"
    ManagedBy = "Terraform"
  })
}

# IAM Role for Cert Manager
# Uses OIDC federation to allow the cert-manager service account to assume this role
# Service account: system:serviceaccount:cert-manager:cert-manager
resource "aws_iam_role" "cert_manager" {
  count = local.persists_through_sleep && var.enable_cert_manager_iam ? 1 : 0

  name                 = substr("${var.cluster_name}-rosa-cert-manager", 0, 64)
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
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cert-manager-role"
    Purpose   = "CertManager"
    ManagedBy = "Terraform"
  })

  depends_on = [
    aws_iam_policy.cert_manager
  ]
}

# Attach the cert-manager policy to the role
resource "aws_iam_role_policy_attachment" "cert_manager" {
  count = local.persists_through_sleep && var.enable_cert_manager_iam ? 1 : 0

  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager[0].arn

  depends_on = [
    aws_iam_policy.cert_manager,
    aws_iam_role.cert_manager
  ]
}
