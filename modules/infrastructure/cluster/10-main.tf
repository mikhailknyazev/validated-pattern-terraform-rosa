# Get AWS account ID (needed for cluster properties and other resources)
data "aws_caller_identity" "current" {}

locals {
  # Determine if resources persist through sleep (use override if provided, else global)
  # Note: persists_through_sleep=true means resources persist (don't destroy), which is opposite of destroy_enabled
  persists_through_sleep = var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep

  # Concatenate private and public subnet IDs for cluster resource
  # Cluster needs all subnets (private + public for public clusters, just private for private clusters)
  subnet_ids = var.private ? var.private_subnet_ids : concat(var.private_subnet_ids, var.public_subnet_ids)

  # Strip https:// prefix from OIDC endpoint URL if present (as per Red Hat documentation)
  # The OIDC endpoint URL should be in format: oidc.op1.openshiftapps.com/2nb1con7holccea7ogkfrm7ddjc8ih0q
  # Using replace() is safe - it returns the original string if the pattern isn't found
  # Used by IAM roles for CloudWatch audit logging and Cert Manager
  oidc_endpoint_url_normalized = var.oidc_endpoint_url != null ? replace(var.oidc_endpoint_url, "https://", "") : ""

  # Script paths relative to repository root
  # path.root is the root module directory (terraform/)
  # From there, scripts are at ../scripts/cluster/ relative to repo root
  termination_protection_script_path = "${path.root}/../scripts/cluster/termination-protection.sh"
  bootstrap_gitops_script_path       = "${path.root}/../scripts/cluster/bootstrap-gitops.sh"

  # AWS account ID (available via data source)
  aws_account_id = data.aws_caller_identity.current.account_id

  # Common resource suffix for consistent naming across resources
  # Used for resources that need globally unique names (e.g., S3 buckets)
  # This ensures all resources from the same cluster share the same suffix for consistency
  # Provided from root module (terraform/10-main.tf) so it can be shared across modules
  resource_suffix = var.resource_suffix != null ? var.resource_suffix : null

  # S3 bucket name for control plane logs
  # Use provided name or generate one with cluster name + random suffix
  # This local is used by both 21-control-plane-log-forwarding.tf and 22-control-plane-log-forwarding-resources.tf
  s3_bucket_name = var.control_plane_log_s3_enabled ? (
    var.control_plane_log_s3_bucket_name != null ? var.control_plane_log_s3_bucket_name : (
      local.resource_suffix != null ? "${lower(var.cluster_name)}-control-plane-logs-${local.resource_suffix}" : null
    )
  ) : null

  # Determine OpenShift version to use
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # If openshift_version is provided, use it; otherwise use the latest installable version
  openshift_version_to_use = var.openshift_version != null ? var.openshift_version : (
    # Get the latest version from the data source (last item after ordering by id)
    length(data.rhcs_versions.available.items) > 0 ? element(data.rhcs_versions.available.items, length(data.rhcs_versions.available.items) - 1).name : null
  )

  # Determine replicas and autoscaling settings
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # HCP: if unspecified and multi-az, use 1 per availability zone (total = 1 * number of AZs); if unspecified and single-az, use 2
  # NOTE: hcp_replicas is the TOTAL number of replicas across all availability zones, not per AZ
  # For ROSA HCP: multi_az=true means 3 AZs, multi_az=false means 1 AZ
  is_multi_az            = var.multi_az
  num_availability_zones = var.multi_az ? 3 : 1
  autoscaling_enabled    = true # Default pool always uses autoscaling

  # Calculate default min/max replicas per pool if not provided
  # Single-AZ: min = 2 (minimum for HA), max = 4 (double min) per pool
  # Multi-AZ: min = 1 (per AZ), max = 2 (per AZ)
  # Note: For multi-AZ clusters, replica values are per availability zone (not total)
  calculated_min_replicas_per_pool = local.is_multi_az ? 1 : 2
  calculated_max_replicas_per_pool = local.is_multi_az ? 2 : 4

  # Use user-provided values directly (they are per-AZ for multi-AZ, per-pool for single-AZ)
  default_min_replicas_per_pool = var.default_min_replicas != null ? var.default_min_replicas : local.calculated_min_replicas_per_pool
  default_max_replicas_per_pool = var.default_max_replicas != null ? var.default_max_replicas : local.calculated_max_replicas_per_pool

  # hcp_replicas is the total number of replicas across all machine pools (used at cluster level)
  # For single-AZ: 1 pool with hcp_replicas replicas
  # For multi-AZ: 3 pools, total = min_replicas_per_pool * 3
  hcp_replicas = local.is_multi_az ? (local.default_min_replicas_per_pool * local.num_availability_zones) : local.default_min_replicas_per_pool

  # Determine machine pool names - HCP creates one pool per availability zone if multi-AZ
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # NOTE: ROSA creates "workers" (plural) for single-AZ
  # For multi-AZ, ROSA creates "workers-0", "workers-1", "workers-2" (one per availability zone)
  # Use a list (not set) to match reference implementation for count-based iteration
  # Conditionally set machine pools based on destroy flag
  # For multi-AZ clusters, always generate numbered pool names
  hcp_machine_pools = local.persists_through_sleep ? (
    local.is_multi_az ? [for idx in range(local.num_availability_zones) : "workers-${idx}"] : ["workers"]
  ) : []

  # Common tags
  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
  })

  # Cluster properties
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # zero_egress property is set when zero_egress variable is true
  cluster_properties = merge(
    {
      rosa_creator_arn = data.aws_caller_identity.current.arn
    },
    var.zero_egress ? { "zero_egress" = "true" } : {}
  )

  # Additional machine pools validation
  # Ensure no name conflicts with default pools
  default_pool_names    = toset(local.hcp_machine_pools)
  additional_pool_names = keys(var.additional_machine_pools)
}

# Query available OpenShift versions
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/data-sources/versions
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
data "rhcs_versions" "available" {
  search = "enabled='t' and rosa_enabled='t' and hosted_control_plane_enabled = 't' and channel_group='${var.channel_group}'"
  order  = "id"
}

# Query available machine types for ROSA
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/data-sources/machine_types
# Note: This data source returns machine types for the current region context
data "rhcs_machine_types" "available" {}

# DNS Domain Registration
# Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:17-19
# DNS domain persists between cluster creations (not gated by persists_through_sleep)
resource "rhcs_dns_domain" "dns_domain" {
  count        = var.enable_persistent_dns_domain ? 1 : 0
  cluster_arch = "hcp"
}

# ROSA HCP Cluster
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
resource "rhcs_cluster_rosa_hcp" "main" {
  count          = local.persists_through_sleep ? 1 : 0
  name           = var.cluster_name
  cloud_region   = var.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # AWS billing account ID (optional, defaults to current account)
  aws_billing_account_id = var.aws_billing_account_id != null ? var.aws_billing_account_id : data.aws_caller_identity.current.account_id

  # Network configuration
  aws_subnet_ids     = local.subnet_ids
  availability_zones = var.availability_zones
  machine_cidr       = var.vpc_cidr # Required: VPC CIDR block

  # STS configuration - required attribute (not block)
  # Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp#sts
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
  sts = {
    role_arn             = var.installer_role_arn # role_arn is the installer role ARN (not operator role)
    support_role_arn     = var.support_role_arn
    operator_role_prefix = var.cluster_name
    oidc_config_id       = var.oidc_config_id
    oidc_endpoint_url    = var.oidc_endpoint_url
    instance_iam_roles = {
      worker_role_arn = var.worker_role_arn
    }
  }

  # Security and encryption settings
  private         = var.private
  etcd_encryption = var.etcd_encryption

  # Optional encryption - use KMS key ARN from IAM module (via variable)
  # kms_key_arn is used for root volume encryption (EBS volumes)
  kms_key_arn = var.kms_key_arn

  # Etcd encryption KMS key - use etcd KMS key ARN from IAM module (via variable)
  # Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp#etcd_kms_key_arn
  # When etcd_encryption is true, etcd_kms_key_arn must be provided
  etcd_kms_key_arn = var.etcd_encryption ? var.etcd_kms_key_arn : null

  # CloudWatch audit log forwarding
  # Note: audit_log_arn is not yet available in the official provider release
  # Audit logging is configured via script-based approach in 20-audit-logging.tf
  # Once PR is accepted, we can switch to provider-native implementation:
  # audit_log_arn = local.persists_through_sleep && var.enable_audit_logging ? (
  #   length(aws_iam_role.cloudwatch_audit_logging) > 0 ? aws_iam_role.cloudwatch_audit_logging[0].arn : null
  # ) : null

  # Network CIDR configuration
  service_cidr = var.service_cidr
  pod_cidr     = var.pod_cidr
  host_prefix  = var.host_prefix

  # DNS domain configuration
  # Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:103
  base_dns_domain = var.enable_persistent_dns_domain ? rhcs_dns_domain.dns_domain[0].id : null

  # Version configuration
  # Use determined version (provided or latest installable)
  version       = local.openshift_version_to_use
  channel_group = var.channel_group

  # Compute machine type (used for default machine pool)
  compute_machine_type = var.default_instance_type

  # Replicas for default machine pool
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # NOTE: we are only deriving this because we use the rhcs_hcp_machine_pool.default resource to manage our
  #       machine pools and we require this input for the cluster.
  # HCP: if unspecified and multi-az, use 1 per subnet; if unspecified and single-az, use 2
  # For multi-AZ: hcp_replicas should be the total number (e.g., 3 for 3 subnets with 1 per subnet)
  # For single-AZ: hcp_replicas should be 2 (minimum for HA)
  # NOTE: Cluster-level replicas must always be set (even with autoscaling) for validation
  #       Autoscaling is handled at the machine pool level, not cluster level
  replicas = local.hcp_replicas

  # EC2 metadata HTTP tokens (required for security)
  ec2_metadata_http_tokens = "required"

  # Properties
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Properties are constructed in locals.cluster_properties for better readability and maintainability
  properties = local.cluster_properties

  # Lifecycle settings
  disable_waiting_in_destroy          = false
  wait_for_create_complete            = true
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete

  tags = local.common_tags

  lifecycle {
    # CRITICAL: Destroy order is handled by Terraform's implicit dependency graph:
    # - This cluster resource depends on IAM module outputs (installer_role_arn, support_role_arn, etc.)
    # - During destroy, Terraform destroys resources in REVERSE dependency order
    # - Therefore, cluster (which depends on IAM outputs) will be destroyed BEFORE IAM resources
    # - This ensures Terraform maintains permissions to destroy the cluster
    # - No explicit depends_on needed - the dependency on IAM outputs is sufficient

    # Validate instance type is available for ROSA in the specified region
    precondition {
      condition = contains(
        [for mt in data.rhcs_machine_types.available.items : mt.id],
        var.default_instance_type
      )
      error_message = "Instance type '${var.default_instance_type}' is not available for ROSA in region '${var.region}'. Use 'terraform console' and run 'data.rhcs_machine_types.available.items' to see available machine types."
    }

    # Validate replicas is a multiple of number of availability zones for multi-AZ clusters
    # Only validate when destroy is enabled (resource will be created) and multi-AZ is enabled
    precondition {
      condition     = local.persists_through_sleep && local.is_multi_az ? (local.hcp_replicas % local.num_availability_zones == 0) : true
      error_message = "For multi-AZ clusters, replicas (${local.hcp_replicas}) must be a multiple of the number of availability zones (${local.num_availability_zones}). For ${local.num_availability_zones} AZs, use replicas like ${local.num_availability_zones}, ${local.num_availability_zones * 2}, ${local.num_availability_zones * 3}, etc."
    }

    # Validate no name conflicts between default and additional pools
    precondition {
      condition     = length(setintersection(local.default_pool_names, local.additional_pool_names)) == 0
      error_message = "Additional machine pool names cannot conflict with default pool names. Default pools: ${join(", ", local.default_pool_names)}. Conflicting names: ${join(", ", setintersection(local.default_pool_names, local.additional_pool_names))}"
    }
  }

  # Explicit dependency on IAM outputs ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  #
  # Dependency on cleanup resource ensures cleanup runs AFTER cluster is destroyed
  # On destroy: cleanup waits for cluster (reverse dependency order)
  depends_on = [
    var.installer_role_arn,
    var.support_role_arn,
    var.worker_role_arn,
    var.oidc_config_id,
    var.oidc_endpoint_url,
    null_resource.cleanup_rosa_security_groups
  ]
}

# Machine Pools
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/hcp_machine_pool
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
# For HCP, we read the default machine pools created by the cluster, then manage them
# Using count (not for_each) to match reference implementation for magic import pattern
data "rhcs_hcp_machine_pool" "default" {
  count = local.persists_through_sleep ? length(local.hcp_machine_pools) : 0

  cluster = one(rhcs_cluster_rosa_hcp.main[*].id)
  name    = local.hcp_machine_pools[count.index]
}

resource "rhcs_hcp_machine_pool" "default" {
  # Only create resources for pools that exist (magic import pattern)
  # The data source count matches local.hcp_machine_pools, so use that for resource count
  # This ensures we create resources for all expected pools, and the data source will populate values if pools exist
  # Gate with persists_through_sleep flag
  count = local.persists_through_sleep ? length(local.hcp_machine_pools) : 0

  # Use expected pool name from local.hcp_machine_pools (not from data source, which may be null)
  # For multi-AZ: "workers-0", "workers-1", "workers-2"
  # For single-AZ: "workers"
  name    = local.hcp_machine_pools[count.index]
  cluster = one(rhcs_cluster_rosa_hcp.main[*].id)

  # Handle null subnet_id - derive from count.index if data source returns null
  # Since hcp_machine_pools list matches AZ order, use count.index to map to private_subnet_ids
  # Worker nodes only go in private subnets, never public subnets
  # For multi-AZ: count.index 0 -> private_subnet_ids[0], count.index 1 -> private_subnet_ids[1], etc.
  # For single-AZ: count.index 0 -> private_subnet_ids[0]
  subnet_id = try(data.rhcs_hcp_machine_pool.default[count.index].subnet_id, null) != null ? (
    data.rhcs_hcp_machine_pool.default[count.index].subnet_id
  ) : var.private_subnet_ids[count.index % length(var.private_subnet_ids)]

  # Handle null auto_repair - default to true (standard ROSA default)
  auto_repair = try(data.rhcs_hcp_machine_pool.default[count.index].auto_repair, null) != null ? (
    data.rhcs_hcp_machine_pool.default[count.index].auto_repair
  ) : true

  # NOTE: if autoscaling is specified, replicas must be null
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Handle null replicas - use calculated value if data source returns null
  replicas = local.autoscaling_enabled ? null : (
    try(data.rhcs_hcp_machine_pool.default[count.index].replicas, null) != null ?
    data.rhcs_hcp_machine_pool.default[count.index].replicas :
    local.hcp_replicas
  )

  # Autoscaling configuration - required attribute (not block)
  # Use per-pool values directly (already calculated above)
  autoscaling = {
    enabled      = local.autoscaling_enabled
    min_replicas = local.autoscaling_enabled ? local.default_min_replicas_per_pool : null
    max_replicas = local.autoscaling_enabled ? local.default_max_replicas_per_pool : null
  }

  # AWS node pool configuration - required attribute (not block)
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Preserve instance type from data source if available, otherwise use default_instance_type
  # Handle null aws_node_pool gracefully (may be null on initial creation or subsequent applies)
  aws_node_pool = {
    instance_type = try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ? (
      data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type
    ) : var.default_instance_type
    ec2_metadata_http_tokens = try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.ec2_metadata_http_tokens, null) != null ? (
      data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.ec2_metadata_http_tokens
    ) : "required" # Default to "required" to match cluster-level setting
    tags = local.common_tags
  }

  # CRITICAL: Default machine pools are managed by Terraform for configuration (autoscaling, instance type, etc.)
  # but should NOT be deleted by Terraform during destroy. ROSA automatically deletes default machine pools
  # when the cluster is destroyed. Attempting to delete them manually causes errors because ROSA requires
  # at least 2 replicas. Setting ignore_deletion_error = true allows Terraform to gracefully handle deletion
  # failures by removing the resource from state without error, allowing cluster destruction to proceed.
  # Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/hcp_machine_pool#ignore_deletion_error
  # Reference: ./reference/terraform-provider-rhcs/docs/guides/deleting-clusters-with-removed-initial-worker-pools.md
  ignore_deletion_error = true

  lifecycle {
    # Magic import: When using data.rhcs_hcp_machine_pool, Terraform should automatically import
    # the existing machine pool if it exists. However, if the pool was deleted and recreated,
    # we may need to manually import it first using: terraform import <resource_address> <cluster_id>,<machine_pool_id>
    # The machine_pool_id can be found in the data source's id attribute after refresh.

    # Validate minimum replicas for single-AZ (must be at least 2)
    precondition {
      condition     = var.multi_az ? true : (local.hcp_replicas >= 2)
      error_message = "must have a minimum of 2 'replicas' for single az use cases."
    }

    # Validate max_replicas >= min_replicas (per pool/AZ)
    precondition {
      condition = local.autoscaling_enabled ? (
        local.default_max_replicas_per_pool >= local.default_min_replicas_per_pool
      ) : true
      error_message = "'max_replicas' (${local.default_max_replicas_per_pool} per ${local.is_multi_az ? "AZ" : "pool"}) must be greater than or equal to 'min_replicas' (${local.default_min_replicas_per_pool} per ${local.is_multi_az ? "AZ" : "pool"})."
    }

    # Validate instance type is available for ROSA in the specified region
    # Handle null aws_node_pool gracefully
    precondition {
      condition = contains(
        [for mt in data.rhcs_machine_types.available.items : mt.id],
        try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ? (
          data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type
        ) : var.default_instance_type
      )
      error_message = "Instance type '${try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ? data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type : var.default_instance_type}' is not available for ROSA in region '${var.region}'. Use 'terraform console' and run 'data.rhcs_machine_types.available.items' to see available machine types."
    }
  }
}

# Additional Custom Machine Pools
# Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:212-233
# Use for_each for stable resource addressing (better than count for dynamic resources)
resource "rhcs_hcp_machine_pool" "additional" {
  for_each = local.persists_through_sleep ? var.additional_machine_pools : {}

  cluster   = one(rhcs_cluster_rosa_hcp.main[*].id)
  name      = each.key # Pool name from map key
  subnet_id = each.value.subnet_id

  # Autoscaling configuration
  autoscaling = {
    enabled      = each.value.autoscaling_enabled
    min_replicas = each.value.autoscaling_enabled ? each.value.min_replicas : null
    max_replicas = each.value.autoscaling_enabled ? each.value.max_replicas : null
  }

  # Replicas (only if autoscaling is disabled)
  replicas = each.value.autoscaling_enabled ? null : each.value.replicas

  # Auto repair
  auto_repair = each.value.auto_repair

  # AWS Node Pool configuration
  aws_node_pool = {
    instance_type                 = each.value.instance_type
    additional_security_group_ids = length(each.value.additional_security_group_ids) > 0 ? each.value.additional_security_group_ids : null
    capacity_reservation_id       = each.value.capacity_reservation_id
    disk_size                     = each.value.disk_size
    ec2_metadata_http_tokens      = each.value.ec2_metadata_http_tokens
    tags                          = merge(local.common_tags, each.value.tags)
  }

  # Kubernetes configuration
  # Only set labels/taints/tuning_configs if they have values (provider requires at least 1 element if provided)
  labels                       = length(each.value.labels) > 0 ? each.value.labels : null
  taints                       = length(each.value.taints) > 0 ? each.value.taints : null
  kubelet_configs              = each.value.kubelet_configs
  tuning_configs               = length(each.value.tuning_configs) > 0 ? each.value.tuning_configs : null
  version                      = each.value.version
  upgrade_acknowledgements_for = each.value.upgrade_acknowledgements_for

  # Lifecycle
  ignore_deletion_error = each.value.ignore_deletion_error

  lifecycle {
    # Validate instance type is available for ROSA
    precondition {
      condition = contains(
        [for mt in data.rhcs_machine_types.available.items : mt.id],
        each.value.instance_type
      )
      error_message = "Instance type '${each.value.instance_type}' for machine pool '${each.key}' is not available for ROSA in region '${var.region}'. Use 'terraform console' and run 'data.rhcs_machine_types.available.items' to see available machine types."
    }

    # Validate subnet_id is in the private subnet_ids list (worker nodes only go in private subnets)
    precondition {
      condition     = contains(var.private_subnet_ids, each.value.subnet_id)
      error_message = "Subnet ID '${each.value.subnet_id}' for machine pool '${each.key}' must be one of the cluster's private subnet IDs: ${join(", ", var.private_subnet_ids)}"
    }

    # Validate autoscaling configuration
    precondition {
      condition = each.value.autoscaling_enabled ? (
        each.value.max_replicas >= each.value.min_replicas
      ) : true
      error_message = "For machine pool '${each.key}': max_replicas (${each.value.max_replicas}) must be greater than or equal to min_replicas (${each.value.min_replicas})"
    }
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    rhcs_hcp_machine_pool.default # Ensure default pools are created first
  ]
}

# Note: Admin user creation has been moved to a separate identity-admin module
# This allows for independent lifecycle management (create initially, remove when external IDP is configured)
# See modules/infrastructure/identity-admin/ for the admin user creation module

# API Endpoint Security Group Access Configuration
# By default, ROSA HCP creates a VPC endpoint security group that only allows access from within the VPC.
# This configuration allows adding additional IPv4 CIDR blocks to access the API endpoint.
# Reference: https://github.com/redhat-rosa/rosa-hcp-dedicated-vpc/blob/main/terraform/2.expose-api.tf

# Data source to look up ROSA-created VPC endpoint for API server access
# ROSA HCP creates a VPC endpoint for worker nodes to connect to the hosted control plane API
# This endpoint is tagged with:
# - red-hat-managed=true
# - red-hat-clustertype=rosa
# - api.openshift.com/id=<cluster_id>
data "aws_vpc_endpoint" "rosa_api" {
  count = local.persists_through_sleep && length(var.api_endpoint_allowed_cidrs) > 0 ? 1 : 0

  vpc_id = var.vpc_id

  filter {
    name   = "tag:red-hat-managed"
    values = ["true"]
  }

  filter {
    name   = "tag:red-hat-clustertype"
    values = ["rosa"]
  }

  filter {
    name   = "tag:api.openshift.com/id"
    values = [one(rhcs_cluster_rosa_hcp.main[*].id)]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Create ingress rules for each allowed CIDR block on each security group attached to the VPC endpoint
# ROSA may attach multiple security groups to the VPC endpoint
# Use for_each with a set of tuples (security_group_id, cidr) for better resource stability
locals {
  # Create a set of tuples: each security group ID paired with each CIDR block
  api_endpoint_security_group_rules = local.persists_through_sleep && length(var.api_endpoint_allowed_cidrs) > 0 && length(data.aws_vpc_endpoint.rosa_api) > 0 ? {
    for pair in flatten([
      for sg_id in data.aws_vpc_endpoint.rosa_api[0].security_group_ids : [
        for cidr in var.api_endpoint_allowed_cidrs : {
          key               = "${sg_id}_${replace(cidr, "/", "_")}"
          security_group_id = sg_id
          cidr              = cidr
        }
      ]
    ]) : pair.key => pair
  } : {}
}

resource "aws_vpc_security_group_ingress_rule" "api_endpoint_access" {
  for_each = local.api_endpoint_security_group_rules

  security_group_id = each.value.security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  description = "Allow HTTPS access to ROSA HCP API endpoint from ${each.value.cidr}"

  lifecycle {
    # Ignore changes to security_group_id as it's managed by ROSA
    ignore_changes = [
      security_group_id
    ]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    data.aws_vpc_endpoint.rosa_api
  ]
}
