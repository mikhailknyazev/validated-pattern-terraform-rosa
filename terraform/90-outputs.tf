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
  description = "Whether break-glass admin identity provider was created (enable_cluster_admin)"
  value       = module.cluster.identity_provider_id != null
  sensitive   = false
}

output "external_auth_providers_enabled" {
  description = "Whether external authentication providers are enabled (use break-glass-login for temporary admin access)"
  value       = var.external_auth_providers_enabled == true
  sensitive   = false
}

output "bootstrap_admin_username" {
  description = "Short-lived bootstrap HTPasswd username (null when enable_bootstrap_admin_user is false)"
  value       = module.bootstrap_admin.username
  sensitive   = false
}

output "bootstrap_admin_password" {
  description = "Short-lived bootstrap HTPasswd password (null when disabled). For GitOps bootstrap, prefer BOOTSTRAP_PASSWORD from bootstrap-admin.sh create (script-generated). This output is for module/standalone use when password is TF-generated (#29)."
  value       = module.bootstrap_admin.password
  sensitive   = true
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

output "cluster_credentials_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing cluster credentials JSON (user, password, url). Persists through sleep."
  value       = module.cluster.cluster_credentials_secret_name
  sensitive   = false
}

output "cluster_credentials_secret_arn" {
  description = <<EOF
  ARN of the AWS Secrets Manager secret containing cluster credentials JSON:
    {"user":"...","password":"...","url":"https://api...:6443"}
  This is the single source of truth for admin credentials (persists through sleep).
  Retrieve the password with:
    aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text | jq -r .password
  EOF
  value       = module.cluster.cluster_credentials_secret_arn
  sensitive   = false
}

output "admin_password_secret_arn" {
  description = <<EOF
  Deprecated alias for cluster_credentials_secret_arn (same ARN).
  Secret payload is JSON (user/password/url), not a plain password string.
  Prefer cluster_credentials_secret_arn. Kept for backward compatibility with existing scripts.
  EOF
  value       = module.cluster.cluster_credentials_secret_arn
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

#------------------------------------------------------------------------------
# AWS Client VPN (when enable_client_vpn = true)
#------------------------------------------------------------------------------

output "client_vpn_deployed" {
  description = "Whether AWS Client VPN endpoint was deployed"
  value       = var.enable_client_vpn && length(module.client_vpn) > 0
  sensitive   = false
}

output "client_vpn_endpoint_id" {
  description = "ID of the AWS Client VPN endpoint"
  value       = var.enable_client_vpn && length(module.client_vpn) > 0 ? module.client_vpn[0].vpn_endpoint_id : null
  sensitive   = false
}

output "client_vpn_config_path" {
  description = "Path to the .ovpn client configuration file (relative to project root when using scripts)"
  value       = var.enable_client_vpn && length(module.client_vpn) > 0 ? "./clusters/${coalesce(var.cluster_config_dir, var.cluster_name)}/${var.cluster_name}-vpn-client.ovpn" : null
  sensitive   = false
}

output "client_vpn_connection_instructions" {
  description = "Instructions for connecting to the Client VPN"
  value       = var.enable_client_vpn && length(module.client_vpn) > 0 ? module.client_vpn[0].connection_instructions : null
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
  description = "ARN of the IAM role for External Secrets Operator IRSA to access AWS Secrets Manager (null if enable_secrets_manager_iam is false)"
  value       = module.iam.secrets_manager_role_arn
  sensitive   = false
}

output "external_secrets_role_arn" {
  description = "Alias of secrets_manager_role_arn for External Secrets Operator IRSA (null if enable_secrets_manager_iam is false)"
  value       = module.iam.external_secrets_role_arn
  sensitive   = false
}

#------------------------------------------------------------------------------
# AWS VPC Route Server (when enable_route_server = true)
#------------------------------------------------------------------------------

output "route_server_deployed" {
  description = "Whether AWS VPC Route Server was deployed"
  value       = var.enable_route_server && length(module.route_server) > 0
  sensitive   = false
}

output "route_server_id" {
  description = "ID of the VPC Route Server (for CUDNBgpConfig CR spec.aws.routeServerIDs)"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].route_server_id : null
  sensitive   = false
}

output "route_server_asn" {
  description = "Amazon-side ASN of the VPC Route Server"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].route_server_asn : null
  sensitive   = false
}

output "route_server_endpoint_ips" {
  description = "Map of Route Server endpoint keys to ENI IP addresses"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].endpoint_ips : {}
  sensitive   = false
}

output "bgp_operator_role_arn" {
  description = "ARN of the IAM role for the CUDN BGP routing operator (for IRSA ServiceAccount annotation)"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].bgp_operator_role_arn : null
  sensitive   = false
}

output "bgp_config_secret_name" {
  description = "Secrets Manager secret name for BGP runtime config consumed by ESO (issue #51)"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].bgp_config_secret_name : null
  sensitive   = false
}

output "bgp_config_secret_arn" {
  description = "Secrets Manager secret ARN for BGP runtime config consumed by ESO (issue #51)"
  value       = var.enable_route_server && length(module.route_server) > 0 ? module.route_server[0].bgp_config_secret_arn : null
  sensitive   = false
}

output "gitops_bootstrap_enabled" {
  description = "Whether GitOps bootstrap is enabled"
  value       = module.cluster.gitops_bootstrap_enabled
  sensitive   = false
}

output "gitops_bootstrap_acm_mode" {
  description = "ACM mode for GitOps bootstrap (hub, spoke, or noacm)"
  value       = module.cluster.gitops_bootstrap_acm_mode
  sensitive   = false
}

output "gitops_bootstrap_env_exports" {
  description = "Shell export statements for GitOps bootstrap script env vars"
  value       = module.cluster.gitops_bootstrap_env_exports
  sensitive   = false
}

output "gitops_bootstrap_script_path" {
  description = "Path to the GitOps bootstrap script"
  value       = module.cluster.gitops_bootstrap_script_path
  sensitive   = false
}

output "cluster_domain" {
  description = "Cluster domain derived from API URL for GitOps bootstrap"
  value       = module.cluster.cluster_domain
  sensitive   = false
}

output "gitops_bootstrap_hub_values" {
  description = "Helm values YAML for cluster-bootstrap chart (hub/standalone mode)"
  value       = module.cluster.gitops_bootstrap_hub_values
  sensitive   = false
}

output "gitops_bootstrap_spoke_values" {
  description = "Helm values YAML for cluster-bootstrap-acm-spoke chart"
  value       = module.cluster.gitops_bootstrap_spoke_values
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

#------------------------------------------------------------------------------
# Registry Image Mirrors
#------------------------------------------------------------------------------

# Covers: description, value, sensitive
# Does: Passes the cluster module's state-retained mirror identifiers to root callers.
# Why: Root consumers need stable identifiers without reaching into child-module state.
# Change: Removing the output breaks callers but does not alter management-plane mirrors.
# Trap: This value is not a live management API or guest realization read.
# Evidence: https://developer.hashicorp.com/terraform/language/values/outputs
output "image_mirror_ids" {
  description = "Map of source repository path to image-mirror id as recorded in Terraform state at the last apply. Empty when image_mirrors is not set. This is not a live management-API or guest read."
  value       = module.cluster.image_mirror_ids
  sensitive   = false
}
