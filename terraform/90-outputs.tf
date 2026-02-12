output "cluster_id" {
  description = "ROSA HCP Cluster ID"
  value       = module.cluster.cluster_id
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  value       = var.cluster_name
  sensitive   = false
}

output "api_url" {
  description = "Cluster API URL"
  value       = module.cluster.api_url
  sensitive   = false
}

output "console_url" {
  description = "Cluster Console URL"
  value       = module.cluster.console_url
  sensitive   = false
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.network.vpc_id
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = local.network.vpc_cidr_block
  sensitive   = false
}

output "region" {
  description = "AWS region"
  value       = var.region
  sensitive   = false
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = local.network.private_subnet_ids
  sensitive   = false
}

output "public_subnet_ids" {
  description = "Public subnet IDs (null for private/egress-zero clusters)"
  value       = var.network_type == "public" ? local.network.public_subnet_ids : []
  sensitive   = false
}

output "security_group_id" {
  description = "Security group ID for worker nodes (null for public/private clusters without zero egress)"
  value       = var.network_type == "private" && var.zero_egress ? local.network.security_group_id : null
  sensitive   = false
}

output "admin_user_created" {
  description = "Whether admin user was created"
  value       = module.cluster.identity_provider_id != null
  sensitive   = false
}

output "identity_provider_id" {
  description = "ID of the HTPasswd identity provider (null if enable_identity_provider is false)"
  value       = module.cluster.identity_provider_id
  sensitive   = false
}

output "identity_provider_name" {
  description = "Name of the identity provider (null if enable_identity_provider is false)"
  value       = module.cluster.identity_provider_name
  sensitive   = false
}

output "admin_password_secret_arn" {
  description = <<EOF
  ARN of the AWS Secrets Manager secret containing the admin password.
  This secret persists through sleep operations for easy cluster restart.
  Use AWS CLI to retrieve the password:
    aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text
  EOF
  value       = length(aws_secretsmanager_secret.admin_password) > 0 ? aws_secretsmanager_secret.admin_password[0].arn : null
  sensitive   = false
}

output "bastion_deployed" {
  description = "Whether bastion host was deployed"
  value       = var.enable_bastion && length(module.bastion) > 0
  sensitive   = false
}

output "bastion_instance_id" {
  description = "Bastion instance ID (for SSM Session Manager access)"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].bastion_instance_id : null
  sensitive   = false
}

output "bastion_ssm_command" {
  description = "Command to connect to bastion via SSM Session Manager"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].ssm_session_command : null
  sensitive   = false
}

output "bastion_sshuttle_command" {
  description = "Command to create VPN-like access via sshuttle"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].sshuttle_command : null
  sensitive   = false
}

output "aws_account_id" {
  description = "AWS account ID where the cluster is deployed"
  value       = module.cluster.aws_account_id
  sensitive   = false
}

output "efs_file_system_id" {
  description = "ID of the EFS file system (persists through sleep, null if enable_storage is false or enable_efs is false)"
  value       = module.cluster.efs_file_system_id
  sensitive   = false
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system (persists through sleep, null if enable_storage is false or enable_efs is false)"
  value       = module.cluster.efs_file_system_arn
  sensitive   = false
}

output "ebs_kms_key_arn" {
  description = "ARN of the KMS key for EBS encryption (persists through sleep, null if enable_storage is false)"
  value       = module.iam.ebs_kms_key_arn
  sensitive   = false
}

output "efs_kms_key_arn" {
  description = "ARN of the KMS key for EFS encryption (persists through sleep, null if enable_storage is false or enable_efs is false)"
  value       = module.iam.efs_kms_key_arn
  sensitive   = false
}

output "etcd_kms_key_id" {
  description = "ID of the KMS key for etcd encryption (persists through sleep, null if enable_storage is false or etcd_encryption is false)"
  value       = module.iam.etcd_kms_key_id
  sensitive   = false
}

output "etcd_kms_key_arn" {
  description = "ARN of the KMS key for etcd encryption (persists through sleep, null if enable_storage is false or etcd_encryption is false)"
  value       = module.iam.etcd_kms_key_arn
  sensitive   = false
}

output "cert_manager_role_arn" {
  description = "ARN of the IAM role for cert-manager to use AWS Private CA (null if enable_cert_manager_iam is false)"
  value       = module.iam.cert_manager_role_arn
  sensitive   = false
}

output "cloudwatch_logging_role_arn" {
  description = "ARN of the IAM role for CloudWatch logging via OpenShift Logging Operator (null if enable_cloudwatch_logging is false)"
  value       = module.iam.cloudwatch_logging_role_arn
  sensitive   = false
}

output "secrets_manager_role_arn" {
  description = "ARN of the IAM role for ArgoCD Vault Plugin to access AWS Secrets Manager (null if enable_secrets_manager_iam is false)"
  value       = module.iam.secrets_manager_role_arn
  sensitive   = false
}

output "gitops_bootstrap_enabled" {
  description = "Whether GitOps bootstrap is enabled"
  value       = module.cluster.gitops_bootstrap_enabled
  sensitive   = false
}

output "gitops_bootstrap_env_vars" {
  description = "Environment variables for running the GitOps bootstrap script manually"
  value       = module.cluster.gitops_bootstrap_env_vars
  sensitive   = false
}

output "gitops_bootstrap_command" {
  description = <<EOF
  Shell commands to export environment variables for the GitOps bootstrap script.

  Usage:
    # Export variables and run script
    eval $(terraform output -raw gitops_bootstrap_command)
    $(terraform output -raw gitops_bootstrap_script_path)
  EOF
  value       = module.cluster.gitops_bootstrap_command
  sensitive   = false
}

output "gitops_bootstrap_script_path" {
  description = "Path to the GitOps bootstrap script"
  value       = module.cluster.gitops_bootstrap_script_path
  sensitive   = false
}

#------------------------------------------------------------------------------
# Cluster Creation Timing (when enable_timing = true)
#------------------------------------------------------------------------------
# Reference: ./reference/rosa-tf/environments/commercial-hcp/outputs.tf:309-315

output "cluster_creation_timing" {
  description = "Cluster creation timing summary (only populated when enable_timing = true)."
  value       = var.enable_timing ? module.cluster_timing.timing_summary : null
  sensitive   = false
}
