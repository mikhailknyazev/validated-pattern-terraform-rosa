# ROSA AutoNode / Karpenter controller IAM resources.
# Mirrors Karpenter controller policy structure (without EKS-only statements); see terraform-aws-modules/terraform-aws-eks karpenter/policy.tf.

data "aws_region" "current" {}

locals {
  # First apply bootstrap: cluster ID is not known yet, so policy cannot pin kubernetes.io/cluster/<id>.
  # Subsequent applies: discover cluster ID from ROSA-managed security group tags and tighten policy.
  autonode_discovery_enabled = local.persists_through_sleep && var.enable_autonode && var.autonode_kubernetes_cluster_tag_id == null

  # Must match terraform-redhat/rosa-hcp/rhcs//modules/operator-roles:aws_iam_role.operator_role naming:
  #   substr("${operator_role_prefix}-${operator_namespace}-${operator_name}", 0, 64)
  # kube-system-control-plane-operator is the STS role Hypershift uses for default SG tagging.
  hypershift_control_plane_operator_role_name = substr("${local.operator_role_prefix_final}-kube-system-control-plane-operator", 0, 64)
}

data "aws_security_groups" "autonode_cluster_discovery" {
  count = local.autonode_discovery_enabled ? 1 : 0

  filter {
    name   = "tag:ClusterName"
    values = [var.cluster_name]
  }

  filter {
    name   = "tag:red-hat-managed"
    values = ["true"]
  }
}

data "aws_security_group" "autonode_cluster_discovery" {
  for_each = local.autonode_discovery_enabled ? toset(try(data.aws_security_groups.autonode_cluster_discovery[0].ids, [])) : toset([])

  id = each.value
}

locals {
  # Prefer explicit override. Otherwise discover from ROSA-managed SG tags after cluster exists.
  autonode_kubernetes_cluster_tag_id_discovered = try(one(distinct(compact([
    for sg in values(data.aws_security_group.autonode_cluster_discovery) : lookup(sg.tags, "api.openshift.com/id", null)
  ]))), null)
  autonode_kubernetes_cluster_tag_id_for_policy = try(coalesce(var.autonode_kubernetes_cluster_tag_id, local.autonode_kubernetes_cluster_tag_id_discovered), null)
  autonode_cluster_tag_key_for_policy           = local.autonode_kubernetes_cluster_tag_id_for_policy != null ? "kubernetes.io/cluster/${local.autonode_kubernetes_cluster_tag_id_for_policy}" : null
  autonode_cluster_tag_key_pattern              = "kubernetes.io/cluster/*"

}

data "aws_iam_policy_document" "autonode_controller" {
  count = local.persists_through_sleep && var.enable_autonode ? 1 : 0

  statement {
    sid = "AllowScopedEC2InstanceAccessActions"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:*::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:subnet/*",
    ]
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
  }

  statement {
    sid = "AllowScopedEC2LaunchTemplateAccessActions"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:*:launch-template/*",
    ]
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowScopedEC2InstanceActionsWithTags"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:spot-instances-request/*",
    ]
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy == null ? [1] : []
      content {
        test     = "ForAnyValue:StringLike"
        variable = "aws:TagKeys"
        values   = [local.autonode_cluster_tag_key_pattern]
      }
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowScopedResourceCreationTagging"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:spot-instances-request/*",
    ]
    actions = ["ec2:CreateTags"]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy == null ? [1] : []
      content {
        test     = "ForAnyValue:StringLike"
        variable = "aws:TagKeys"
        values   = [local.autonode_cluster_tag_key_pattern]
      }
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*"]
    actions   = ["ec2:CreateTags"]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "karpenter.sh/nodeclaim",
        "Name",
      ]
    }
  }

  statement {
    sid = "AllowScopedDeletion"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:*:*:launch-template/*",
    ]
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowRegionalReadActions"
    resources = ["*"]
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.id]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}::parameter/aws/service/*"]
    actions   = ["ssm:GetParameter"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    resources = ["*"]
    actions   = ["pricing:GetProducts"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    resources = ["*"]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    resources = ["*"]
    actions   = ["iam:PassRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileCreationActions"
    resources = ["*"]
    actions   = ["iam:CreateInstanceProfile"]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy == null ? [1] : []
      content {
        test     = "ForAnyValue:StringLike"
        variable = "aws:TagKeys"
        values   = [local.autonode_cluster_tag_key_pattern]
      }
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileTagActions"
    resources = ["*"]
    actions   = ["iam:TagInstanceProfile"]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.id]
    }
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy == null ? [1] : []
      content {
        test     = "ForAnyValue:StringLike"
        variable = "aws:TagKeys"
        values   = [local.autonode_cluster_tag_key_pattern]
      }
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileActions"
    resources = ["*"]
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    dynamic "condition" {
      for_each = local.autonode_cluster_tag_key_for_policy != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceTag/${local.autonode_cluster_tag_key_for_policy}"
        values   = ["owned"]
      }
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    resources = ["*"]
    actions   = ["iam:GetInstanceProfile"]
  }
}

resource "aws_iam_policy" "autonode" {
  count = local.persists_through_sleep && var.enable_autonode ? 1 : 0

  name        = substr("${local.account_role_prefix_final}-autonode-policy", 0, 128)
  description = "Karpenter / AutoNode controller permissions for cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.autonode_controller[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.account_role_prefix_final}-autonode-policy"
    Purpose = "AutoNodeKarpenter"
  })
}

resource "aws_iam_role" "autonode_operator" {
  count = local.persists_through_sleep && var.enable_autonode ? 1 : 0

  name                 = substr("${local.account_role_prefix_final}-autonode-operator-role", 0, 64)
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
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:kube-system:karpenter"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.account_role_prefix_final}-autonode-operator-role"
    Purpose = "AutoNodeKarpenter"
  })

  lifecycle {
    precondition {
      condition     = local.oidc_endpoint_url_normalized != ""
      error_message = "OIDC endpoint URL must be available before creating the AutoNode IRSA role."
    }
  }

  depends_on = [
    module.oidc_config_and_provider,
  ]
}

resource "aws_iam_role_policy_attachment" "autonode_operator" {
  count = local.persists_through_sleep && var.enable_autonode ? 1 : 0

  role       = aws_iam_role.autonode_operator[0].name
  policy_arn = aws_iam_policy.autonode[0].arn

  depends_on = [
    aws_iam_role.autonode_operator,
    aws_iam_policy.autonode,
  ]
}

# HyperShift needs to tag the Hypershift-managed security group so Karpenter can discover it.
resource "aws_iam_role_policy" "control_plane_operator_autonode_tags" {
  count = local.persists_through_sleep && var.enable_autonode ? 1 : 0

  name = "AllowCreateTagsOnRedHatManagedResources"
  role = local.hypershift_control_plane_operator_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowCreateTagsOnRedHatManagedResources"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/red-hat-managed" = "true"
          }
        }
      }
    ]
  })

  depends_on = [
    module.operator_roles,
  ]
}
