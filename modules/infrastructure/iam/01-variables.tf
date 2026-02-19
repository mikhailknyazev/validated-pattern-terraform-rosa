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
variable "enable_storage" {
  description = "Enable storage resources (KMS keys)"
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

variable "etcd_encryption" {
  description = "Enable etcd encryption (requires etcd KMS key)"
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
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
