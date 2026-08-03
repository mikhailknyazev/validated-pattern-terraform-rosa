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
    # Operator roles are created by the operator-roles module using substr({prefix}-{namespace}-{operator_name}, 0, 64)
    ingress        = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-openshift-ingress-operator-cloud-credentials", 0, 64)}"
    control_plane  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-kube-system-control-plane-operator", 0, 64)}"
    csi_driver     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-openshift-cluster-csi-drivers-ebs-cloud-credentials", 0, 64)}"
    image_registry = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-openshift-image-registry-installer-cloud-credentials", 0, 64)}"
    network        = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-openshift-cloud-network-config-controller-cloud-credentials", 0, 64)}"
    node_pool      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${substr("${local.operator_role_prefix_final}-kube-system-capa-controller-manager", 0, 64)}"
  } : null
  sensitive = false
}

# KMS Key Outputs — returns resolved ARN (external takes precedence over internal)
output "ebs_kms_key_id" {
  description = "ID of the EBS KMS key (null when using external ARN or no key configured)"
  value       = length(aws_kms_key.ebs) > 0 ? aws_kms_key.ebs[0].key_id : null
  sensitive   = false
}

output "ebs_kms_key_arn" {
  description = "Resolved ARN of the EBS KMS key (external ARN, internal key ARN, or null)"
  value       = local.ebs_kms_key_arn_resolved
  sensitive   = false
}

output "efs_kms_key_id" {
  description = "ID of the EFS KMS key (null when using external ARN or no key configured)"
  value       = length(aws_kms_key.efs) > 0 ? aws_kms_key.efs[0].key_id : null
  sensitive   = false
}

output "efs_kms_key_arn" {
  description = "Resolved ARN of the EFS KMS key (external ARN, internal key ARN, or null)"
  value       = local.efs_kms_key_arn_resolved
  sensitive   = false
}

output "etcd_kms_key_id" {
  description = "ID of the ETCD KMS key (null when using external ARN or no key configured)"
  value       = length(aws_kms_key.etcd) > 0 ? aws_kms_key.etcd[0].key_id : null
  sensitive   = false
}

output "etcd_kms_key_arn" {
  description = "Resolved ARN of the ETCD KMS key (external ARN, internal key ARN, or null)"
  value       = local.etcd_kms_key_arn_resolved
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
  description = "ARN of the Secrets Manager IAM role for External Secrets Operator IRSA (null if enable_secrets_manager_iam is false)"
  value       = length(aws_iam_role.secrets_manager) > 0 ? aws_iam_role.secrets_manager[0].arn : null
  sensitive   = false
}

output "external_secrets_role_arn" {
  description = "Alias of secrets_manager_role_arn for External Secrets Operator IRSA (null if enable_secrets_manager_iam is false)"
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

output "autonode_policy_arn" {
  description = "ARN of the AutoNode (Karpenter) controller IAM policy (null if enable_autonode is false)"
  value       = length(aws_iam_policy.autonode) > 0 ? aws_iam_policy.autonode[0].arn : null
  sensitive   = false
}

output "autonode_role_arn" {
  description = "ARN of the AutoNode (Karpenter) IRSA IAM role (null if enable_autonode is false)"
  value       = length(aws_iam_role.autonode_operator) > 0 ? aws_iam_role.autonode_operator[0].arn : null
  sensitive   = false
}
