# Infrastructure Configuration for RHAI cluster
# Red Hat AI on OpenShift demo/lab cluster

cluster_name = "rhai"

# Version pinning
openshift_version = "4.22.8"

# Network Configuration
network_type = "public"
zero_egress  = false
private      = false
region       = "ap-southeast-2"
vpc_cidr     = "10.20.0.0/16"

# Cluster Topology
multi_az = false

# Machine Pool Configuration
default_instance_type = "m5.2xlarge"

# Break-glass HTPasswd admin for make cluster.<name>.login
enable_cluster_admin = true

# GitOps Bootstrap
enable_gitops_bootstrap = true
gitops_git_repo_url     = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path         = "dev/rhai"

# Additional Machine Pools
additional_machine_pools = {
  "compute-0" = {
    subnet_index        = 0
    instance_type       = "m5.xlarge"
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 2
  }
  # "compute-1" = {
  #   subnet_index        = 0
  #   instance_type       = "m5.xlarge"
  #   autoscaling_enabled = false
  #   replicas            = 1
  # }
  # "infra" = {
  #   subnet_index          = 0
  #   instance_type         = "m5.xlarge"
  #   autoscaling_enabled   = false # Changed from True to False
  #   replicas              = 3
  #   # min_replicas        = 1   # Must be set to Null
  #   # max_replicas        = 3   # Must be set to Null
  #   version               = "4.22.4"
  # }
}

# Optional Features - minimal for lab/demo
persists_through_sleep        = true
enable_persistent_dns_domain  = false
enable_control_plane_log_forwarding  = true
control_plane_log_cloudwatch_enabled = true
enable_cert_manager_iam       = false
enable_termination_protection = false

# Debug / Timing
enable_timing = true
