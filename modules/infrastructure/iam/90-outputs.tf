output "oidc_config_id" {
  description = "ID of the OIDC configuration"
  value       = module.oidc_config_and_provider.oidc_config_id
  sensitive   = false
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL"
  value       = module.oidc_config_and_provider.oidc_endpoint_url
  sensitive   = false
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider (constructed from OIDC endpoint URL)"
  # The module may not expose this directly, so we construct it from the endpoint URL
  value     = try(module.oidc_config_and_provider.oidc_provider_arn, "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.oidc_config_and_provider.oidc_endpoint_url, "https://", "")}")
  sensitive = false
}

output "installer_role_arn" {
  description = "ARN of the Installer account role (null if persists_through_sleep_iam is false)"
  value       = length(module.account_roles) > 0 ? local.installer_role_arn : null
  sensitive   = false
}

output "support_role_arn" {
  description = "ARN of the Support account role (null if persists_through_sleep_iam is false)"
  value       = length(module.account_roles) > 0 ? local.support_role_arn : null
  sensitive   = false
}

output "worker_role_arn" {
  description = "ARN of the Worker account role (null if persists_through_sleep_iam is false)"
  value       = length(module.account_roles) > 0 ? local.worker_role_arn : null
  sensitive   = false
}

output "operator_role_arns" {
  description = "Map of operator role names to ARNs. Operator roles are created by the operator-roles module and referenced by prefix in the cluster. (null if persists_through_sleep_iam is false)"
  value = length(module.operator_roles) > 0 ? {
    # Operator roles are created by the operator-roles module
    # The cluster references them by operator_role_prefix
    # These ARNs follow the pattern: {operator_role_prefix}{operator_name}-Role
    ingress        = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}ingress-Role"
    control_plane  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}control-plane-Role"
    csi_driver     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}csi-driver-Role"
    image_registry = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}image-registry-Role"
    network        = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}network-Role"
    node_pool      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.operator_role_prefix_final}node-pool-Role"
  } : null
  sensitive = false
}

# KMS Key Outputs
output "ebs_kms_key_id" {
  description = "ID of the EBS KMS key (null if enable_storage is false)"
  value       = length(aws_kms_key.ebs) > 0 ? aws_kms_key.ebs[0].key_id : null
  sensitive   = false
}

output "ebs_kms_key_arn" {
  description = "ARN of the EBS KMS key (null if enable_storage is false)"
  value       = length(aws_kms_key.ebs) > 0 ? aws_kms_key.ebs[0].arn : null
  sensitive   = false
}

output "efs_kms_key_id" {
  description = "ID of the EFS KMS key (null if enable_storage is false)"
  value       = length(aws_kms_key.efs) > 0 ? aws_kms_key.efs[0].key_id : null
  sensitive   = false
}

output "efs_kms_key_arn" {
  description = "ARN of the EFS KMS key (null if enable_storage is false)"
  value       = length(aws_kms_key.efs) > 0 ? aws_kms_key.efs[0].arn : null
  sensitive   = false
}

output "etcd_kms_key_id" {
  description = "ID of the ETCD KMS key (null if enable_storage is false or etcd_encryption is false)"
  value       = length(aws_kms_key.etcd) > 0 ? aws_kms_key.etcd[0].key_id : null
  sensitive   = false
}

output "etcd_kms_key_arn" {
  description = "ARN of the ETCD KMS key (null if enable_storage is false or etcd_encryption is false)"
  value       = length(aws_kms_key.etcd) > 0 ? aws_kms_key.etcd[0].arn : null
  sensitive   = false
}

# IAM Role Outputs
output "cloudwatch_audit_logging_role_arn" {
  description = "ARN of the CloudWatch audit logging IAM role (null if enable_audit_logging is false)"
  value       = length(aws_iam_role.cloudwatch_audit_logging) > 0 ? aws_iam_role.cloudwatch_audit_logging[0].arn : null
  sensitive   = false
}

output "cloudwatch_logging_role_arn" {
  description = "ARN of the CloudWatch logging IAM role (null if enable_cloudwatch_logging is false)"
  value       = length(aws_iam_role.cloudwatch_logging) > 0 ? aws_iam_role.cloudwatch_logging[0].arn : null
  sensitive   = false
}

output "secrets_manager_role_arn" {
  description = "ARN of the Secrets Manager IAM role (null if enable_secrets_manager_iam is false)"
  value       = length(aws_iam_role.secrets_manager) > 0 ? aws_iam_role.secrets_manager[0].arn : null
  sensitive   = false
}

output "cert_manager_role_arn" {
  description = "ARN of the cert-manager IAM role (null if enable_cert_manager_iam is false)"
  value       = length(aws_iam_role.cert_manager) > 0 ? aws_iam_role.cert_manager[0].arn : null
  sensitive   = false
}

# Control Plane Log Forwarding Outputs
output "control_plane_log_forwarding_role_arn" {
  description = "ARN of the control plane log forwarding IAM role (null if enable_control_plane_log_forwarding is false)"
  value       = length(aws_iam_role.control_plane_log_forwarding) > 0 ? aws_iam_role.control_plane_log_forwarding[0].arn : null
  sensitive   = false
}
