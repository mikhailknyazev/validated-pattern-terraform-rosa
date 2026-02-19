# Infrastructure Configuration
# This file contains variables for the infrastructure layer (VPC, network, cluster creation)

# cluster_name      = "dev-public-01"

# Version pinning for production
openshift_version = "4.20.12"

# Network Configuration
network_type = "public" # Public clusters use NAT Gateway for internet egress
zero_egress  = false    # Public clusters don't use zero egress (have internet access). Matches ROSA API property name.
private      = false    # Public API endpoint (independent of network_type - can have public API in private VPC or vice versa)
region       = "ap-southeast-2"
vpc_cidr     = "10.10.0.0/16"

# Cluster Topology
multi_az = false # Single AZ for dev cost savings (availability zones automatically determined)
# Note: For multi-AZ clusters, default_min_replicas and default_max_replicas are per-AZ values
# Example: min_replicas=1 means 1 replica per pool (3 total for 3 pools)

# Machine Pool Configuration
default_instance_type = "m5.xlarge" # EC2 instance type for default worker nodes
# default_min_replicas and default_max_replicas use module defaults:
# - Single-AZ: min=2, max=4 per pool
# - Multi-AZ: min=1, max=2 per AZ (each pool gets these values)

# GitOps Bootstrap
enable_gitops_bootstrap = true # Enable GitOps operator installation after cluster creation
gitops_git_repo_url     = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path         = "dev/pczarkow" # Path to cluster configuration directory in Git repo

# Additional Machine Pools
# Create custom machine pools beyond the default pool
# subnet_index: 0 = first AZ, 1 = second AZ, 2 = third AZ, etc.
# Note: Replica values are per-pool (not per-AZ like default pools)
additional_machine_pools = {
  "compute-0" = {
    subnet_index        = 0
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 3
  }
  # Uncomment for multi-AZ clusters:
  # "compute-1" = {
  #   subnet_index        = 1
  #   instance_type       = "m5.xlarge"
  #   autoscaling_enabled = true
  #   min_replicas        = 1
  #   max_replicas        = 3
  # }
  # "compute-2" = {
  #   subnet_index        = 2
  #   instance_type       = "m5.xlarge"
  #   autoscaling_enabled = true
  #   min_replicas        = 1
  #   max_replicas        = 3
  # }
}

# Destroy protection - set to true to allow resource destruction
# enable_destroy = false

# tags = {
#   Environment = "development"
#   ManagedBy   = "terraform"
#   Project     = "rosa-hcp"
# }

# DNS Configuration
enable_persistent_dns_domain = true # Use persistent DNS domain that survives cluster recreation

# IAM Integration
enable_cert_manager_iam = true # Create IAM role for cert-manager to use AWS Private CA

# Cluster Protection
enable_termination_protection = false # Prevent accidental cluster deletion (requires OCM console to disable)

# Logging
enable_cloudwatch_logging = true # Enable CloudWatch logging for OpenShift Logging Operator

# Control Plane Log Forwarding (new ROSA managed log forwarder)
enable_control_plane_log_forwarding         = true
control_plane_log_cloudwatch_groups         = ["api", "authentication", "controller manager", "scheduler"]
control_plane_log_cloudwatch_applications   = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]
control_plane_log_s3_groups                 = ["api", "authentication", "controller manager", "scheduler"]
control_plane_log_s3_applications           = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]
control_plane_log_cloudwatch_enabled        = false
control_plane_log_cloudwatch_log_group_name = null
control_plane_log_s3_enabled                = true
control_plane_log_s3_bucket_name            = null
control_plane_log_s3_bucket_prefix          = null
control_plane_log_s3_retention_days         = 30

# Legacy audit logging (deprecated - disable when control plane log forwarding is enabled)
enable_audit_logging = false # Disable legacy audit logging in favor of new control plane log forwarding

# Debug / Timing
enable_timing = true # Enable cluster creation timing capture
