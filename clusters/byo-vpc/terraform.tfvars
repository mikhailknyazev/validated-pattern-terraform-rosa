# BYO VPC (Bring Your Own) Cluster Configuration
#
# With network_type = "existing", NO network module runs. You must create the VPC,
# subnets, VPC endpoints, route tables, and subnet tags BEFORE running Terraform.
# This Terraform config creates IAM, cluster, and optional Client VPN.
#
# Full requirements: docs/prerequisites/byo/network.md (published site: Prerequisites → BYO Network)
#
# =============================================================================
# PREREQUISITES - Create These Before Running Terraform
# =============================================================================
#
# 1. VPC with enable_dns_support and enable_dns_hostnames enabled
# 2. Private subnets (for worker nodes) tagged: kubernetes.io/role/internal-elb = "1"
# 3. Public subnets (for external LBs, if private = false) tagged: kubernetes.io/role/elb = "1"
#
# Standard (zero_egress = false):
#   - NAT gateway(s) on private subnet route tables for internet egress
#   - VPC endpoints recommended: S3 (gateway), STS, ECR API, ECR DKR (interface)
#
# Zero egress (zero_egress = true) — see clusters/byo-vpc-egress-zero/ example:
#   - NO NAT or IGW routes on private subnets
#   - Required VPC endpoints: S3 (gateway), STS, ECR API, ECR DKR (interface, PrivateDnsEnabled)
#   - Optional: CloudWatch Logs + Monitoring endpoints if control_plane_log_cloudwatch_enabled = true
#   - EC2 and KMS endpoints in customer VPC are NOT required for ROSA HCP
#
# 4. Security group for interface VPC endpoints: inbound HTTPS (443) from VPC CIDR
#
# Validate before apply:
#   make cluster.<name>.validate
#
# Quick start: rosa create network (ROSA CLI v1.2.48+) — then adjust for zero egress if needed.
# See: https://access.redhat.com/articles/7096266
#
# =============================================================================

cluster_name = "dev-byo-vpc-01"

# Version pinning
openshift_version = "4.20.12"

# Network Configuration - BYO VPC
network_type = "existing"
zero_egress  = false
private      = false

# Required: IDs of your existing VPC and subnets (from rosa create network output or your own IaC)
# Replace with actual values from: rosa create network (or aws cloudformation describe-stacks)
region   = "ap-southeast-2"
vpc_cidr = "10.0.0.0/16"

existing_vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = [
  "subnet-xxxxxxxxxxxxxxxxx",
  "subnet-yyyyyyyyyyyyyyyyy",
  "subnet-zzzzzzzzzzzzzzzzz",
]
existing_public_subnet_ids = [
  "subnet-aaaaaaaaaaaaaaaaa",
  "subnet-bbbbbbbbbbbbbbbbb",
  "subnet-ccccccccccccccccc",
]

# Cluster Topology (should match your subnet count)
multi_az = true

# Machine Pool Configuration
default_instance_type = "m5.xlarge"

# Additional Machine Pools (subnet_index maps to existing_private_subnet_ids)
additional_machine_pools = {
  "compute-0" = {
    subnet_index        = 0
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 3
  }
  "compute-1" = {
    subnet_index        = 1
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 3
  }
  "compute-2" = {
    subnet_index        = 2
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 3
  }
}

# Bastion (optional - for private cluster API access)
enable_bastion    = false
bastion_public_ip = false

# GitOps Bootstrap
enable_gitops_bootstrap = false
gitops_git_repo_url     = null
gitops_git_path         = null

# DNS Configuration
enable_persistent_dns_domain = false

# IAM Integration
enable_cert_manager_iam = false

# Cluster Protection
enable_termination_protection = false

# Logging
enable_cloudwatch_logging = false

# Control Plane Log Forwarding
enable_control_plane_log_forwarding  = false
control_plane_log_cloudwatch_enabled = false
control_plane_log_s3_enabled         = false

# Legacy audit logging (deprecated)
enable_audit_logging = false

# Debug / Timing
enable_timing = false
