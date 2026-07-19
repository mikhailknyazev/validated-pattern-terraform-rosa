variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "account_role_prefix" {
  description = "Prefix for account roles to ensure uniqueness. Defaults to cluster_name"
  type        = string
  default     = null
  nullable    = true
}

variable "operator_role_prefix" {
  description = "Prefix for operator roles to ensure uniqueness. Defaults to cluster_name"
  type        = string
  default     = null
  nullable    = true
}

variable "zero_egress" {
  description = "Enable zero egress mode. When true, attaches AmazonEC2ContainerRegistryReadOnly policy to worker role (required for egress-zero clusters)"
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

# Sleep Protection Variables
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "persists_through_sleep_iam" {
  description = "Override persists_through_sleep for IAM resources. If null, uses persists_through_sleep value. Allows sleeping IAM roles while preserving OIDC configuration for reuse across clusters."
  type        = bool
  default     = null
  nullable    = true
}

# KMS configuration
# External KMS keys MUST be tagged with "red-hat" = "true" for the ROSA KMS provider
# operator to access them (ROSAKMSProviderPolicy uses this tag as a condition).
variable "enable_storage" {
  description = "Enable storage resources (CSI driver IAM roles)"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_efs" {
  description = "Enable EFS file system (required for EFS CSI driver IAM role)"
  type        = bool
  default     = false
  nullable    = false
}

variable "create_kms_keys" {
  description = "Create KMS keys internally. When false (default), no keys are created unless external ARNs are provided. External ARNs always take precedence."
  type        = bool
  default     = false
  nullable    = false
}

variable "ebs_kms_key_arn" {
  description = "External KMS key ARN for EBS volume encryption. Takes precedence over internally created key."
  type        = string
  default     = null
  nullable    = true
}

variable "efs_kms_key_arn" {
  description = "External KMS key ARN for EFS encryption. Takes precedence over internally created key."
  type        = string
  default     = null
  nullable    = true
}

variable "etcd_kms_key_arn" {
  description = "External KMS key ARN for etcd encryption. Takes precedence over internally created key."
  type        = string
  default     = null
  nullable    = true
}

variable "etcd_encryption" {
  description = "Enable etcd encryption (requires etcd KMS key via etcd_kms_key_arn or create_kms_keys)"
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days (only used when create_kms_keys is true)"
  type        = number
  default     = 10
  nullable    = false
}

# IAM feature flags
variable "enable_audit_logging" {
  description = "[DEPRECATED] Enable CloudWatch audit logging IAM resources (legacy implementation). Use enable_control_plane_log_forwarding instead."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging IAM resources"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_cert_manager_iam" {
  description = "Enable cert-manager IAM resources"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_secrets_manager_iam" {
  description = "Enable Secrets Manager IAM resources"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_autonode" {
  description = "Create Karpenter IAM policy and IRSA role for AutoNode (ROSA HCP). Policy conditions use kubernetes.io/cluster/<suffix>; default suffix is cluster_name—set autonode_kubernetes_cluster_tag_id if ROSA tags use another ID."
  type        = bool
  default     = false
  nullable    = false
}

# Optional ROSA infra / OCM identifier for IAM policy conditions kubernetes.io/cluster/<id>.
# Defaults to cluster_name (same as other ROSA patterns in this repo). Set if instance/subnet tags use a different value.
variable "autonode_kubernetes_cluster_tag_id" {
  description = "Optional explicit cluster identifier string for kubernetes.io/cluster/<id> IAM policy conditions when enable_autonode is true. Null enables bootstrap mode on first apply and then automatic ID discovery/tightening on subsequent applies."
  type        = string
  default     = null
  nullable    = true
}

variable "aws_private_ca_arn" {
  description = "AWS Private CA ARN for cert-manager (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "additional_secrets" {
  description = "Additional Secrets Manager secret names for IAM policy (optional)"
  type        = list(string)
  default     = null
  nullable    = true
}

# Control Plane Log Forwarding configuration
variable "enable_control_plane_log_forwarding" {
  description = "Enable control plane log forwarding IAM resources (new ROSA managed log forwarder). Replaces legacy audit logging."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_log_cloudwatch_enabled" {
  description = "Enable CloudWatch destination for control plane log forwarding. Default disabled for cost; S3 is more cost-effective. Requires control_plane_log_cloudwatch_log_group_name to be set or uses default pattern."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_log_cloudwatch_log_group_name" {
  description = "CloudWatch log group name for control plane logs. If null, uses default pattern: <cluster_name>-control-plane-logs. Must match the name used in cluster module."
  type        = string
  default     = null
  nullable    = true
}

#------------------------------------------------------------------------------
# Permission Boundaries
#------------------------------------------------------------------------------

variable "rosa_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for ROSA managed IAM roles (account + operator roles). If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}

variable "custom_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for custom IAM roles (EFS CSI, CloudWatch, Secrets Manager, cert-manager, etc.). If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}
