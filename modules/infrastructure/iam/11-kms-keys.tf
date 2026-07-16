######################
# KMS Keys
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf
# KMS keys for EBS, EFS, and ETCD encryption
# Only created when create_kms_keys = true AND no external ARN is provided
# External ARNs always take precedence over internally created keys
######################

# KMS key for EBS volume encryption
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_key" "ebs" {
  count = var.enable_storage && var.create_kms_keys && var.ebs_kms_key_arn == null ? 1 : 0

  description             = "KMS key for EBS volumes for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-ebs-kms-key"
    Purpose                = "EBSEncryption"
    "red-hat"              = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for EBS
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "ebs" {
  count = var.enable_storage && var.create_kms_keys && var.ebs_kms_key_arn == null ? 1 : 0

  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}

# KMS key for EFS encryption
# Persists through sleep operation (not gated by persists_through_sleep)
# Note: EFS file system is in cluster module, but KMS key is infrastructure-level
resource "aws_kms_key" "efs" {
  count = var.enable_storage && var.create_kms_keys && var.efs_kms_key_arn == null ? 1 : 0

  description             = "KMS key for EFS encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-efs-kms-key"
    Purpose                = "EFSEncryption"
    "red-hat"              = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for EFS
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "efs" {
  count = var.enable_storage && var.create_kms_keys && var.efs_kms_key_arn == null ? 1 : 0

  name          = "alias/${var.cluster_name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

# KMS key for etcd encryption
# Persists through sleep operation (not gated by persists_through_sleep)
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/1.main.tf:5-12
resource "aws_kms_key" "etcd" {
  count = var.enable_storage && var.create_kms_keys && var.etcd_encryption && var.etcd_kms_key_arn == null ? 1 : 0

  description             = "KMS key for etcd encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-etcd-kms-key"
    Purpose                = "EtcdEncryption"
    "red-hat"              = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for etcd
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "etcd" {
  count = var.enable_storage && var.create_kms_keys && var.etcd_encryption && var.etcd_kms_key_arn == null ? 1 : 0

  name          = "alias/${var.cluster_name}-etcd"
  target_key_id = aws_kms_key.etcd[0].key_id
}

# Resolved KMS key ARNs — external ARNs take precedence over internally created keys
locals {
  ebs_kms_key_arn_resolved  = var.ebs_kms_key_arn != null ? var.ebs_kms_key_arn : try(aws_kms_key.ebs[0].arn, null)
  efs_kms_key_arn_resolved  = var.efs_kms_key_arn != null ? var.efs_kms_key_arn : try(aws_kms_key.efs[0].arn, null)
  etcd_kms_key_arn_resolved = var.etcd_kms_key_arn != null ? var.etcd_kms_key_arn : try(aws_kms_key.etcd[0].arn, null)

  kms_key_arns_for_policy = compact([local.ebs_kms_key_arn_resolved, local.efs_kms_key_arn_resolved])
  create_kms_policy       = length(local.kms_key_arns_for_policy) > 0
}
