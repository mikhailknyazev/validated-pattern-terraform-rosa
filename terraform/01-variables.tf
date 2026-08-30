variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "cluster_config_dir" {
  description = <<-EOF
    Directory name under clusters/ containing this cluster's terraform.tfvars.
    Used for outputs like VPN config path. When null, defaults to cluster_name.
    Scripts pass this via -var to match the Makefile cluster directory (e.g., egress-zero).
  EOF
  type        = string
  default     = null
  nullable    = true
}

variable "network_type" {
  description = "Network topology type: 'public', 'private', or 'existing'. Use 'existing' for BYO VPC (Bring Your Own)—you provide VPC and subnet IDs; no network module runs. Zero egress mode (zero_egress) is a separate cluster-level property that can be set independently, though it typically requires 'private' network type for PrivateLink API endpoint."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["public", "private", "existing"], var.network_type)
    error_message = "network_type must be 'public', 'private', or 'existing'"
  }
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC to use (required when network_type = 'existing'). The VPC must have DNS support and hostnames enabled. You are responsible for creating the VPC, subnets, VPC endpoints, NAT gateways, and subnet tags before running Terraform."
  type        = string
  default     = null
  nullable    = true
}

variable "existing_private_subnet_ids" {
  description = "List of existing private subnet IDs for worker nodes (required when network_type = 'existing'). Subnets must be tagged with kubernetes.io/role/internal-elb = \"1\"."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "existing_public_subnet_ids" {
  description = "List of existing public subnet IDs for load balancers (optional when network_type = 'existing'). Subnets must be tagged with kubernetes.io/role/elb = \"1\". Leave empty or null for private-only clusters."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "zero_egress" {
  description = "Enable zero egress mode (no internet egress, only VPC endpoints). This is a cluster-level ROSA API property that can be set independently of network_type. However, zero egress typically requires network_type='private' (PrivateLink API endpoint) and the network module will configure infrastructure (disable NAT Gateway, enable strict egress security groups) when both conditions are met. Matches ROSA API property name."
  type        = bool
  default     = false
  nullable    = false
}

variable "private" {
  description = "Use PrivateLink API endpoint (private cluster). Independent of network_type - you can have a private cluster in a VPC with public subnets, or a public cluster in a VPC with only private subnets."
  type        = bool
  default     = true
  nullable    = false
}

variable "region" {
  description = "AWS region"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  nullable    = false
}

variable "multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = false
  nullable    = false
}

variable "default_instance_type" {
  description = "Default EC2 instance type for worker nodes (used for default machine pool)"
  type        = string
  default     = "m5.xlarge"
  nullable    = false
}

variable "default_labels" {
  description = "Labels to apply to all default machine pool nodes. Applied to all default pools (workers, workers-0/1/2 for multi-AZ)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "default_taints" {
  description = "Taints to apply to all default machine pool nodes. schedule_type must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  type = list(object({
    key           = string
    value         = string
    schedule_type = string
  }))
  default  = []
  nullable = false
}

variable "default_min_replicas" {
  description = <<-EOF
    Default minimum replicas per default machine pool. If null, the cluster module calculates bounds (single-AZ: 2 per pool; multi-AZ: 1 per AZ per pool).
    For multi-AZ, this is per pool (per AZ), not cluster total.
  EOF
  type        = number
  default     = null
  nullable    = true
}

variable "default_max_replicas" {
  description = <<-EOF
    Default maximum replicas per default machine pool. If null, the cluster module calculates bounds (single-AZ: 4 per pool; multi-AZ: 2 per AZ per pool).
    For multi-AZ, this is per pool (per AZ), not cluster total.
  EOF
  type        = number
  default     = null
  nullable    = true
}

# KMS Encryption (optional)
# External KMS keys MUST be tagged with "red-hat" = "true" for the ROSA KMS provider
# operator to access them. Without this tag, etcd encryption will fail during cluster install.
variable "create_kms_keys" {
  description = "Create KMS keys internally in the IAM module. When false (default), no keys are created unless external ARNs are provided. External ARNs always take precedence over internally created keys."
  type        = bool
  default     = false
  nullable    = false
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS root volume encryption on worker nodes. When null, no EBS encryption is applied (unless create_kms_keys is true, which creates an internal key)."
  type        = string
  default     = null
  nullable    = true
}

variable "efs_kms_key_arn" {
  description = "KMS key ARN for EFS file system encryption. When null, no EFS encryption is applied (unless create_kms_keys is true, which creates an internal key)."
  type        = string
  default     = null
  nullable    = true
}

variable "etcd_kms_key_arn" {
  description = "KMS key ARN for etcd encryption. Requires etcd_encryption = true. When null, no etcd KMS encryption is applied (unless create_kms_keys is true and etcd_encryption is true)."
  type        = string
  default     = null
  nullable    = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days (only used when create_kms_keys is true)"
  type        = number
  default     = 10
  nullable    = false
}

variable "etcd_encryption" {
  description = "Enable etcd encryption. When true, etcd_kms_key_arn must be provided (or create_kms_keys must be true to create an internal key)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_autonode" {
  description = "Enable ROSA HCP AutoNode (Karpenter): IAM policy/IRSA in the iam module, rhcs_cluster_rosa_hcp auto_node block, and subnet/SG discovery tags in the cluster module. See clusters README for preview constraints. OCM cannot disable AutoNode after enable—avoid toggling false on existing clusters."
  type        = bool
  default     = false
  nullable    = false
}

variable "autonode_kubernetes_cluster_tag_id" {
  description = "Optional explicit override for IAM policy conditions kubernetes.io/cluster/<id> used by the AutoNode controller policy. Null uses bootstrap mode on first apply and automatic cluster ID discovery/tightening on subsequent applies."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_audit_logging" {
  description = "[DEPRECATED] Enable CloudWatch audit log forwarding (legacy implementation). Use enable_control_plane_log_forwarding instead. When enabled, creates IAM role in IAM module and configures cluster to forward audit logs to CloudWatch."
  type        = bool
  default     = true
  nullable    = false
}

# Control Plane Log Forwarding (new ROSA managed log forwarder)
variable "enable_control_plane_log_forwarding" {
  description = "Enable control plane log forwarding using ROSA's managed log forwarder. Supports forwarding multiple log groups (API, Authentication, Controller Manager, Scheduler, Other) to CloudWatch and/or S3. Replaces legacy audit logging."
  type        = bool
  default     = false
  nullable    = false
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

variable "aws_private_ca_arn" {
  description = "AWS Private CA ARN for cert-manager (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "channel" {
  description = "Y-stream specific channel for the cluster version (e.g., 'stable-4.16', 'fast-4.22'). Cannot be used together with channel_group. Requires RHCS provider >= 1.7.7."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.channel == null || can(regex("^(stable|fast|candidate|eus)-\\d+\\.\\d+$", var.channel))
    error_message = "The 'channel' parameter must follow the format '<channel_group>-<version>' (e.g., 'stable-4.16', 'fast-4.22')."
  }
}

variable "openshift_version" {
  description = "OpenShift version to pin"
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

variable "fips" {
  description = "Enable FIPS 140-2 compliance"
  type        = bool
  default     = false
  nullable    = false
}

variable "flow_log_s3_bucket" {
  description = "S3 bucket name for VPC Flow Logs (optional, typically used with egress-zero)"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources (from terraform.tfvars)"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tags_override" {
  description = <<EOF
  Optional override for tags. If set, this value will be used instead of the tags variable.
  Useful for setting tags via environment variables (TF_VAR_tags_override).

  Can be provided via:
  - Environment variable: TF_VAR_tags_override (JSON format: '{"key":"value"}')
  - terraform.tfvars file
  EOF
  type        = map(string)
  default     = null
  nullable    = true
}

variable "enable_cluster_admin" {
  description = "Create a long-lived HTPasswd break-glass cluster admin and store credentials in AWS Secrets Manager. Default false. Not used by GitOps bootstrap (see enable_bootstrap_admin_user). Relates to #29."
  type        = bool
  default     = false
  nullable    = false
}

variable "external_auth_providers_enabled" {
  description = "Enable external authentication providers on the ROSA HCP cluster. When true, break-glass admin and bootstrap admin are automatically disabled (RHCS API rejects rhcs_identity_provider resources). Use 'make cluster.<name>.break-glass-login' for temporary admin access. Create-time only (immutable after cluster creation)."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_bootstrap_admin_user" {
  description = "Create short-lived HTPasswd bootstrap admin (module.bootstrap_admin). Default false. Bootstrap scripts set this true via targeted apply, then false to tear down. Relates to #29."
  type        = bool
  default     = false
  nullable    = false
}

variable "bootstrap_admin_cluster_id" {
  description = "ROSA cluster ID for module.bootstrap_admin. Set by bootstrap-admin.sh from terraform output so -target=module.bootstrap_admin does not depend on module.cluster (avoids reconciling immutable cluster tags). Leave null for normal applies."
  type        = string
  nullable    = true
  default     = null
}

variable "bootstrap_admin_password" {
  description = "Optional password for module.bootstrap_admin. When null, the module generates a random password. bootstrap-admin.sh always sets this so GitOps login does not need terraform outputs. Relates to #29."
  type        = string
  sensitive   = true
  nullable    = true
  default     = null
}

variable "admin_username" {
  description = "Break-glass admin username when enable_cluster_admin is true"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password_override" {
  description = <<EOF
  Optional override for break-glass admin password when enable_cluster_admin is true.
  If not set, a random password is generated and stored in the cluster credentials secret
  ({cluster_name}-credentials) in AWS Secrets Manager as JSON {"user","password","url"}.
  Password must be 14 characters or more, contain one uppercase letter and a symbol or number.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_admin_password_override

  Note: The password is never output by Terraform. Retrieve it with:
    aws secretsmanager get-secret-value --secret-id <secret_arn> --query SecretString --output text | jq -r .password

  Not used for GitOps bootstrap (bootstrap uses module.bootstrap_admin / bootstrap-admin.sh).
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
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

variable "enable_bastion" {
  description = <<EOF
  Enable bastion host for secure access to private cluster.

  WARNING: This bastion is provided for development and demonstration purposes only.
  For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections instead.
  EOF
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ip" {
  description = "Whether the bastion should have a public IP address. If false, access is via SSM Session Manager only (more secure). For egress-zero, this should always be false."
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ssh_key" {
  description = "Path to SSH public key file for bastion access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  nullable    = false
}

#------------------------------------------------------------------------------
# AWS Client VPN (recommended for private cluster access)
#------------------------------------------------------------------------------

variable "enable_client_vpn" {
  description = <<-EOF
    Enable AWS Client VPN endpoint for private cluster access.

    Client VPN provides robust, cross-platform access using standard OpenVPN
    clients (AWS VPN Client, OpenVPN, Tunnelblick). Recommended over
    sshuttle/bastion for teams.
  EOF
  type        = bool
  default     = false
  nullable    = false
}

variable "vpn_client_cidr_block" {
  description = "CIDR block for VPN client IP addresses. Must not overlap with VPC CIDR. Minimum /22."
  type        = string
  default     = "10.100.0.0/22"
  nullable    = false
}

variable "vpn_split_tunnel" {
  description = "Enable split tunnel mode. When true, only VPC-destined traffic goes through VPN."
  type        = bool
  default     = true
  nullable    = false
}

variable "vpn_session_timeout_hours" {
  description = "VPN session timeout in hours (8-24)."
  type        = number
  default     = 12
  nullable    = false

  validation {
    condition     = var.vpn_session_timeout_hours >= 8 && var.vpn_session_timeout_hours <= 24
    error_message = "VPN session timeout must be between 8 and 24 hours."
  }
}

# Destroy Protection Variables
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "persists_through_sleep_cluster" {
  description = "Override persists_through_sleep for cluster resources. If null, uses persists_through_sleep value."
  type        = bool
  default     = null
  nullable    = true
}

variable "persists_through_sleep_iam" {
  description = "Override persists_through_sleep for IAM resources. If null, uses persists_through_sleep value."
  type        = bool
  default     = null
  nullable    = true
}

variable "persists_through_sleep_network" {
  description = "Override persists_through_sleep for network resources. If null, uses persists_through_sleep value."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_persistent_dns_domain" {
  description = "Enable persistent DNS domain registration. When true, creates rhcs_dns_domain resource that persists between cluster creations. When false, ROSA uses default DNS domain."
  type        = bool
  default     = false
  nullable    = false
}

variable "additional_machine_pools" {
  description = <<EOF
  Map of additional machine pools to create beyond the default pools.
  Key is the pool name, value is the pool configuration.

  subnet_index: Index of the private subnet to use (0, 1, 2, etc.). Automatically maps to the actual subnet ID.

  Example:
  additional_machine_pools = {
    "compute-0" = {
      subnet_index        = 0
      instance_type       = "m5.2xlarge"
      autoscaling_enabled = true
      min_replicas        = 1
      max_replicas        = 3
    }
  }
  EOF
  type = map(object({
    subnet_index        = number # Index of private subnet (0, 1, 2, etc.)
    instance_type       = string
    autoscaling_enabled = optional(bool, true)
    min_replicas        = optional(number)
    max_replicas        = optional(number)
    replicas            = optional(number) # Only if autoscaling_enabled = false
    auto_repair         = optional(bool, true)
    labels              = optional(map(string), {})
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string # "NoSchedule", "PreferNoSchedule", "NoExecute"
    })), [])
    additional_security_group_ids = optional(list(string), [])
    capacity_reservation_id       = optional(string)
    disk_size                     = optional(number)
    ec2_metadata_http_tokens      = optional(string, "required")
    tags                          = optional(map(string), {})
    version                       = optional(string)
    upgrade_acknowledgements_for  = optional(string)
    kubelet_configs               = optional(string)
    tuning_configs                = optional(list(string), [])
    ignore_deletion_error         = optional(bool, false)
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

# Storage variables
variable "enable_efs" {
  description = "Enable EFS file system creation"
  type        = bool
  default     = null
  nullable    = true
}

# GitOps Bootstrap variables
variable "enable_gitops_bootstrap" {
  description = "Enable GitOps operator bootstrap using Helm charts after cluster creation"
  type        = bool
  default     = null
  nullable    = true
}

variable "gitops_git_repo_url" {
  description = "Git repository URL for cluster-config (e.g., https://github.com/org/cluster-config.git)"
  type        = string
  default     = null
  nullable    = true
}

variable "gitops_git_target_revision" {
  description = "Git target revision (branch/tag/commit) for cluster-config repository used by Argo CD ApplicationSet values source. Passed through to cluster-bootstrap gitTargetRevision (chart >= 0.5.18). Defaults to HEAD (default branch)."
  type        = string
  default     = "HEAD"
  nullable    = false
}

variable "gitops_git_path" {
  description = "Git path for cluster configuration directory (e.g., 'dev/pczarkow' for dev/pczarkow/infrastructure.yaml)"
  type        = string
  default     = null
  nullable    = true
}

variable "gitops_csv" {
  description = "Cluster Service Version (CSV) for the GitOps operator"
  type        = string
  default     = "openshift-gitops-operator.v1.19.2"
  nullable    = false
}

variable "acm_mode" {
  description = <<-EOF
    ACM (Advanced Cluster Management) mode for GitOps bootstrap values selection.
    - "noacm": Standalone cluster (default)
    - "hub": ACM hub cluster (uses app-of-apps-acm-team-onboarding)
    - "spoke": ACM spoke cluster (use make cluster.<name>.bootstrap-spoke)
  EOF
  type        = string
  default     = "noacm"
  nullable    = false

  validation {
    condition     = contains(["hub", "spoke", "noacm"], var.acm_mode)
    error_message = "acm_mode must be one of: hub, spoke, noacm."
  }
}

variable "enable_cert_manager_iam" {
  description = "Enable IAM role creation for cert-manager to use AWS Private CA"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_termination_protection" {
  description = "Enable cluster termination protection to prevent accidental deletion"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for OpenShift Logging Operator. When enabled, creates IAM role and policy for the OpenShift Logging Operator to send logs to CloudWatch. Uses service account: openshift-logging:cluster-logging. This is separate from audit logging (SIEM)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_secrets_manager_iam" {
  description = "Enable IAM role and policy for External Secrets Operator to access AWS Secrets Manager (IRSA for external-secrets-operator:external-secrets-sa). Secrets access is restricted to an explicit ARN list for security."
  type        = bool
  default     = false
  nullable    = false
}

variable "additional_secrets" {
  description = "Optional list of additional secret names to grant access to via Secrets Manager IAM. Secrets are looked up by name to get exact ARNs. The cluster credentials secret is always included automatically. Example: [\"my-secret-1\", \"my-secret-2\"]"
  type        = list(string)
  default     = null
  nullable    = true
}

#------------------------------------------------------------------------------
# Debug / Timing
#------------------------------------------------------------------------------

variable "enable_timing" {
  description = "Enable cluster creation timing capture. When enabled, timing information will be available in outputs."
  type        = bool
  default     = false
  nullable    = false
}

variable "additional_cluster_properties" {
  description = "Additional key/value properties to merge into the ROSA HCP cluster resource's properties block. Merged after built-in properties (rosa_creator_arn, zero_egress), so values here take precedence. Use to pass custom OCM cluster properties not exposed as dedicated variables."
  type        = map(string)
  default     = {}
  nullable    = false
}

#------------------------------------------------------------------------------
# Permission Boundaries
#------------------------------------------------------------------------------

variable "rosa_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for ROSA managed IAM roles (account + operator roles). If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}

variable "custom_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for custom IAM roles (EFS CSI, CloudWatch, Secrets Manager, cert-manager, bastion, etc.). If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}

#------------------------------------------------------------------------------
# VPC endpoint CIDR block allows for security group
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# AWS VPC Route Server (for BGP routing with CUDN operator)
#------------------------------------------------------------------------------

variable "enable_route_server" {
  description = <<-EOF
    Enable AWS VPC Route Server for BGP routing with the CUDN BGP routing operator.
    Creates a Route Server with endpoints in each private subnet, propagation to all
    route tables, and an IAM role for the operator (IRSA). Requires multi_az = true
    for production use (one BGP router per AZ).
  EOF
  type        = bool
  default     = false
  nullable    = false
}

variable "route_server_asn" {
  description = "Amazon-side ASN for the VPC Route Server. Must not conflict with the BGP local ASN used by OpenShift FRR routers."
  type        = number
  default     = 64512
  nullable    = false
}

variable "api_endpoint_allowed_cidrs" {
  description = "Optional list of IPv4 CIDR blocks allowed to access the ROSA HCP API endpoint. By default, the VPC endpoint security group only allows access from within the VPC. This variable allows you to add additional CIDR blocks (e.g., VPN ranges, bastion host IPs, or other VPCs)."
  type        = list(string)
  default     = []
  nullable    = false
}
#------------------------------------------------------------------------------
# Registry Configuration
# Passed through to the cluster module.
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp#registry_config
#------------------------------------------------------------------------------

# Covers: description, registry_config, additional_trusted_ca, type, registry_sources, allowed_registries, blocked_registries, insecure_registries, allowed_registries_for_import, domain_name, insecure, platform_allowlist_id, default, nullable, condition, error_message
# Does: Exposes the cluster module's complete registry configuration at the root.
# Why: Root validation gives callers the same policy and trust contract as the child.
# Change: Allow or block lists alter pull policy; trusted CAs alter transport trust.
# Trap: RHCS 1.7.7 requires a non-null registry_sources child for non-null config.
# Evidence: https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/cluster_rosa_hcp#nested-schema-for-registry_config
variable "registry_config" {
  description = <<-EOT
    Cluster registry configuration. Null (the default) leaves the cluster on platform
    defaults and restricts nothing. Non-null changes are updatable in place.

    The cluster module normalizes RHCS 1.7.7's required non-null registry_sources
    child and avoids its "Value Conversion Error" for CA-only input. RHCS 1.7.7
    crashes when restoring an existing registry_config to null; follow the module
    README recovery procedure instead of applying null.

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
