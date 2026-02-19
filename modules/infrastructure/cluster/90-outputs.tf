output "cluster_id" {
  description = "ID of the ROSA HCP cluster (null if persists_through_sleep is false)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the ROSA HCP cluster (null if persists_through_sleep is false)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].name) : null
  sensitive   = false
}

output "api_url" {
  description = "API URL of the cluster (null if persists_through_sleep is false)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].api_url) : null
  sensitive   = false
}

output "console_url" {
  description = "Console URL of the cluster (null if persists_through_sleep is false)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].console_url) : null
  sensitive   = false
}

# Note: kubeconfig and cluster_admin_password are not available as direct outputs

# Identity Provider Outputs
output "identity_provider_id" {
  description = "ID of the HTPasswd identity provider (null if enable_identity_provider is false or persists_through_sleep is false)"
  value       = length(rhcs_identity_provider.admin) > 0 ? one(rhcs_identity_provider.admin[*].id) : null
  sensitive   = false
}

output "identity_provider_name" {
  description = "Name of the identity provider (null if enable_identity_provider is false or persists_through_sleep is false)"
  value       = length(rhcs_identity_provider.admin) > 0 ? one(rhcs_identity_provider.admin[*].name) : null
  sensitive   = false
}

output "admin_username" {
  description = "Username of the admin user"
  value       = var.admin_username
  sensitive   = false
}

output "admin_group" {
  description = "Group the admin user belongs to"
  value       = var.admin_group
  sensitive   = false
}
# from rhcs_cluster_rosa_hcp resource. Access these through the ROSA CLI or console.

output "state" {
  description = "State of the cluster (null if persists_through_sleep is false)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].state) : null
  sensitive   = false
}


output "default_machine_pools" {
  description = "Map of default machine pool IDs keyed by pool name"
  value = local.persists_through_sleep ? {
    for idx, pool_name in local.hcp_machine_pools : pool_name => rhcs_hcp_machine_pool.default[idx].id
  } : {}
  sensitive = false
}

output "additional_machine_pools" {
  description = "Map of additional machine pool IDs keyed by pool name"
  value = local.persists_through_sleep ? {
    for k, v in rhcs_hcp_machine_pool.additional : k => v.id
  } : {}
  sensitive = false
}

output "all_machine_pools" {
  description = "Map of all machine pool IDs (default + additional) keyed by pool name"
  value = merge(
    local.persists_through_sleep ? {
      for idx, pool_name in local.hcp_machine_pools : pool_name => rhcs_hcp_machine_pool.default[idx].id
    } : {},
    local.persists_through_sleep ? {
      for k, v in rhcs_hcp_machine_pool.additional : k => v.id
    } : {}
  )
  sensitive = false
}

output "gitops_bootstrap_enabled" {
  description = "Whether GitOps bootstrap is enabled"
  value       = var.enable_gitops_bootstrap
  sensitive   = false
}

output "cluster_credentials_secret_name" {
  description = "Name of AWS Secrets Manager secret containing cluster credentials (persists through sleep)"
  value       = length(aws_secretsmanager_secret.cluster_credentials) > 0 ? aws_secretsmanager_secret.cluster_credentials[0].name : null
  sensitive   = false
}

output "cluster_credentials_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing cluster credentials (persists through sleep)"
  value       = length(aws_secretsmanager_secret.cluster_credentials) > 0 ? aws_secretsmanager_secret.cluster_credentials[0].arn : null
  sensitive   = false
}

# GitOps Bootstrap Configuration Outputs
# These outputs provide all the environment variables needed to run the bootstrap script manually
output "gitops_bootstrap_env_vars" {
  description = "Environment variables for running the GitOps bootstrap script"
  value = var.enable_gitops_bootstrap ? {
    # Required variables
    CLUSTER_NAME       = var.cluster_name
    CREDENTIALS_SECRET = length(aws_secretsmanager_secret.cluster_credentials) > 0 ? aws_secretsmanager_secret.cluster_credentials[0].name : ""
    AWS_REGION         = var.region

    # ACM configuration
    ACM_MODE = var.acm_mode

    # Helm chart configuration
    HELM_REPO_NAME     = var.helm_repo_name
    HELM_REPO_URL      = var.helm_repo_url
    HELM_CHART         = var.helm_chart
    HELM_CHART_VERSION = var.helm_chart_version

    # GitOps operator CSV
    GITOPS_CSV = var.gitops_csv

    # Optional: Git path for environment extraction
    GIT_PATH = var.git_path

    # Optional: Git repository URL for cluster-config
    GIT_REPO_URL = var.gitops_git_repo_url

    # Optional: AWS account and resources
    AWS_ACCOUNT_ID = local.aws_account_id

    # Optional: ECR account for image pulls
    ECR_ACCOUNT = var.ecr_account

    # Optional: Storage configuration - KMS keys come from IAM module (via variables)
    EBS_KMS_KEY_ARN    = var.kms_key_arn
    EFS_FILE_SYSTEM_ID = var.efs_file_system_id != null ? var.efs_file_system_id : (length(aws_efs_file_system.main) > 0 ? aws_efs_file_system.main[0].id : null)

    # Optional: AWS Private CA Issuer
    AWS_PRIVATE_CA_ARN = var.aws_private_ca_arn
    AWSPCA_CSV         = var.awspca_csv
    AWSPCA_ISSUER      = var.awspca_issuer
    ZONE_NAME          = var.zone_name

    # ACM Spoke specific (required if ACM_MODE=spoke)
    HUB_CREDENTIALS_SECRET = var.hub_credentials_secret_name
    ACM_REGION             = var.acm_region

    # ACM Spoke Helm charts
    HELM_CHART_ACM_SPOKE                    = var.helm_chart_acm_spoke
    HELM_CHART_ACM_SPOKE_VERSION            = var.helm_chart_acm_spoke_version
    HELM_CHART_ACM_HUB_REGISTRATION         = var.helm_chart_acm_hub_registration
    HELM_CHART_ACM_HUB_REGISTRATION_VERSION = var.helm_chart_acm_hub_registration_version

    # AWS Private CA Helm chart
    HELM_CHART_AWSPCA         = var.helm_chart_awspca
    HELM_CHART_AWSPCA_VERSION = var.helm_chart_awspca_version

    # Operation mode - set to true for bootstrap, false for cleanup
    ENABLE = "true"
  } : null
  sensitive = false
}

output "gitops_bootstrap_command" {
  description = <<EOF
  Shell commands to export environment variables for the GitOps bootstrap script.

  Usage:
    # Export variables and run script
    eval $(terraform output -raw gitops_bootstrap_command)
    $(terraform output -raw gitops_bootstrap_script_path)
  EOF
  value = var.enable_gitops_bootstrap && length(aws_secretsmanager_secret.cluster_credentials) > 0 ? join("\n", compact([
    "export CLUSTER_NAME='${var.cluster_name}'",
    "export CREDENTIALS_SECRET='${aws_secretsmanager_secret.cluster_credentials[0].name}'",
    "export AWS_REGION='${var.region}'",
    "export ACM_MODE='${var.acm_mode}'",
    "export HELM_REPO_NAME='${var.helm_repo_name}'",
    "export HELM_REPO_URL='${var.helm_repo_url}'",
    "export HELM_CHART='${var.helm_chart}'",
    "export HELM_CHART_VERSION='${var.helm_chart_version}'",
    "export GITOPS_CSV='${var.gitops_csv}'",
    var.git_path != null ? "export GIT_PATH='${var.git_path}'" : "",
    var.gitops_git_repo_url != null ? "export GIT_REPO_URL='${var.gitops_git_repo_url}'" : "",
    "export AWS_ACCOUNT_ID='${local.aws_account_id}'",
    var.ecr_account != null ? "export ECR_ACCOUNT='${var.ecr_account}'" : "",
    var.kms_key_arn != null ? "export EBS_KMS_KEY_ARN='${var.kms_key_arn}'" : "",
    var.efs_file_system_id != null ? "export EFS_FILE_SYSTEM_ID='${var.efs_file_system_id}'" : (length(aws_efs_file_system.main) > 0 ? "export EFS_FILE_SYSTEM_ID='${aws_efs_file_system.main[0].id}'" : ""),
    var.aws_private_ca_arn != null ? "export AWS_PRIVATE_CA_ARN='${var.aws_private_ca_arn}'" : "",
    var.awspca_csv != null ? "export AWSPCA_CSV='${var.awspca_csv}'" : "",
    var.awspca_issuer != null ? "export AWSPCA_ISSUER='${var.awspca_issuer}'" : "",
    var.zone_name != null ? "export ZONE_NAME='${var.zone_name}'" : "",
    var.cert_manager_role_arn != null ? "export CERT_MANAGER_ROLE_ARN='${var.cert_manager_role_arn}'" : "",
    var.hub_credentials_secret_name != null ? "export HUB_CREDENTIALS_SECRET='${var.hub_credentials_secret_name}'" : "",
    var.acm_region != null ? "export ACM_REGION='${var.acm_region}'" : "",
    var.helm_chart_acm_spoke != null ? "export HELM_CHART_ACM_SPOKE='${var.helm_chart_acm_spoke}'" : "",
    var.helm_chart_acm_spoke_version != null ? "export HELM_CHART_ACM_SPOKE_VERSION='${var.helm_chart_acm_spoke_version}'" : "",
    var.helm_chart_acm_hub_registration != null ? "export HELM_CHART_ACM_HUB_REGISTRATION='${var.helm_chart_acm_hub_registration}'" : "",
    var.helm_chart_acm_hub_registration_version != null ? "export HELM_CHART_ACM_HUB_REGISTRATION_VERSION='${var.helm_chart_acm_hub_registration_version}'" : "",
    var.helm_chart_awspca != null ? "export HELM_CHART_AWSPCA='${var.helm_chart_awspca}'" : "",
    var.helm_chart_awspca_version != null ? "export HELM_CHART_AWSPCA_VERSION='${var.helm_chart_awspca_version}'" : "",
    "export ENABLE='true'"
  ])) : null
  sensitive = false
}

output "gitops_bootstrap_script_path" {
  description = "Path to the GitOps bootstrap script"
  value       = var.enable_gitops_bootstrap ? local.bootstrap_gitops_script_path : null
  sensitive   = false
}

# Storage outputs
# Note: EFS persists through sleep operation, so outputs are available even when cluster is destroyed
# KMS keys are now in IAM module - see IAM module outputs

output "efs_file_system_id" {
  description = "ID of the EFS file system (persists through sleep, null if enable_efs is false)"
  value       = var.enable_efs && length(aws_efs_file_system.main) > 0 ? aws_efs_file_system.main[0].id : null
  sensitive   = false
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system (persists through sleep, null if enable_efs is false)"
  value       = var.enable_efs && length(aws_efs_file_system.main) > 0 ? aws_efs_file_system.main[0].arn : null
  sensitive   = false
}

output "aws_account_id" {
  description = "AWS account ID where the cluster is deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = false
}

# Control Plane Log Forwarding Outputs
output "control_plane_log_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for control plane logs (null if control_plane_log_cloudwatch_enabled is false)"
  value       = var.enable_control_plane_log_forwarding && var.control_plane_log_cloudwatch_enabled && length(aws_cloudwatch_log_group.control_plane_logs) > 0 ? aws_cloudwatch_log_group.control_plane_logs[0].name : null
  sensitive   = false
}

output "control_plane_log_s3_bucket_name" {
  description = "Name of the S3 bucket for control plane logs (null if control_plane_log_s3_enabled is false)"
  value       = var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled && length(aws_s3_bucket.control_plane_logs) > 0 ? aws_s3_bucket.control_plane_logs[0].id : null
  sensitive   = false
}
