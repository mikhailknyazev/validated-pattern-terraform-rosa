# AutoNode: Karpenter discovery tags on AWS subnets and default SG.
# Enablement is `auto_node` on `rhcs_cluster_rosa_hcp` in 10-main.tf (not ROSA CLI).
# Reference: rh-mobb/validated-pattern-terraform-rosa issue #15.

locals {
  autonode_enabled = local.persists_through_sleep && var.enable_autonode
}

# Use count (not for_each on subnet IDs): private_subnet_ids often come from aws_subnet at plan time
# and are unknown until apply; for_each keys must be known, but length(var.private_subnet_ids) is stable.
resource "aws_ec2_tag" "private_subnet_karpenter_discovery" {
  count = local.autonode_enabled ? length(var.private_subnet_ids) : 0

  resource_id = var.private_subnet_ids[count.index]
  key         = "karpenter.sh/discovery"
  value       = one(rhcs_cluster_rosa_hcp.main[*].id)

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
  ]
}

data "aws_security_groups" "autonode_default" {
  count = local.autonode_enabled ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name = "tag:Name"
    values = [
      "${one(rhcs_cluster_rosa_hcp.main[*].id)}-default-sg"
    ]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
  ]
}

resource "aws_ec2_tag" "default_sg_karpenter_discovery" {
  count = local.autonode_enabled ? 1 : 0

  resource_id = data.aws_security_groups.autonode_default[0].ids[0]
  key         = "karpenter.sh/discovery"
  value       = one(rhcs_cluster_rosa_hcp.main[*].id)

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    data.aws_security_groups.autonode_default,
  ]
}
