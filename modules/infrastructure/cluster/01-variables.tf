# Required Variables
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID from network module (null when persists_through_sleep is false, must be set when persists_through_sleep is true)"
  type        = string
  nullable    = true

  validation {
    # When persists_through_sleep is true, resource will be created (count = 1), so vpc_id must not be null
    # When persists_through_sleep is false, resource won't be created (count = 0), so vpc_id can be null
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? var.vpc_id != null : true
    error_message = "vpc_id must not be null when persists_through_sleep is true (resource will be created)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (required for machine_cidr)"
  type        = string
  nullable    = false
}

variable "installer_role_arn" {
  description = "ARN of the Installer role from IAM module (null when persists_through_sleep is false)"
  type        = string
  nullable    = true

  validation {
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? var.installer_role_arn != null : true
    error_message = "installer_role_arn must not be null when persists_through_sleep is true (resource will be created)."
  }
}

variable "support_role_arn" {
  description = "ARN of the Support role from IAM module (null when persists_through_sleep is false)"
  type        = string
  nullable    = true

  validation {
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? var.support_role_arn != null : true
    error_message = "support_role_arn must not be null when persists_through_sleep is true (resource will be created)."
  }
}

variable "worker_role_arn" {
  description = "ARN of the Worker role from IAM module (null when persists_through_sleep is false)"
  type        = string
  nullable    = true

  validation {
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? var.worker_role_arn != null : true
    error_message = "worker_role_arn must not be null when persists_through_sleep is true (resource will be created)."
  }
}

variable "oidc_config_id" {
  description = "OIDC configuration ID from IAM module (null when persists_through_sleep is false, but OIDC is never gated)"
  type        = string
  nullable    = true
  # Note: OIDC is never gated by persists_through_sleep, but may be null if IAM module has persists_through_sleep_iam = false
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL from IAM module (null when persists_through_sleep is false, but OIDC is never gated)"
  type        = string
  nullable    = true
  # Note: OIDC is never gated by persists_through_sleep, but may be null if IAM module has persists_through_sleep_iam = false
}

# Cluster Configuration Variables (with organizational defaults)
# Note: availability_zones should come from network module output (private_subnet_azs)
variable "availability_zones" {
  description = "List of availability zones from network module. Automatically determined based on multi_az setting. (null or empty when persists_through_sleep is false)"
  type        = list(string)
  nullable    = true
  default     = []

  validation {
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? length(var.availability_zones) > 0 : true
    error_message = "availability_zones must not be empty when persists_through_sleep is true (resource will be created)."
  }
}

variable "multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = true
  nullable    = false
}

variable "aws_billing_account_id" {
  description = "The AWS billing account identifier where all resources are billed. If not provided, defaults to the current AWS account ID."
  type        = string
  default     = null
  nullable    = true
}

variable "private" {
  description = "Use PrivateLink API endpoint (organizational default: true)"
  type        = bool
  default     = true
  nullable    = false
}

variable "etcd_encryption" {
  description = "Enable etcd encryption (organizational default: false)"
  type        = bool
  default     = false
  nullable    = false
}

variable "fips" {
  description = "Enable FIPS 140-2 compliance"
  type        = bool
  default     = false
  nullable    = false
}

variable "zero_egress" {
  description = "Enable zero egress mode (egress-zero cluster). Sets zero_egress property to 'true' in cluster properties"
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for EBS volume encryption (from IAM module output). Required when cluster is created."
  type        = string
  default     = null
  nullable    = true
}

variable "etcd_kms_key_arn" {
  description = "KMS key ARN for etcd encryption (from IAM module output). Required when etcd_encryption is true."
  type        = string
  default     = null
  nullable    = true
}

variable "efs_kms_key_arn" {
  description = "KMS key ARN for EFS encryption (from IAM module output). Required when enable_efs is true."
  type        = string
  default     = null
  nullable    = true
}

# Storage Configuration
# Note: KMS keys are created in IAM module, EFS file system is created here

variable "enable_efs" {
  description = "Enable EFS file system creation (requires enable_storage = true)"
  type        = bool
  default     = true
  nullable    = false
}

variable "rosa_default_sg_wait_duration" {
  description = "Duration to wait after cluster create before looking up the ROSA default worker security group ({cluster_id}-default-sg). Hypershift tags this SG asynchronously after rhcs_cluster_rosa_hcp is ready."
  type        = string
  default     = "120s"
  nullable    = false
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks (required for EFS security group rules)"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (required for EFS mount targets and cluster creation)"
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = (var.persists_through_sleep_cluster != null ? var.persists_through_sleep_cluster : var.persists_through_sleep) == true ? length(var.private_subnet_ids) > 0 : true
    error_message = "private_subnet_ids must not be empty when persists_through_sleep is true (resource will be created)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (for public clusters, will be concatenated with private_subnet_ids for cluster subnet_ids)"
  type        = list(string)
  default     = []
  nullable    = false
}


variable "service_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "172.30.0.0/16"
  nullable    = false
}

variable "pod_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.128.0.0/14"
  nullable    = false
}

variable "host_prefix" {
  description = "Host prefix for subnet allocation"
  type        = number
  default     = 23
  nullable    = false
}

variable "channel_group" {
  description = "Channel group for OpenShift version"
  type        = string
  default     = "stable"
  nullable    = false
}

variable "channel" {
  description = "Y-stream specific channel for the cluster version (e.g., 'stable-4.16'). This parameter specifies the upgrade path for the cluster. Cannot be used together with 'channel_group'."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.channel == null || can(regex("^(stable|fast|candidate|eus)-\\d+\\.\\d+$", var.channel))
    error_message = "The 'channel' parameter must follow the format '<channel_group>-<version>' (e.g., 'stable-4.16')"
  }
}

variable "openshift_version" {
  description = "OpenShift version to pin (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "upgrade_acknowledgements_for" {
  description = "Acknowledgement for minor version upgrade (e.g., '4.22'). Required when upgrading between minor versions."
  type        = string
  default     = null
  nullable    = true
}

variable "default_machine_pool_version" {
  description = "OpenShift version for the default machine pool. If null, Terraform does not manage the worker node version. Use this to stage upgrades: first upgrade openshift_version (control plane), wait for completion, then set this to the new version."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to the cluster"
  type        = map(string)
  default     = {}
  nullable    = false
}

# Note: Admin user creation has been moved to a separate identity-admin module
# Use modules/infrastructure/identity-admin/ for admin user creation to enable independent lifecycle management

# Default machine pool values (used for default pool configuration)
variable "default_instance_type" {
  description = "Default instance type for machine pool (if machine_pools not provided)"
  type        = string
  default     = "m5.xlarge"
  nullable    = false
}

variable "default_labels" {
  description = "Labels to apply to all default machine pool nodes. Format: map of key/value strings. Applied to all default pools (workers, workers-0/1/2 for multi-AZ)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "default_taints" {
  description = "Taints to apply to all default machine pool nodes. Applied to all default pools. schedule_type must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  type = list(object({
    key           = string
    value         = string
    schedule_type = string
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for t in var.default_taints :
      contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.schedule_type)
    ])
    error_message = "Each taint schedule_type must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "default_min_replicas" {
  description = <<EOF
  Default minimum replicas per machine pool. If null, defaults are calculated:
  - Single-AZ: 2 per pool (minimum for HA)
  - Multi-AZ: 1 per availability zone (each pool gets this value)

  **Important**: For multi-AZ clusters, this value is per availability zone, not total.
  For example, if you set min_replicas = 1 for a multi-AZ cluster, each of the 3 pools
  (workers-0, workers-1, workers-2) will have 1 replica minimum (3 total minimum).
  EOF
  type        = number
  default     = null
  nullable    = true
}

variable "default_max_replicas" {
  description = <<EOF
  Default maximum replicas per machine pool. If null, defaults are calculated:
  - Single-AZ: 4 per pool (double the minimum)
  - Multi-AZ: 2 per availability zone (each pool gets this value)

  **Important**: For multi-AZ clusters, this value is per availability zone, not total.
  For example, if you set max_replicas = 2 for a multi-AZ cluster, each of the 3 pools
  (workers-0, workers-1, workers-2) will have 2 replicas maximum (6 total maximum).
  EOF
  type        = number
  default     = null
  nullable    = true
}

variable "wait_for_std_compute_nodes_complete" {
  description = <<EOF
  Wait for standard compute nodes to complete before considering cluster creation successful.

  Set to false if worker nodes may take longer to start (e.g., egress-zero clusters with network connectivity delays).
  When false, cluster creation will complete once the control plane is ready, and nodes will be created asynchronously.
  EOF
  type        = bool
  default     = true
  nullable    = false
}

# Sleep Protection Variables
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "persists_through_sleep_cluster" {
  description = "Override persists_through_sleep for cluster resources. If null, uses persists_through_sleep value. Allows sleeping cluster while preserving other resources."
  type        = bool
  default     = null
  nullable    = true
}

variable "api_endpoint_allowed_cidrs" {
  description = "Optional list of IPv4 CIDR blocks allowed to access the ROSA HCP API endpoint. By default, the VPC endpoint security group only allows access from within the VPC. This variable allows you to add additional CIDR blocks (e.g., VPN ranges, bastion host IPs, or other VPCs)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.api_endpoint_allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks in api_endpoint_allowed_cidrs must be valid IPv4 CIDR notation (e.g., '10.0.0.0/32' or '192.168.1.0/24')."
  }
}

variable "enable_audit_logging" {
  description = "[DEPRECATED] Enable CloudWatch audit log forwarding for the ROSA HCP cluster (legacy implementation). Use enable_control_plane_log_forwarding instead. When enabled, configures the cluster to forward audit logs to CloudWatch using the IAM role ARN provided via cloudwatch_audit_logging_role_arn variable (from IAM module)."
  type        = bool
  default     = true
  nullable    = false
}

variable "cloudwatch_audit_logging_role_arn" {
  description = "[DEPRECATED] ARN of the CloudWatch audit logging IAM role (from IAM module output). Required when enable_audit_logging is true. Use control_plane_log_forwarding_role_arn instead."
  type        = string
  default     = null
  nullable    = true
}

# Control Plane Log Forwarding (new ROSA managed log forwarder)
variable "enable_control_plane_log_forwarding" {
  description = "Enable control plane log forwarding using ROSA's managed log forwarder. Supports forwarding multiple log groups (API, Authentication, Controller Manager, Scheduler, Other) to CloudWatch and/or S3. Replaces legacy audit logging."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_log_forwarding_role_arn" {
  description = "ARN of the control plane log forwarding IAM role (from IAM module output). Required when enable_control_plane_log_forwarding is true."
  type        = string
  default     = null
  nullable    = true
}

variable "control_plane_log_cloudwatch_groups" {
  description = "List of log groups to forward to CloudWatch. Valid values: api, authentication, controller manager, scheduler (case-insensitive). Only used when control_plane_log_cloudwatch_enabled is true."
  type        = list(string)
  default     = ["api", "authentication", "controller manager", "scheduler"]
  nullable    = false

  validation {
    condition = alltrue([
      for group in var.control_plane_log_cloudwatch_groups : contains([
        "api", "authentication", "controller manager", "scheduler",
        "API", "Authentication", "Controller Manager", "Scheduler"
      ], group)
    ])
    error_message = "Log groups must be one of: api, authentication, controller manager, scheduler (case-insensitive)."
  }
}

variable "control_plane_log_cloudwatch_applications" {
  description = "Optional list of specific applications to forward to CloudWatch. If empty, forwards all applications for the selected log groups. Only used when control_plane_log_cloudwatch_enabled is true."
  type        = list(string)
  default     = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]
  nullable    = false
}

variable "control_plane_log_s3_groups" {
  description = "List of log groups to forward to S3. Valid values: api, authentication, controller manager, scheduler (case-insensitive). Only used when control_plane_log_s3_enabled is true."
  type        = list(string)
  default     = ["api", "authentication", "controller manager", "scheduler"]
  nullable    = false

  validation {
    condition = alltrue([
      for group in var.control_plane_log_s3_groups : contains([
        "api", "authentication", "controller manager", "scheduler",
        "API", "Authentication", "Controller Manager", "Scheduler"
      ], group)
    ])
    error_message = "Log groups must be one of: api, authentication, controller manager, scheduler (case-insensitive)."
  }
}

variable "control_plane_log_s3_applications" {
  description = "Optional list of specific applications to forward to S3. If empty, forwards all applications for the selected log groups. Only used when control_plane_log_s3_enabled is true."
  type        = list(string)
  default     = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]
  nullable    = false
}

variable "control_plane_log_cloudwatch_enabled" {
  description = "Enable CloudWatch destination for control plane log forwarding. Default disabled for cost; S3 is more cost-effective."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_log_cloudwatch_log_group_name" {
  description = "CloudWatch log group name for control plane logs. If null, uses default pattern: <cluster_name>-control-plane-logs. Must match the name used in IAM module policy."
  type        = string
  default     = null
  nullable    = true
}

variable "control_plane_log_cloudwatch_retention_days" {
  description = "Number of days to retain CloudWatch control plane logs. Valid values: 0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.control_plane_log_cloudwatch_retention_days
    )
    error_message = "Retention days must be one of: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "control_plane_log_s3_enabled" {
  description = "Enable S3 destination for control plane log forwarding. Default enabled as more cost-effective than CloudWatch."
  type        = bool
  default     = true
  nullable    = false
}

variable "control_plane_log_s3_bucket_name" {
  description = "S3 bucket name for control plane logs. If null, auto-generates a unique name using pattern: <cluster_name>-control-plane-logs-<random_suffix>. S3 bucket names must be globally unique."
  type        = string
  default     = null
  nullable    = true
}

variable "control_plane_log_s3_bucket_prefix" {
  description = "S3 bucket prefix for control plane logs. Optional prefix to organize logs within the bucket."
  type        = string
  default     = null
  nullable    = true
}

variable "control_plane_log_s3_retention_days" {
  description = "Number of days to retain control plane logs in S3 before automatic deletion. Default 30 days for cost-effectiveness. Set to null to retain indefinitely (no lifecycle rule)."
  type        = number
  default     = 30
  nullable    = true

  validation {
    condition     = var.control_plane_log_s3_retention_days == null || var.control_plane_log_s3_retention_days >= 1
    error_message = "Retention days must be at least 1 when set, or null to retain indefinitely."
  }
}

variable "resource_suffix" {
  description = "Random suffix for resource naming (from root module). Ensures consistency across all resources from the same cluster. Used for resources that need globally unique names (e.g., S3 buckets)."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_termination_protection" {
  description = "Enable cluster termination protection. When enabled, prevents accidental cluster deletion via ROSA CLI. Default: false. Note: Disabling protection requires manual action via OCM console."
  type        = bool
  nullable    = false
  default     = false
}


##############################################################
# Proxy variables
##############################################################

variable "http_proxy" {
  type        = string
  default     = null
  description = "A proxy URL to use for creating HTTP connections outside the cluster. The URL scheme must be http."
}

variable "https_proxy" {
  type        = string
  default     = null
  description = "A proxy URL to use for creating HTTPS connections outside the cluster."
}

variable "no_proxy" {
  type        = string
  default     = null
  description = "A comma-separated list of destination domain names, domains, IP addresses or other network CIDRs to exclude proxying."
}

variable "additional_trust_bundle" {
  type        = string
  default     = null
  description = "A string containing a PEM-encoded X.509 certificate bundle that will be added to the nodes' trusted certificate store."
}

variable "enable_persistent_dns_domain" {
  description = "Enable persistent DNS domain registration. When true, creates rhcs_dns_domain resource that persists between cluster creations. When false, ROSA uses default DNS domain."
  type        = bool
  default     = false
  nullable    = false
}

# Additional Machine Pool Configuration
variable "additional_machine_pools" {
  description = "Map of additional custom machine pools to create beyond the default pools. Key is the pool name, value is the pool configuration. Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:212-233"
  type = map(object({
    # Required
    subnet_id     = string
    instance_type = string

    # Optional - Autoscaling
    autoscaling_enabled = optional(bool, true)
    min_replicas        = optional(number)
    max_replicas        = optional(number)
    replicas            = optional(number) # Only if autoscaling_enabled = false

    # Optional - Advanced Features
    auto_repair = optional(bool, true)
    labels      = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string # "NoSchedule", "PreferNoSchedule", "NoExecute"
    })), [])

    # Optional - AWS Node Pool
    additional_security_group_ids = optional(list(string), [])
    capacity_reservation_id       = optional(string)
    disk_size                     = optional(number)
    ec2_metadata_http_tokens      = optional(string, "required")
    tags                          = optional(map(string), {})

    # Optional - OpenShift Configuration
    version                      = optional(string) # Pin OpenShift version for this pool
    upgrade_acknowledgements_for = optional(string)
    kubelet_configs              = optional(string)           # Name of kubelet config
    tuning_configs               = optional(list(string), []) # List of tuning config names

    # Optional - Lifecycle
    ignore_deletion_error = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.additional_machine_pools : (
        (v.autoscaling_enabled && v.min_replicas != null && v.max_replicas != null && v.replicas == null) ||
        (!v.autoscaling_enabled && v.replicas != null && v.min_replicas == null && v.max_replicas == null)
      )
    ])
    error_message = "For each additional machine pool: if autoscaling_enabled is true, min_replicas and max_replicas must be set and replicas must be null. If autoscaling_enabled is false, replicas must be set and min_replicas/max_replicas must be null."
  }
}

# GitOps Bootstrap Configuration
variable "enable_gitops_bootstrap" {
  description = "Enable GitOps operator bootstrap using Helm charts after cluster creation"
  type        = bool
  default     = false
  nullable    = false
}

variable "acm_mode" {
  description = <<EOF
  ACM (Advanced Cluster Management) mode for the cluster.
  - "noacm": Standalone cluster (default)
  - "hub": ACM hub cluster
  - "spoke": ACM spoke cluster
  EOF
  type        = string
  default     = "noacm"
  nullable    = false

  validation {
    condition     = contains(["hub", "spoke", "noacm"], var.acm_mode)
    error_message = "acm_mode must be one of: hub, spoke, noacm."
  }
}

variable "helm_repo_name" {
  description = "Name for the Helm repository"
  type        = string
  default     = "vp-rosa-gitops"
  nullable    = false
}

variable "helm_repo_url" {
  description = "URL for the Helm repository"
  type        = string
  default     = "https://rh-mobb.github.io/validated-pattern-helm-charts/"
  nullable    = false
}

variable "helm_chart" {
  description = "Helm chart name for cluster bootstrap (for hub/standalone clusters)"
  type        = string
  default     = "cluster-bootstrap"
  nullable    = false
}

variable "helm_chart_version" {
  description = "Helm chart version for cluster bootstrap"
  type        = string
  default     = "0.5.19"
  nullable    = false
}

variable "app_of_apps_infrastructure_chart_version" {
  description = "Helm chart version for app-of-apps-infrastructure (cluster-config Argo Application targetRevision in hub bootstrap values)"
  type        = string
  default     = "0.3.0"
  nullable    = false
}

variable "app_of_apps_application_chart_version" {
  description = "Helm chart version for app-of-apps-application (application-ns Argo Application targetRevision when acm_mode is not hub)"
  type        = string
  default     = "1.5.8"
  nullable    = false
}

variable "app_of_apps_acm_team_onboarding_chart_version" {
  description = "Helm chart version for app-of-apps-acm-team-onboarding (application-ns Argo Application targetRevision when acm_mode is hub)"
  type        = string
  default     = "0.4.1"
  nullable    = false
}

variable "gitops_csv" {
  description = "Cluster Service Version (CSV) for the GitOps operator"
  type        = string
  default     = "openshift-gitops-operator.v1.19.2"
  nullable    = false
}

variable "git_path" {
  description = "Git path for environment extraction (e.g., 'nonprod/np-ai-1' -> environment='nonprod')"
  type        = string
  default     = ""
  nullable    = true
}

variable "gitops_git_repo_url" {
  description = "Git repository URL for cluster-config (e.g., https://github.com/org/cluster-config.git). If not set, uses default from cluster-bootstrap chart."
  type        = string
  default     = null
  nullable    = true
}

variable "gitops_git_target_revision" {
  description = "Git target revision (branch/tag/commit) for cluster-config repository used by Argo CD ApplicationSet values source. Emitted as gitTargetRevision in hub bootstrap values (cluster-bootstrap >= 0.5.18). Defaults to HEAD (default branch). Override with a branch or tag when testing preview cluster-config."
  type        = string
  default     = "HEAD"
  nullable    = false
}

variable "ecr_account" {
  description = "ECR account ID for image pulls"
  type        = string
  default     = ""
  nullable    = true
}

variable "gitops_tools_image" {
  description = "Container image for the optional Argo CD repo-server CMP sidecar tooling. Re-host in your private registry for egress-zero or registry policy requirements; mirrored URL is passed as defaultImage in GitOps bootstrap Helm values when CMP plugin mode is enabled."
  type        = string
  default     = "ghcr.io/rh-mobb/validated-pattern-terraform-rosa/gitops-tools:latest"
  nullable    = false
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS encryption"
  type        = string
  default     = ""
  nullable    = true
}

variable "efs_file_system_id" {
  description = "EFS file system ID"
  type        = string
  default     = ""
  nullable    = true
}

# Optional variables for GitOps bootstrap (values from IAM module outputs)
variable "aws_private_ca_arn" {
  description = "AWS Private CA ARN for certificate management (for GitOps bootstrap, from IAM module)"
  type        = string
  default     = null
  nullable    = true
}

variable "cert_manager_role_arn" {
  description = "ARN of cert-manager IAM role (from IAM module output, for GitOps bootstrap)"
  type        = string
  default     = null
  nullable    = true
}

variable "secrets_manager_role_arn" {
  description = "ARN of Secrets Manager / ESO IRSA role (from IAM module output, for rosa-platform-metadata)"
  type        = string
  default     = null
  nullable    = true
}

variable "bgp_config_secret_name" {
  description = "AWS Secrets Manager secret name for CUDN BGP operator config (for rosa-platform-metadata); null when Route Server is disabled"
  type        = string
  default     = null
  nullable    = true
}

variable "awspca_csv" {
  description = "CSV for AWS Private CA Issuer operator"
  type        = string
  default     = "cert-manager-operator.v1.17.0"
  nullable    = false
}

variable "awspca_issuer" {
  description = "AWS Private CA Issuer name"
  type        = string
  default     = ""
  nullable    = true
}

variable "zone_name" {
  description = "Zone name for AWS Private CA Issuer"
  type        = string
  default     = ""
  nullable    = true
}

variable "hub_credentials_secret_name" {
  description = "Name of AWS Secrets Manager secret containing hub cluster credentials (required if acm_mode=spoke)"
  type        = string
  default     = ""
  nullable    = true
}

variable "acm_region" {
  description = "AWS region where the ACM hub cluster is located (required if acm_mode=spoke)"
  type        = string
  default     = ""
  nullable    = true
}

variable "helm_chart_acm_spoke" {
  description = "Helm chart name for ACM spoke cluster bootstrap"
  type        = string
  default     = "cluster-bootstrap-acm-spoke"
  nullable    = false
}

variable "helm_chart_acm_spoke_version" {
  description = "Helm chart version for ACM spoke cluster bootstrap"
  type        = string
  default     = "0.6.14"
  nullable    = false
}

variable "helm_chart_acm_hub_registration" {
  description = "Helm chart name for ACM hub registration"
  type        = string
  default     = "cluster-bootstrap-acm-hub-registration"
  nullable    = false
}

variable "helm_chart_acm_hub_registration_version" {
  description = "Helm chart version for ACM hub registration"
  type        = string
  default     = "0.2.2"
  nullable    = false
}

variable "helm_chart_awspca" {
  description = "Helm chart name for AWS Private CA Issuer"
  type        = string
  default     = "aws-privateca-issuer"
  nullable    = false
}

variable "helm_chart_awspca_version" {
  description = "Helm chart version for AWS Private CA Issuer"
  type        = string
  default     = "1.6.1"
  nullable    = false
}

variable "rerun_bootstrap" {
  description = "Trigger value to force re-running the bootstrap script (increment to trigger)"
  type        = string
  default     = "1"
  nullable    = false
}

variable "enable_identity_provider" {
  description = "Enable long-lived HTPasswd break-glass identity provider (root enable_cluster_admin). GitOps bootstrap uses module.bootstrap_admin instead (#29)."
  type        = bool
  default     = false
  nullable    = false
}

variable "external_auth_providers_enabled" {
  description = "Enable external authentication providers on the ROSA HCP cluster. When true, the RHCS API rejects rhcs_identity_provider resources. Create-time only (immutable after cluster creation)."
  type        = bool
  default     = null
  nullable    = true
}

variable "admin_username" {
  description = "Break-glass admin username for identity provider and credentials secret. Default: 'admin'"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password_for_bootstrap" {
  description = "Break-glass admin password for identity provider and credentials secret. Not used for GitOps bootstrap (#29)."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "admin_group" {
  description = "OpenShift group to add admin user to (default: 'cluster-admins')"
  type        = string
  default     = "cluster-admins"
  nullable    = false
}


variable "enable_autonode" {
  description = "Enable AutoNode on rhcs_cluster_rosa_hcp (auto_node block) and tag private subnets/default SG for Karpenter discovery. Requires IAM AutoNode IRSA role. OCM does not support disabling AutoNode once enabled—do not set this back to false on an existing cluster without vendor guidance."
  type        = bool
  default     = false
  nullable    = false
}

variable "autonode_iam_role_arn" {
  description = "ARN of the Karpenter IRSA role from the IAM module. Required when enable_autonode is true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !var.enable_autonode || (var.autonode_iam_role_arn != null && var.autonode_iam_role_arn != "")
    error_message = "When enable_autonode is true, autonode_iam_role_arn must be a non-empty string (IAM module AutoNode outputs)."
  }
}

variable "additional_cluster_properties" {
  description = "Additional key/value properties to merge into the ROSA HCP cluster resource's properties block. Merged after built-in properties (rosa_creator_arn, zero_egress), so values here take precedence. Use to pass custom OCM cluster properties not exposed as dedicated variables."
  type        = map(string)
  default     = {}
  nullable    = false
}

##############################################################
# Registry Image Mirrors
# See 23-image-mirrors.tf for the scope, limits and references.
##############################################################

# Covers: description, image_mirrors, type, default, nullable, condition, error_message
# Does: Defines source-keyed ordered digest-mirror mappings and rejects malformed paths.
# Why: A typed map makes API identity explicit and catches invalid references before apply.
# Change: Changing a key replaces one mirror; changing its list updates that mapping.
# Trap: Tags, URL schemes, digest suffixes, and empty lists cannot express this API.
# Evidence: https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/image_mirror
variable "image_mirrors" {
  description = <<-EOT
    Digest-based registry mirrors for the cluster, applied after cluster creation.

    Map key   = the SOURCE repository path being mirrored, for example
                "registry.redhat.io" or "quay.io/prometheus". This is a repository
                path: no URL scheme, no ":tag" suffix, no "@sha256:..." digest.
    Map value = an ordered list of mirror repository paths. Mirrors are tried in the
                order given, so put the closest or most reliable mirror first.

    Only image references pinned BY DIGEST are rewritten; references by tag are not,
    and the mirror must hold byte-identical manifests for the digests to match. Read
    the limits at the top of 23-image-mirrors.tf before relying on this.

    Keys are the Terraform resource addresses and the source is immutable in the API,
    so editing a key destroys and recreates that one mirror. Terraform leaves the
    other mirror resource addresses unchanged, but live ROSA HCP 4.22.5 testing found
    that mirror create and delete were followed by a managed worker roll. Treat the
    apply as a disruption window; editing only an existing mirrors list was not tested.

    Example:
      image_mirrors = {
        "registry.redhat.io" = ["mirror.example.com/redhat"]
        "quay.io/prometheus" = ["mirror.example.com/quay-prometheus"]
      }
  EOT
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    # A URL scheme or a digest suffix is the most common way to get this wrong: these
    # are repository paths, not URLs and not fully-qualified image references.
    condition = alltrue([
      for src in keys(var.image_mirrors) :
      src != "" &&
      !startswith(lower(src), "http://") &&
      !startswith(lower(src), "https://") &&
      !strcontains(src, "@")
    ])
    error_message = "image_mirrors keys must be non-empty repository paths with no URL scheme and no digest (e.g. \"registry.redhat.io\", not \"https://registry.redhat.io\" and not \"registry.redhat.io/ubi@sha256:...\")."
  }

  validation {
    # A ":tag" suffix on the source is a path mistake. Only checked when the path has
    # more than one segment, so a legitimate registry port such as "host:5000" is not
    # flagged.
    condition = alltrue([
      for src in keys(var.image_mirrors) :
      length(split("/", src)) < 2 ? true : !strcontains(element(split("/", src), length(split("/", src)) - 1), ":")
    ])
    error_message = "image_mirrors keys must not carry a tag suffix (e.g. use \"registry.redhat.io/ubi9\", not \"registry.redhat.io/ubi9:latest\")."
  }

  validation {
    # An empty mirror list would create a mirror object that redirects nowhere.
    condition     = alltrue([for mirrors in values(var.image_mirrors) : length(mirrors) > 0])
    error_message = "Each image_mirrors entry must list at least one mirror repository path."
  }

  validation {
    # Mirrors are repository paths under the same rules as the source.
    condition = alltrue([
      for mirrors in values(var.image_mirrors) : alltrue([
        for mirror in mirrors :
        mirror != "" &&
        !startswith(lower(mirror), "http://") &&
        !startswith(lower(mirror), "https://") &&
        !strcontains(mirror, "@")
      ])
    ])
    error_message = "image_mirrors values must be non-empty repository paths with no URL scheme and no digest."
  }
}

##############################################################
# Registry Configuration
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp#registry_config
##############################################################

# Covers: description, registry_config, additional_trusted_ca, type, registry_sources, allowed_registries, blocked_registries, insecure_registries, allowed_registries_for_import, domain_name, insecure, platform_allowlist_id, default, nullable, condition, error_message
# Does: Defines the complete typed registry policy, trust, and import contract.
# Why: Typed nested fields expose cluster-wide effects and fail malformed input early.
# Change: Allow or block lists alter pull policy; trusted CAs alter transport trust.
# Trap: RHCS 1.7.7 requires a non-null registry_sources child for non-null config.
# Evidence: https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/cluster_rosa_hcp#nested-schema-for-registry_config
variable "registry_config" {
  description = <<-EOT
    Cluster registry configuration. Null (the default) leaves the cluster on platform
    defaults and restricts nothing. Non-null changes are updatable in place.

    RHCS 1.7.7 raises "Value Conversion Error" when a non-null value omits the
    registry_sources child. This module supplies that complete child with null
    members so CA-only input remains valid without sending empty source lists.
    RHCS 1.7.7 also crashes when restoring an existing registry_config to null;
    follow the recovery procedure in the module README instead of applying null.

    Fields:

      registry_sources.allowed_registries
        Registries the container runtime may pull and push for builds and pods.
        DANGER: setting this switches the cluster to DENY-BY-DEFAULT -- every registry
        not listed is blocked, including ones the platform itself needs. The failure
        appears at the next pod schedule rather than at apply time, so an incomplete
        list looks like a successful apply followed by unrelated breakage hours later.
        Not required to make image mirroring work. Test on a non-production cluster.
        Mutually exclusive with blocked_registries. Supports a leading "*" wildcard,
        e.g. "*.example.com".

      registry_sources.blocked_registries
        The inverse: everything is allowed except these. Mutually exclusive with
        allowed_registries.

      registry_sources.insecure_registries
        Registries reached over HTTP or without a valid TLS certificate. Prefer
        additional_trusted_ca over marking a registry insecure.

      additional_trusted_ca
        Map of registry hostname => PEM-encoded CA certificate. This is the field that
        makes a mirror behind a private certificate authority usable: without it the
        pull fails with "x509: certificate signed by unknown authority". Values must be
        the certificate itself, not a path to one.

      allowed_registries_for_import
        Registries users may import ImageStreams from. Narrower than registry_sources:
        it governs ImageStream import only, not pod image pulls. Do not reach for this
        expecting it to control what workloads can pull.

      platform_allowlist_id
        Reference to a RegistryAllowlist of internal registries that must stay reachable
        for the platform to work. Its lifecycle can be managed separately. Relevant when
        using allowed_registries.

    Example -- trust a private mirror's CA, without restricting anything:

      registry_config = {
        additional_trusted_ca = {
          "mirror.example.com" = file("mirror-ca.pem")
        }
      }
  EOT

  type = object({
    registry_sources = optional(object({
      allowed_registries  = optional(list(string))
      blocked_registries  = optional(list(string))
      insecure_registries = optional(list(string))
    }))
    allowed_registries_for_import = optional(list(object({
      domain_name = optional(string)
      insecure    = optional(bool)
    })))
    additional_trusted_ca = optional(map(string))
    platform_allowlist_id = optional(string)
  })
  default  = null
  nullable = true

  validation {
    # The API rejects both at once. Catching it here gives a readable error at plan time
    # instead of an API error partway through an apply.
    condition = (
      var.registry_config == null ||
      try(var.registry_config.registry_sources, null) == null ||
      length(coalesce(try(var.registry_config.registry_sources.allowed_registries, null), [])) == 0 ||
      length(coalesce(try(var.registry_config.registry_sources.blocked_registries, null), [])) == 0
    )
    error_message = "registry_config.registry_sources.allowed_registries and blocked_registries are mutually exclusive; set at most one."
  }

  validation {
    # A path, a bare base64 blob, or an empty string are the usual mistakes here. Anything
    # that is not a PEM certificate will fail at pull time, far from the change that caused it.
    condition = (
      var.registry_config == null ||
      try(var.registry_config.additional_trusted_ca, null) == null ||
      alltrue([
        for host, cert in coalesce(var.registry_config.additional_trusted_ca, {}) :
        host != "" && startswith(trimspace(cert), "-----BEGIN CERTIFICATE-----")
      ])
    )
    error_message = "registry_config.additional_trusted_ca must map a non-empty registry hostname to a PEM-encoded certificate beginning with \"-----BEGIN CERTIFICATE-----\" (the certificate itself, not a path to it)."
  }

  validation {
    # domain_name is optional in the provider schema, but an entry without one configures
    # nothing and is silently ignored.
    condition = (
      var.registry_config == null ||
      try(var.registry_config.allowed_registries_for_import, null) == null ||
      alltrue([
        for entry in coalesce(var.registry_config.allowed_registries_for_import, []) :
        try(entry.domain_name, null) != null && try(entry.domain_name, "") != ""
      ])
    )
    error_message = "Each registry_config.allowed_registries_for_import entry must set a non-empty domain_name."
  }
}
