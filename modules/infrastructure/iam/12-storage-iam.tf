######################
# Storage IAM Resources
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf
# IAM policies and roles for CSI drivers (EBS and EFS)
######################

######################
# IAM Policies for KMS Access
######################

# IAM policy for KMS access (used by both EBS and EFS CSI drivers)
# Only created when KMS key ARNs are available (external or internally created)
resource "aws_iam_policy" "kms_csi" {
  count = local.persists_through_sleep && var.enable_storage && local.create_kms_policy ? 1 : 0

  name        = "${var.cluster_name}-rosa-kms-csi"
  path        = "/"
  description = "KMS access policy for EBS and EFS CSI drivers for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlainText",
          "kms:DescribeKey"
        ]
        Resource = local.kms_key_arns_for_policy
      },
      {
        Effect = "Allow"
        Action = [
          "kms:RevokeGrant",
          "kms:CreateGrant",
          "kms:ListGrants"
        ]
        Resource = local.kms_key_arns_for_policy
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

######################
# Attach KMS Policy to Installer Role
######################

# The ROSA installer role needs kms:DescribeKey to validate KMS keys during cluster creation
resource "aws_iam_role_policy_attachment" "kms_installer" {
  count = local.persists_through_sleep && var.enable_storage && local.create_kms_policy ? 1 : 0

  role       = "${var.cluster_name}-HCP-ROSA-Installer-Role"
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    module.account_roles,
    aws_iam_policy.kms_csi
  ]
}

######################
# Attach KMS Policy to EBS CSI Driver Operator Role
######################

# Attach KMS policy to EBS CSI driver operator role
# The role name follows the pattern: {cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials
# This role is created by the operator-roles module in this IAM module
resource "aws_iam_role_policy_attachment" "kms_csi_ebs" {
  count = local.persists_through_sleep && var.enable_storage && local.create_kms_policy ? 1 : 0

  role       = "${var.cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    module.operator_roles,
    aws_iam_policy.kms_csi
  ]
}

######################
# EFS CSI Driver IAM Resources
######################

# IAM policy for EFS CSI driver
resource "aws_iam_policy" "efs_csi" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

  name        = "${var.cluster_name}-rosa-efs-csi"
  path        = "/"
  description = "EFS CSI driver policy for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:TagResource",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM role for EFS CSI driver
# Note: Removed depends_on cluster - only needs OIDC provider which is created by this module
resource "aws_iam_role" "efs_csi" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

  name = "${var.cluster_name}-rosa-efs-csi-role-iam"

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
            "${local.oidc_endpoint_url_normalized}:sub" = [
              "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-operator",
              "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-controller-sa"
            ]
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach EFS CSI policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.efs_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.efs_csi
  ]
}

# Attach KMS policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "kms_csi_efs" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep && local.create_kms_policy ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.kms_csi
  ]
}
