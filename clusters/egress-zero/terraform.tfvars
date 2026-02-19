# Infrastructure Configuration
# This file contains variables for the infrastructure layer (VPC, network, cluster creation)

# cluster_name = "prod-egress-zero-01"

# Network Configuration
network_type = "public" # NOTE: A real egress-zero would use "private" but needs Git access via CodeCommit/VPC endpoints
zero_egress  = true     # Enables zero egress mode (no internet egress, only VPC endpoints). Matches ROSA API property name.
private      = true     # Private API endpoint (PrivateLink). Independent of network_type - can have private API in VPC with public subnets
region       = "ap-southeast-2"
vpc_cidr     = "10.30.0.0/16"

# Bastion Host
enable_bastion    = true  # Required for egress-zero clusters (SSM Session Manager access)
bastion_public_ip = false # SSM-only access (required for egress-zero, no public IP)

# Cluster Topology
multi_az = true # Multi-AZ for production HA (availability zones automatically determined)
# Note: For multi-AZ clusters, default_min_replicas and default_max_replicas are per-AZ values
# Example: min_replicas=1 means 1 replica per pool (3 total for 3 pools: workers-0, workers-1, workers-2)


# Machine Pool Configuration
default_instance_type = "m5.xlarge" # EC2 instance type for default worker nodes
# default_min_replicas and default_max_replicas use module defaults:
# - Multi-AZ: min=1, max=2 per AZ (each pool gets these values, 3 total min, 6 total max)

# Encryption
# kms_key_arn      = "arn:aws:kms:us-east-1:123456789012:key/abc123..."

# Version pinning for production
# openshift_version = "4.19.18"

# Network CIDRs
service_cidr = "172.30.0.0/16" # CIDR block for Kubernetes services
pod_cidr     = "10.128.0.0/14" # CIDR block for pods
host_prefix  = 23              # Host prefix for subnet allocation

# Compliance
fips = false # Set to true for FIPS 140-2 compliance (requires FIPS-compliant instance types)

# Audit logging
# flow_log_s3_bucket = "my-org-vpc-flow-logs"

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
    max_replicas        = 2
  }
  "compute-1" = {
    subnet_index        = 1
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 2
  }
  "compute-2" = {
    subnet_index        = 2
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 2
  }
}

# Destroy protection - set to true to allow resource destruction
# enable_destroy = false

# tags = {
#   Environment = "production"
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

# GitOps Bootstrap
enable_gitops_bootstrap = true # Enable GitOps operator installation after cluster creation
gitops_git_repo_url     = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path         = "dev/pczarkow" # Path to cluster configuration directory in Git repo

# Debug / Timing
enable_timing = true # Enable cluster creation timing capture