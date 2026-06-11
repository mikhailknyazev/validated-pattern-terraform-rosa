######################
# EFS Storage Resources
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf
# Note: KMS keys and IAM resources are now in the IAM module
# EFS file system remains here as it depends on cluster security groups and subnets
######################

# EFS file system
# Persists through sleep operation (not gated by persists_through_sleep)
# Note: depends_on cluster is kept for initial creation order, but EFS persists even when cluster is destroyed
# Uses EFS KMS key ARN from IAM module (via variable)
resource "aws_efs_file_system" "main" {
  count = var.enable_efs ? 1 : 0

  encrypted  = var.efs_kms_key_arn != null
  kms_key_id = var.efs_kms_key_arn != null ? var.efs_kms_key_arn : null

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-rosa-efs"
    persists_through_sleep = "true"
  })
}

# Security group ingress rules for EFS (port 2049)
# Allow access from private subnets
# Use count instead of for_each because var.private_subnet_cidrs may not be fully known at plan time
resource "aws_vpc_security_group_ingress_rule" "efs" {
  count = var.enable_efs && local.persists_through_sleep && length(var.private_subnet_cidrs) > 0 ? length(var.private_subnet_cidrs) : 0

  security_group_id = data.aws_security_groups.cluster_default[0].ids[0]
  cidr_ipv4         = var.private_subnet_cidrs[count.index]
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  description       = "Allow EFS access from ${var.private_subnet_cidrs[count.index]}"

  lifecycle {
    ignore_changes = [
      security_group_id
    ]
  }

  depends_on = [
    aws_efs_file_system.main,
    data.aws_security_groups.cluster_default
  ]
}

# EFS mount targets in each private subnet
# IMPORTANT: EFS mount targets should only be created in PRIVATE subnets, not public subnets
# For public clusters, subnet_ids includes both private and public subnets, so we use private_subnet_ids instead
# Use count instead of for_each because var.private_subnet_ids may not be fully known at plan time
resource "aws_efs_mount_target" "main" {
  count = var.enable_efs && local.persists_through_sleep ? length(var.private_subnet_ids) : 0

  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [data.aws_security_groups.cluster_default[0].ids[0]]

  lifecycle {
    ignore_changes = [
      security_groups
    ]
  }

  depends_on = [
    aws_efs_file_system.main,
    data.aws_security_groups.cluster_default
  ]
}
