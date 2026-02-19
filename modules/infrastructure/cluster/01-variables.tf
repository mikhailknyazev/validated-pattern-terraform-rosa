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

variable "openshift_version" {
  description = "OpenShift version to pin (optional)"
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
  default     = "helm_repo_new"
  nullable    = false
}

variable "helm_repo_url" {
  description = "URL for the Helm repository"
  type        = string
  default     = "https://rosa-hcp-dedicated-vpc.github.io/helm-repository/"
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
  default     = "0.5.4"
  nullable    = false
}

variable "gitops_csv" {
  description = "Cluster Service Version (CSV) for the GitOps operator"
  type        = string
  default     = "openshift-gitops-operator.v1.16.0-0.1746014725.p"
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

variable "ecr_account" {
  description = "ECR account ID for image pulls"
  type        = string
  default     = ""
  nullable    = true
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
  default     = "0.6.3"
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
  default     = "0.1.0"
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
  default     = "1.5.7"
  nullable    = false
}

variable "rerun_bootstrap" {
  description = "Trigger value to force re-running the bootstrap script (increment to trigger)"
  type        = string
  default     = "1"
  nullable    = false
}

variable "enable_identity_provider" {
  description = "Enable HTPasswd identity provider for admin user. If false, no identity provider will be created."
  type        = bool
  default     = true
  nullable    = false
}

variable "admin_username" {
  description = "Admin username for cluster credentials secret and identity provider (used by GitOps bootstrap). Default: 'admin'"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password_for_bootstrap" {
  description = "Admin password for cluster credentials secret and identity provider (used by GitOps bootstrap). If not provided, secret will be created with placeholder that must be updated manually."
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
