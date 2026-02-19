# Note: zero_egress is a cluster-level ROSA API property (independent of network_type)
# The network module receives zero_egress directly and configures infrastructure accordingly

# Network Module - conditionally select public or private based on network_type
# Note: Terraform requires the source to be a literal string, so we use separate module blocks with count
module "network_public" {
  count  = var.network_type == "public" ? 1 : 0
  source = "../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets

  tags                           = local.tags
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

module "network_private" {
  count  = var.network_type == "private" ? 1 : 0
  source = "../modules/infrastructure/network-private"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets

  # Network infrastructure configuration for zero egress
  # When zero_egress is true, NAT Gateway is disabled and strict security groups are enabled
  # Note: zero_egress is independent of network_type - passed directly from root variable
  enable_nat_gateway = !var.zero_egress
  zero_egress        = var.zero_egress
  flow_log_s3_bucket = var.flow_log_s3_bucket

  tags                           = local.tags
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

# Create a local to reference the active network module
locals {
  network = var.network_type == "public" ? module.network_public[0] : module.network_private[0]
}

# Generate random suffix for resource naming (reusable across multiple modules)
# This ensures consistency - all resources from the same cluster share the same suffix
# Persists through sleep operation (not gated by persists_through_sleep)
# Created unconditionally so it's available for any module that needs unique resource names
resource "random_id" "resource_suffix" {
  byte_length = 4 # 8 hex characters for uniqueness

  keepers = {
    cluster_name = var.cluster_name
  }

  lifecycle {
    create_before_destroy = false
    # Persist through sleep - don't destroy when cluster is slept
    # The random_id will remain stable across cluster lifecycle
  }
}

# Additional machine pools - resolve subnet_index to actual subnet IDs
locals {
  # Resolve subnet_index to actual subnet IDs from network module
  # Only resolve when destroy is disabled (resources will be created)
  # Remove subnet_index and add subnet_id for the cluster module
  additional_machine_pools_resolved = var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? {
    for pool_name, pool_config in var.additional_machine_pools : pool_name => merge(
      {
        for k, v in pool_config : k => v if k != "subnet_index"
      },
      {
        subnet_id = local.network.private_subnet_ids[pool_config.subnet_index]
      }
    )
  } : {}
}

module "iam" {
  source = "../modules/infrastructure/iam"

  cluster_name               = var.cluster_name
  account_role_prefix        = var.cluster_name # No trailing dash - account-iam-resources module adds it
  operator_role_prefix       = var.cluster_name # No trailing dash - operator-roles module adds it
  zero_egress                = var.zero_egress  # Pass directly - IAM needs ECR policy when zero_egress is enabled (independent of network_type)
  tags                       = local.tags
  persists_through_sleep     = var.persists_through_sleep
  persists_through_sleep_iam = var.persists_through_sleep_iam

  # KMS configuration
  enable_storage          = true
  etcd_encryption         = var.etcd_encryption
  kms_key_deletion_window = var.kms_key_deletion_window
  enable_efs              = var.enable_efs != null ? var.enable_efs : true

  # IAM feature flags
  enable_audit_logging       = var.enable_audit_logging
  enable_cloudwatch_logging  = var.enable_cloudwatch_logging
  enable_cert_manager_iam    = var.enable_cert_manager_iam
  enable_secrets_manager_iam = var.enable_secrets_manager_iam
  aws_private_ca_arn         = var.aws_private_ca_arn
  additional_secrets         = var.additional_secrets

  # Control plane log forwarding (new ROSA managed log forwarder)
  enable_control_plane_log_forwarding         = var.enable_control_plane_log_forwarding
  control_plane_log_cloudwatch_enabled        = var.control_plane_log_cloudwatch_enabled
  control_plane_log_cloudwatch_log_group_name = var.control_plane_log_cloudwatch_log_group_name

  # Note: cluster_credentials_secret_arn is no longer passed as a variable
  # The IAM module looks up the secret by name (${cluster_name}-credentials) to avoid circular dependency
}

module "cluster" {
  source = "../modules/infrastructure/cluster"

  cluster_name = var.cluster_name
  region       = var.region
  vpc_id       = local.network.vpc_id
  vpc_cidr     = var.vpc_cidr

  # Subnet selection - pass private and public separately, cluster module will concatenate
  # Public clusters use both private and public subnets
  # Private and egress-zero clusters use only private subnets
  private_subnet_ids             = local.network.private_subnet_ids
  public_subnet_ids              = coalesce(local.network.public_subnet_ids, [])
  installer_role_arn             = module.iam.installer_role_arn
  support_role_arn               = module.iam.support_role_arn
  worker_role_arn                = module.iam.worker_role_arn
  oidc_config_id                 = module.iam.oidc_config_id    # OIDC is never gated
  oidc_endpoint_url              = module.iam.oidc_endpoint_url # OIDC is never gated
  enable_persistent_dns_domain   = var.enable_persistent_dns_domain
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_cluster = var.persists_through_sleep_cluster

  # Cluster configuration
  # Note: zero_egress is a cluster-level ROSA API property, independent of network_type
  # However, zero egress typically requires private network (PrivateLink API endpoint)
  private            = var.private
  zero_egress        = var.zero_egress # Pass directly - cluster-level property, not tied to network
  multi_az           = var.multi_az
  availability_zones = local.network.private_subnet_azs
  fips               = var.fips

  # Identity provider configuration
  enable_identity_provider     = var.persists_through_sleep
  admin_username               = var.admin_username
  admin_password_for_bootstrap = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result

  # KMS keys from IAM module
  kms_key_arn      = module.iam.ebs_kms_key_arn
  etcd_kms_key_arn = module.iam.etcd_kms_key_arn
  efs_kms_key_arn  = module.iam.efs_kms_key_arn

  # Storage configuration - EFS file system (KMS keys are in IAM module)
  enable_efs           = var.enable_efs != null ? var.enable_efs : true
  private_subnet_cidrs = local.network.private_subnet_cidrs

  # CloudWatch audit logging configuration (legacy - deprecated)
  enable_audit_logging              = var.enable_audit_logging
  cloudwatch_audit_logging_role_arn = module.iam.cloudwatch_audit_logging_role_arn

  # Control plane log forwarding (new ROSA managed log forwarder)
  enable_control_plane_log_forwarding         = var.enable_control_plane_log_forwarding
  control_plane_log_forwarding_role_arn       = module.iam.control_plane_log_forwarding_role_arn
  control_plane_log_cloudwatch_groups         = var.control_plane_log_cloudwatch_groups
  control_plane_log_cloudwatch_applications   = var.control_plane_log_cloudwatch_applications
  control_plane_log_s3_groups                 = var.control_plane_log_s3_groups
  control_plane_log_s3_applications           = var.control_plane_log_s3_applications
  control_plane_log_cloudwatch_enabled        = var.control_plane_log_cloudwatch_enabled
  control_plane_log_cloudwatch_log_group_name = var.control_plane_log_cloudwatch_log_group_name
  control_plane_log_s3_enabled                = var.control_plane_log_s3_enabled
  control_plane_log_s3_bucket_name            = var.control_plane_log_s3_bucket_name
  control_plane_log_s3_bucket_prefix          = var.control_plane_log_s3_bucket_prefix
  control_plane_log_s3_retention_days         = var.control_plane_log_s3_retention_days
  resource_suffix                             = random_id.resource_suffix.hex

  # GitOps bootstrap configuration
  enable_gitops_bootstrap = var.enable_gitops_bootstrap != null ? var.enable_gitops_bootstrap : false
  # admin_password_for_bootstrap is set above in identity provider configuration
  # Storage resources are automatically available from cluster module outputs
  ebs_kms_key_arn    = module.iam.ebs_kms_key_arn # Use IAM module's KMS key
  efs_file_system_id = null                       # Will use cluster module's created EFS
  # GitOps repository configuration
  git_path            = var.gitops_git_path
  gitops_git_repo_url = var.gitops_git_repo_url

  # Termination Protection (IAM resources are in IAM module)
  enable_termination_protection = var.enable_termination_protection

  # GitOps bootstrap configuration - IAM role ARNs from IAM module
  aws_private_ca_arn    = var.aws_private_ca_arn
  cert_manager_role_arn = module.iam.cert_manager_role_arn
  openshift_version     = var.openshift_version
  service_cidr          = var.service_cidr
  pod_cidr              = var.pod_cidr
  host_prefix           = var.host_prefix

  # Default machine pool configuration
  # If not set, module will calculate defaults:
  # - Single-AZ: min = 2, max = 4
  # - Multi-AZ: min = 3, max = 6
  default_instance_type = var.default_instance_type
  default_min_replicas  = null # Use module defaults (calculated based on single-AZ vs multi-AZ)
  default_max_replicas  = null # Use module defaults (calculated based on single-AZ vs multi-AZ)

  # Additional machine pools - resolved with actual subnet IDs
  additional_machine_pools = {
    for pool_name, pool_config in local.additional_machine_pools_resolved : pool_name => {
      subnet_id                     = pool_config.subnet_id
      instance_type                 = pool_config.instance_type
      autoscaling_enabled           = pool_config.autoscaling_enabled
      min_replicas                  = pool_config.min_replicas
      max_replicas                  = pool_config.max_replicas
      replicas                      = pool_config.replicas
      auto_repair                   = pool_config.auto_repair
      labels                        = pool_config.labels
      taints                        = pool_config.taints
      additional_security_group_ids = pool_config.additional_security_group_ids
      capacity_reservation_id       = pool_config.capacity_reservation_id
      disk_size                     = pool_config.disk_size
      ec2_metadata_http_tokens      = pool_config.ec2_metadata_http_tokens
      tags                          = pool_config.tags
      version                       = pool_config.version
      upgrade_acknowledgements_for  = pool_config.upgrade_acknowledgements_for
      kubelet_configs               = pool_config.kubelet_configs
      tuning_configs                = pool_config.tuning_configs
      ignore_deletion_error         = pool_config.ignore_deletion_error
    }
  }

  # Zero-egress specific settings
  # Zero-egress clusters may take longer for nodes to start due to network connectivity
  # Set to false to allow cluster creation to complete even if nodes are still starting
  # Note: Based on zero_egress property directly, independent of network_type
  wait_for_std_compute_nodes_complete = var.zero_egress ? false : true

  # Optional: Allow API endpoint access from additional IPv4 CIDR blocks
  # By default, the VPC endpoint security group only allows access from within the VPC
  # Uncomment and configure to allow access from VPN ranges, bastion hosts, or other VPCs
  # For egress-zero clusters, this is useful for allowing access from VPN or Transit Gateway connected networks
  # api_endpoint_allowed_cidrs = [
  #   "10.0.0.0/32",      # Example: Specific IP (e.g., bastion host via SSM Session Manager)
  #   "192.168.1.0/24"   # Example: VPN range or Transit Gateway connected VPC CIDR
  # ]

  tags = var.tags

  # CRITICAL: Explicit dependency ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  # This matches the reference implementation: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf#L136
  depends_on = [module.network_public, module.network_private, module.iam]
}

#------------------------------------------------------------------------------
# Cluster Creation Timing (Optional)
#------------------------------------------------------------------------------
# Reference: ./reference/rosa-tf/environments/commercial-hcp/main.tf:774-785

module "cluster_timing" {
  source = "../modules/utility/timing"

  enabled = var.enable_timing
  stage   = "cluster-creation"

  # Track cluster completion - timing ends when cluster is ready
  # Pass cluster_id directly - Terraform will handle the dependency
  # When enabled=false, dependency_ids is ignored anyway
  dependency_ids = [module.cluster.cluster_id]
}

# Admin Password Management
# Generate random password if override is not provided
# Store password in AWS Secrets Manager for secure access
resource "random_password" "admin_password" {
  count = var.admin_password_override == null ? 1 : 0

  length           = 20
  special          = true
  upper            = true
  lower            = true
  numeric          = true
  override_special = "@#&*-_"

  # Ensure password meets ROSA requirements:
  # - 14+ characters (we use 20)
  # - Contains uppercase letter (upper = true)
  # - Contains symbol or number (special = true, numeric = true)
}

# AWS Secrets Manager secret for admin password
# Stores either the override password or the generated random password
#
# Admin Password Secret (stored in AWS Secrets Manager)
# This secret persists through sleep operations to preserve credentials for cluster restart.
# Recovery window is set to 0 to disable the 7-30 day recovery period.
# This allows immediate deletion and recreation of secrets with the same name if needed.
resource "aws_secretsmanager_secret" "admin_password" {
  # Always create secret (persists through sleep for easy cluster restart)
  # Secret persists even when persists_through_sleep=false (sleep operation)
  count = 1

  name        = "rosa-hcp-${var.cluster_name}-admin-password"
  description = "Admin password for ROSA HCP cluster ${var.cluster_name} (persists through sleep)"

  # Set recovery window to 0 to disable the recovery period (default is 30 days)
  # This allows immediate deletion and recreation of secrets with the same name
  recovery_window_in_days = 0

  tags = merge(local.tags, {
    Name                   = "rosa-hcp-${var.cluster_name}-admin-password"
    Cluster                = var.cluster_name
    ManagedBy              = "Terraform"
    Purpose                = "ClusterAdminPassword"
    persists_through_sleep = "true"
  })
}

# Store the password in the secret
# Only create/update secret version when cluster exists (not during sleep)
resource "aws_secretsmanager_secret_version" "admin_password" {
  count = var.persists_through_sleep ? 1 : 0

  secret_id     = aws_secretsmanager_secret.admin_password[0].id
  secret_string = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result

  # Allow secret to be updated manually if password changes
  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}

# Identity provider is now created in the cluster module
# See modules/infrastructure/cluster/30-identity-provider.tf

# Bastion Host (optional, for development/demo use only)
# WARNING: This bastion is provided for development and demonstration purposes only.
# For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections.
# NOTE: For egress-zero clusters, bastion_public_ip should always be false
# The bastion module creates SSM VPC endpoints required for Session Manager access
# Only create bastion when persists_through_sleep is true and network resources exist (prevents errors during sleep)
module "bastion" {
  count  = var.enable_bastion && var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../modules/infrastructure/bastion"

  name_prefix            = var.cluster_name
  vpc_id                 = local.network.vpc_id
  subnet_id              = local.network.private_subnet_ids[0] # Use first private subnet
  private_subnet_ids     = local.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                 = var.region
  vpc_cidr               = var.vpc_cidr
  bastion_public_ip      = var.bastion_public_ip # Should be false for egress-zero
  bastion_public_ssh_key = var.bastion_public_ssh_key
  persists_through_sleep = var.persists_through_sleep

  tags = var.tags

  # Terraform will infer network module dependency from vpc_id and subnet_ids references
}
