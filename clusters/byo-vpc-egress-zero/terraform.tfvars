# BYO VPC + Zero Egress Cluster Configuration
#
# network_type = "existing" with zero_egress = true
# Network team must pre-provision VPC per docs/prerequisites/byo/network.md
#
# Validate: make cluster.byo-vpc-egress-zero.validate

# cluster_name = "prod-byo-ze-01"

network_type = "existing"
zero_egress  = true
private      = true
region       = "ap-southeast-2"
vpc_cidr     = "10.0.0.0/23"

existing_vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = [
  "subnet-xxxxxxxxxxxxxxxxx",
  "subnet-yyyyyyyyyyyyyyyyy",
  "subnet-zzzzzzzzzzzzzzzzz",
]
existing_public_subnet_ids = []

multi_az = true

default_instance_type = "m5.xlarge"

service_cidr = "172.30.0.0/16"
pod_cidr     = "10.128.0.0/14"
host_prefix  = 23

enable_client_vpn         = true
vpn_client_cidr_block     = "10.100.0.0/22"
vpn_split_tunnel          = true
vpn_session_timeout_hours = 12

enable_bastion    = false
bastion_public_ip = false

enable_persistent_dns_domain  = true
enable_cert_manager_iam       = true
enable_termination_protection = false

enable_cloudwatch_logging = true

enable_control_plane_log_forwarding       = true
control_plane_log_cloudwatch_enabled      = false
control_plane_log_s3_enabled              = true
control_plane_log_s3_retention_days       = 30
control_plane_log_cloudwatch_groups       = ["api", "authentication", "controller manager", "scheduler"]
control_plane_log_s3_groups               = ["api", "authentication", "controller manager", "scheduler"]
control_plane_log_cloudwatch_applications = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]
control_plane_log_s3_applications         = ["certified-operators-catalog", "cluster-api", "community-operators-catalog", "etcd", "private-router", "redhat-marketplace-catalog", "redhat-operators-catalog"]

enable_audit_logging = false

# GitOps requires CodeCommit mirroring for zero egress — see docs/egress-zero-gitops.md
# Break-glass HTPasswd admin for make cluster.<name>.login (module default is false)
enable_cluster_admin = true

enable_gitops_bootstrap = false
gitops_git_repo_url     = null
gitops_git_path         = null

enable_timing = true
