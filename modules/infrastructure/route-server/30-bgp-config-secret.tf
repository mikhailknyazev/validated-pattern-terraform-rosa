# Publish BGP runtime parameters for External Secrets Operator / GitOps consumption.
# Relates to: https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/51
#
# Secret JSON keys (consumed by cudn-bgp-routing-operator chart ExternalSecret):
#   role_arn, region, route_server_id, route_server_ids (JSON array string)

locals {
  bgp_config_secret_name = "${var.cluster_name}-bgp-config"
  bgp_config_secret_string = length(aws_vpc_route_server.this) > 0 && length(aws_iam_role.bgp_operator) > 0 ? jsonencode({
    role_arn         = aws_iam_role.bgp_operator[0].arn
    region           = var.region
    route_server_id  = aws_vpc_route_server.this[0].route_server_id
    route_server_ids = jsonencode([aws_vpc_route_server.this[0].route_server_id])
  }) : null
}

resource "aws_secretsmanager_secret" "bgp_config" {
  count = var.persists_through_sleep && length(aws_vpc_route_server.this) > 0 ? 1 : 0

  name                    = local.bgp_config_secret_name
  description             = "CUDN BGP operator runtime config (IRSA role, region, Route Server IDs) for cluster ${var.cluster_name}"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name      = local.bgp_config_secret_name
    Purpose   = "CUDNBgpConfig"
    ManagedBy = "Terraform"
  })
}

resource "aws_secretsmanager_secret_version" "bgp_config" {
  count = length(aws_secretsmanager_secret.bgp_config)

  secret_id     = aws_secretsmanager_secret.bgp_config[0].id
  secret_string = local.bgp_config_secret_string
}

# Grant External Secrets Operator IRSA role read access to this secret (avoids
# IAM module data-source chicken-and-egg with secrets created in this apply).
resource "aws_iam_role_policy" "bgp_config_eso_read" {
  count = length(aws_secretsmanager_secret.bgp_config) > 0 && var.secrets_manager_role_name != null ? 1 : 0

  name = substr("${var.cluster_name}-bgp-config-eso-read", 0, 128)
  role = var.secrets_manager_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [aws_secretsmanager_secret.bgp_config[0].arn]
      }
    ]
  })
}
