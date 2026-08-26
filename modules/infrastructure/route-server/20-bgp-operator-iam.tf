# IAM role and policy for the CUDN BGP routing operator (IRSA).
# The operator manages Route Server peers and disables SourceDestCheck
# on BGP-enabled worker nodes.
#
# Service account: openshift-cudn-bgp-routing:openshift-cudn-bgp-routing-controller-manager
# Permissions: from bgp-cloud-connector README

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_endpoint_url_normalized = replace(var.oidc_endpoint_url, "https://", "")
}

resource "aws_iam_policy" "bgp_operator" {
  count = var.persists_through_sleep ? 1 : 0

  name        = "${var.cluster_name}-cudn-bgp-operator"
  path        = "/"
  description = "IAM policy for CUDN BGP routing operator to manage Route Server peers and ENI attributes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "ec2:DescribeRouteServers",
          "ec2:DescribeRouteServerEndpoints",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteServerPeers",
          "ec2:CreateRouteServerPeer",
          "ec2:DeleteRouteServerPeer",
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:ModifyNetworkInterfaceAttribute"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cudn-bgp-operator-policy"
  })
}

resource "aws_iam_role" "bgp_operator" {
  count = var.persists_through_sleep ? 1 : 0

  name                 = substr("${var.cluster_name}-cudn-bgp-operator", 0, 64)
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
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:openshift-cudn-bgp-routing:openshift-cudn-bgp-routing-controller-manager"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cudn-bgp-operator-role"
  })
}

resource "aws_iam_role_policy_attachment" "bgp_operator" {
  count = var.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.bgp_operator[0].name
  policy_arn = aws_iam_policy.bgp_operator[0].arn
}
