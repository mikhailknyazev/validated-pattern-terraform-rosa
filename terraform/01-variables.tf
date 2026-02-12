variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "network_type" {
  description = "Network topology type: 'public' or 'private'. Zero egress mode (zero_egress) is a separate cluster-level property that can be set independently, though it typically requires 'private' network type for PrivateLink API endpoint."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["public", "private"], var.network_type)
    error_message = "network_type must be 'public' or 'private'"
  }
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

# Production variables (optional, typically used with egress-zero)
variable "kms_key_arn" {
  description = "KMS key ARN for encryption (legacy - KMS keys are now created in IAM module)"
  type        = string
  default     = null
  nullable    = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 10
  nullable    = false
}

variable "etcd_encryption" {
  description = "Enable etcd encryption (requires etcd KMS key from IAM module)"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_audit_logging" {
  description = "Enable CloudWatch audit log forwarding. When enabled, creates IAM role in IAM module and configures cluster to forward audit logs to CloudWatch."
  type        = bool
  default     = true
  nullable    = false
}

variable "aws_private_ca_arn" {
  description = "AWS Private CA ARN for cert-manager (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "openshift_version" {
  description = "OpenShift version to pin"
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

variable "token" {
  description = <<EOF
  OCM token used to authenticate against the OpenShift Cluster Manager API.
  See https://console.redhat.com/openshift/token/rosa/show to access your token.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_token
  - Environment variable: OCM_TOKEN or ROSA_TOKEN (provider will check these if token is not set)
  EOF
  type        = string
  sensitive   = true
  nullable    = false
}

variable "admin_username" {
  description = "Admin username for cluster authentication"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password_override" {
  description = <<EOF
  Optional override for admin password. If not set, a random password will be generated and stored in AWS Secrets Manager.
  Password must be 14 characters or more, contain one uppercase letter and a symbol or number.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_admin_password_override

  Note: The password is never output by Terraform. Use AWS CLI to retrieve it:
    aws secretsmanager get-secret-value --secret-id <secret_arn> --query SecretString --output text
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
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

variable "gitops_git_path" {
  description = "Git path for cluster configuration directory (e.g., 'dev/pczarkow' for dev/pczarkow/infrastructure.yaml)"
  type        = string
  default     = null
  nullable    = true
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
  description = "Enable IAM role and policy for ArgoCD Vault Plugin to access AWS Secrets Manager. When enabled, creates IAM role for openshift-gitops:vplugin service account. Secrets access is restricted to explicit ARN list for security."
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
