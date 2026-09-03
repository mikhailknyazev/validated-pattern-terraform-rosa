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

  custom_permissions_boundary_arn = var.custom_permissions_boundary_arn

  tags                           = local.tags
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

# Data sources for BYO VPC (network_type = "existing") - look up subnets to derive AZs and CIDRs
data "aws_subnet" "existing_private" {
  count = var.network_type == "existing" && var.existing_private_subnet_ids != null ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

data "aws_subnet" "existing_public" {
  count = var.network_type == "existing" ? length(coalesce(var.existing_public_subnet_ids, [])) : 0
  id    = coalesce(var.existing_public_subnet_ids, [])[count.index]
}

# Look up route tables for BYO VPC subnets (needed for Route Server propagation)
data "aws_route_table" "existing_private" {
  count     = var.network_type == "existing" && var.existing_private_subnet_ids != null ? length(var.existing_private_subnet_ids) : 0
  subnet_id = var.existing_private_subnet_ids[count.index]
}

data "aws_route_table" "existing_public" {
  count     = var.network_type == "existing" ? length(coalesce(var.existing_public_subnet_ids, [])) : 0
  subnet_id = coalesce(var.existing_public_subnet_ids, [])[count.index]
}

# Create a normalized network object from the active network source.
# Each branch constructs an object with identical attributes and explicit tolist()
# conversions to ensure consistent list(string) types across all branches.
# Without this normalization, Terraform's type checker fails because module splat
# expressions produce fixed-length tuples (e.g. tuple([string,string,string]))
# that are incompatible with the empty tuples from unused data sources.
locals {
  network = (
    var.network_type == "public" ? {
      vpc_id                  = module.network_public[0].vpc_id
      vpc_cidr_block          = module.network_public[0].vpc_cidr_block
      private_subnet_ids      = tolist(module.network_public[0].private_subnet_ids)
      public_subnet_ids       = tolist(module.network_public[0].public_subnet_ids)
      private_subnet_azs      = tolist(module.network_public[0].private_subnet_azs)
      private_subnet_cidrs    = tolist(module.network_public[0].private_subnet_cidrs)
      private_route_table_ids = tolist(module.network_public[0].private_route_table_ids)
      public_route_table_ids  = tolist(module.network_public[0].public_route_table_ids)
      security_group_id       = null
    } :
    var.network_type == "existing" ? {
      vpc_id                  = var.existing_vpc_id
      vpc_cidr_block          = var.vpc_cidr
      private_subnet_ids      = tolist(coalesce(var.existing_private_subnet_ids, []))
      public_subnet_ids       = tolist(coalesce(var.existing_public_subnet_ids, []))
      private_subnet_azs      = tolist([for s in data.aws_subnet.existing_private : s.availability_zone])
      private_subnet_cidrs    = tolist([for s in data.aws_subnet.existing_private : s.cidr_block])
      private_route_table_ids = tolist([for rt in data.aws_route_table.existing_private : rt.route_table_id])
      public_route_table_ids  = tolist([for rt in data.aws_route_table.existing_public : rt.route_table_id])
      security_group_id       = null
    } :
    {
      vpc_id                  = module.network_private[0].vpc_id
      vpc_cidr_block          = module.network_private[0].vpc_cidr_block
      private_subnet_ids      = tolist(module.network_private[0].private_subnet_ids)
      public_subnet_ids       = tolist([])
      private_subnet_azs      = tolist(module.network_private[0].private_subnet_azs)
      private_subnet_cidrs    = tolist(module.network_private[0].private_subnet_cidrs)
      private_route_table_ids = tolist(module.network_private[0].private_route_table_ids)
      public_route_table_ids  = tolist([])
      security_group_id       = module.network_private[0].security_group_id
    }
  )
}

# Validate BYO VPC variables when network_type = "existing"
check "byo_vpc_required_vars" {
  assert {
    condition     = var.network_type != "existing" || (var.existing_vpc_id != null && var.existing_private_subnet_ids != null && length(var.existing_private_subnet_ids) > 0)
    error_message = "When network_type is 'existing', existing_vpc_id and existing_private_subnet_ids (with at least one subnet) must be provided."
  }
}

check "external_auth_cluster_admin_conflict" {
  assert {
    # Covers: condition, error_message
    # Does: Refuses built-in OAuth resources when external authentication removes that surface.
    # Why: One shared guard keeps every authentication-mode conflict in one decision point.
    # Change: Adding another built-in OAuth feature requires extending this same condition.
    # Trap: A separate check can drift and allow an invalid mixed authentication configuration.
    # Evidence: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/authentication_and_authorization/sts-understanding-authentication
    condition     = !(var.external_auth_providers_enabled == true && (var.enable_cluster_admin == true || length(var.oidc_identity_providers) > 0))
    error_message = "enable_cluster_admin and oidc_identity_providers must be disabled when external_auth_providers_enabled is true. External auth providers reject rhcs_identity_provider resources."
  }
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
  create_kms_keys         = var.create_kms_keys
  ebs_kms_key_arn         = var.ebs_kms_key_arn
  efs_kms_key_arn         = var.efs_kms_key_arn
  etcd_kms_key_arn        = var.etcd_kms_key_arn
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

  enable_autonode                    = var.enable_autonode
  autonode_kubernetes_cluster_tag_id = var.autonode_kubernetes_cluster_tag_id

  # Permission boundaries
  rosa_permissions_boundary_arn   = var.rosa_permissions_boundary_arn
  custom_permissions_boundary_arn = var.custom_permissions_boundary_arn

  # Control plane log forwarding (new ROSA managed log forwarder)
  enable_control_plane_log_forwarding         = var.enable_control_plane_log_forwarding
  control_plane_log_cloudwatch_enabled        = var.control_plane_log_cloudwatch_enabled
  control_plane_log_cloudwatch_log_group_name = var.control_plane_log_cloudwatch_log_group_name

  # Note: cluster_credentials_secret_arn is not passed — IAM uses name-prefix ARN patterns
  # (${cluster_name}-credentials-*) so greenfield apply does not require the secret to exist yet
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

  # Proxy variables
  http_proxy              = var.http_proxy
  https_proxy             = var.https_proxy
  no_proxy                = var.no_proxy
  additional_trust_bundle = var.additional_trust_bundle

  # Cluster configuration
  # Note: zero_egress is a cluster-level ROSA API property, independent of network_type
  # However, zero egress typically requires private network (PrivateLink API endpoint)
  private            = var.private
  zero_egress        = var.zero_egress # Pass directly - cluster-level property, not tied to network
  multi_az           = var.multi_az
  availability_zones = local.network.private_subnet_azs
  fips               = var.fips

  # Break-glass HTPasswd (optional). Bootstrap uses module.bootstrap_admin instead (#29).
  # Disabled when external_auth_providers_enabled — RHCS API rejects rhcs_identity_provider.
  # Covers: enable_identity_provider, create_cluster_credentials_secret, admin_username, admin_password_for_bootstrap
  # Does: Passes plan-known lifecycle intent and apply-time password data to the cluster module.
  # Why: Separating identity from value permits greenfield and post-create toggles without targeting.
  # Change: Disabling the root boolean removes every long-lived administrator-owned resource.
  # Trap: Replacing the intent boolean with password nullability makes count unknown at plan time.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  enable_identity_provider          = var.enable_cluster_admin && var.persists_through_sleep && !(var.external_auth_providers_enabled == true)
  create_cluster_credentials_secret = var.enable_cluster_admin && !(var.external_auth_providers_enabled == true)
  admin_username                    = var.admin_username
  admin_password_for_bootstrap      = var.enable_cluster_admin && !(var.external_auth_providers_enabled == true) ? (var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result) : null

  # External authentication providers (create-time only, immutable after creation)
  external_auth_providers_enabled = var.external_auth_providers_enabled

  # KMS keys from IAM module
  kms_key_arn      = module.iam.ebs_kms_key_arn
  etcd_encryption  = var.etcd_encryption
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
  control_plane_log_cloudwatch_retention_days = var.control_plane_log_cloudwatch_retention_days
  control_plane_log_s3_enabled                = var.control_plane_log_s3_enabled
  control_plane_log_s3_bucket_name            = var.control_plane_log_s3_bucket_name
  control_plane_log_s3_bucket_prefix          = var.control_plane_log_s3_bucket_prefix
  control_plane_log_s3_retention_days         = var.control_plane_log_s3_retention_days
  resource_suffix                             = random_id.resource_suffix.hex

  image_mirrors = var.image_mirrors

  registry_config = var.registry_config

  # GitOps bootstrap configuration
  enable_gitops_bootstrap = var.enable_gitops_bootstrap != null ? var.enable_gitops_bootstrap : false
  # admin_password_for_bootstrap is set above in identity provider configuration
  # Storage resources are automatically available from cluster module outputs
  ebs_kms_key_arn    = module.iam.ebs_kms_key_arn # Use IAM module's KMS key
  efs_file_system_id = null                       # Will use cluster module's created EFS
  # GitOps repository configuration
  git_path                   = var.gitops_git_path
  gitops_git_repo_url        = var.gitops_git_repo_url
  gitops_csv                 = var.gitops_csv
  gitops_git_target_revision = var.gitops_git_target_revision
  acm_mode                   = var.acm_mode

  # Termination Protection (IAM resources are in IAM module)
  enable_termination_protection = var.enable_termination_protection

  # GitOps bootstrap configuration - IAM role ARNs from IAM module (rosa-platform-metadata)
  aws_private_ca_arn           = var.aws_private_ca_arn
  cert_manager_role_arn        = module.iam.cert_manager_role_arn
  secrets_manager_role_arn     = module.iam.secrets_manager_role_arn
  bgp_config_secret_name       = var.enable_route_server ? "${var.cluster_name}-bgp-config" : null
  channel                      = var.channel
  openshift_version            = var.openshift_version
  upgrade_acknowledgements_for = var.upgrade_acknowledgements_for
  default_machine_pool_version = var.default_machine_pool_version
  service_cidr                 = var.service_cidr
  pod_cidr                     = var.pod_cidr
  host_prefix                  = var.host_prefix

  # Default machine pool configuration
  # If not set, module will calculate defaults:
  # - Single-AZ: min = 2, max = 4
  # - Multi-AZ: min = 3, max = 6
  default_instance_type = var.default_instance_type
  default_labels        = var.default_labels
  default_taints        = var.default_taints
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
  api_endpoint_allowed_cidrs = var.api_endpoint_allowed_cidrs

  enable_autonode       = var.enable_autonode
  autonode_iam_role_arn = module.iam.autonode_role_arn

  additional_cluster_properties = var.additional_cluster_properties

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

# Break-glass admin password (only when enable_cluster_admin). Bootstrap uses module.bootstrap_admin (#29).
# Generate random password if override is not provided, then pass it to the cluster module.
# Single source of truth in AWS Secrets Manager is the cluster credentials secret
# ({cluster_name}-credentials) created in modules/infrastructure/cluster/30-identity-provider.tf.
# Fixes #28: previously a duplicate rosa-hcp-{cluster}-admin-password secret was also created here.
resource "random_password" "admin_password" {
  count = var.enable_cluster_admin && var.admin_password_override == null && !(var.external_auth_providers_enabled == true) ? 1 : 0

  length           = 20
  special          = true
  upper            = true
  lower            = true
  numeric          = true
  override_special = "@#&*-_"

  # ROSA HTPasswd: 14+ chars, uppercase, symbol or number
}

# Short-lived bootstrap HTPasswd admin (#29). Toggled by bootstrap scripts with -target.
# cluster_id comes from var (set by bootstrap-admin.sh), NOT module.cluster — so
# terraform apply -target=module.bootstrap_admin does not pull in the cluster module
# and attempt to reconcile immutable attributes (e.g. tags) when TF_VAR_tags differs.
module "bootstrap_admin" {
  source = "../modules/infrastructure/bootstrap-admin"

  # Covers: enabled, cluster_id, password, generate_password
  # Does: Converts root input presence into a plan-known bootstrap password-source choice.
  # Why: The child must not derive resource identity from an apply-time generated value.
  # Change: Supplying a password selects caller ownership; null selects child generation.
  # Trap: Passing only password leaves an unknown caller value ambiguous to the child.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  enabled           = var.enable_bootstrap_admin_user && !(var.external_auth_providers_enabled == true)
  cluster_id        = var.bootstrap_admin_cluster_id
  password          = var.bootstrap_admin_password
  generate_password = var.bootstrap_admin_password == null
}

# Break-glass identity provider + cluster credentials secret are created in the cluster module
# when enable_cluster_admin is true. See modules/infrastructure/cluster/30-identity-provider.tf

# Bastion Host (optional, for development/demo use only)
# WARNING: This bastion is provided for development and demonstration purposes only.
# For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections.
# NOTE: For egress-zero clusters, bastion_public_ip should always be false
# The bastion module creates SSM VPC endpoints required for Session Manager access
# Only create bastion when persists_through_sleep is true and network resources exist (prevents errors during sleep)
module "bastion" {
  count  = var.enable_bastion && var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../modules/infrastructure/bastion"

  name_prefix              = var.cluster_name
  vpc_id                   = local.network.vpc_id
  subnet_id                = local.network.private_subnet_ids[0] # Use first private subnet
  private_subnet_ids       = local.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                   = var.region
  vpc_cidr                 = var.vpc_cidr
  bastion_public_ip        = var.bastion_public_ip # Should be false for egress-zero
  bastion_public_ssh_key   = var.bastion_public_ssh_key
  persists_through_sleep   = var.persists_through_sleep
  permissions_boundary_arn = var.custom_permissions_boundary_arn

  tags = var.tags

  # Terraform will infer network module dependency from vpc_id and subnet_ids references
}

#------------------------------------------------------------------------------
# AWS Client VPN (recommended for private cluster access)
#------------------------------------------------------------------------------
# Creates an OpenVPN-compatible endpoint for robust access to private clusters.
# Alternative to sshuttle/bastion - works with AWS VPN Client, OpenVPN, Tunnelblick.
# Reference: ./reference/rosa-tf/modules/networking/client-vpn/

module "client_vpn" {
  count  = var.enable_client_vpn && var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../modules/infrastructure/client-vpn"

  cluster_name               = var.cluster_name
  vpc_id                     = local.network.vpc_id
  vpc_cidr                   = var.vpc_cidr
  subnet_ids                 = [local.network.private_subnet_ids[0]] # Single subnet for cost savings
  client_cidr_block          = var.vpn_client_cidr_block
  split_tunnel               = var.vpn_split_tunnel
  session_timeout_hours      = var.vpn_session_timeout_hours
  output_dir                 = "${path.root}/../clusters/${coalesce(var.cluster_config_dir, var.cluster_name)}"
  client_config_display_path = "./clusters/${coalesce(var.cluster_config_dir, var.cluster_name)}/${var.cluster_name}-vpn-client.ovpn"
  cluster_domain             = module.cluster.cluster_domain
  service_cidr               = var.service_cidr

  tags = local.tags
}

#------------------------------------------------------------------------------
# AWS VPC Route Server (for BGP routing with CUDN operator)
#------------------------------------------------------------------------------

module "route_server" {
  count  = var.enable_route_server && var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../modules/infrastructure/route-server"

  cluster_name            = var.cluster_name
  region                  = var.region
  vpc_id                  = local.network.vpc_id
  private_subnet_ids      = local.network.private_subnet_ids
  private_route_table_ids = local.network.private_route_table_ids
  public_route_table_ids  = local.network.public_route_table_ids
  oidc_endpoint_url       = module.iam.oidc_endpoint_url
  route_server_asn        = var.route_server_asn
  tags                    = local.tags
  persists_through_sleep  = var.persists_through_sleep

  # When ESO IAM is enabled, attach GetSecretValue for {cluster}-bgp-config (issue #51).
  secrets_manager_role_name = var.enable_secrets_manager_iam ? module.iam.secrets_manager_role_name : null

  custom_permissions_boundary_arn = var.custom_permissions_boundary_arn

  depends_on = [module.network_public, module.network_private, module.iam]
}
