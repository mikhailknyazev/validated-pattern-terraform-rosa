# BGP Test Cluster Configuration
# ROSA HCP with VPC Route Server for CUDN BGP routing operator testing
#
# Post-deploy (preferred, issue #51):
# 1. enable_secrets_manager_iam + enable_route_server publish {cluster}-bgp-config to SM
# 2. GitOps installs ESO + cudn-bgp-routing-operator with externalSecret.enabled
# 3. Chart Job applies IRSA annotation + CUDNBgpConfig aws.* from the synced Secret
# Manual SA annotate / hardcoded routeServerIDs in cluster-config are no longer required.

cluster_name = "bgp"

# Version - OCP 4.21+ required for FRR-K8s, CUDN, and RouteAdvertisements
openshift_version = "4.22.2"
channel           = "fast-4.22"

# Network Configuration
network_type = "public"
zero_egress  = false
private      = false
region       = "ap-southeast-2"
vpc_cidr     = "10.0.0.0/16"

# Multi-AZ required for BGP (one router per AZ)
multi_az = true

# Default worker pool — m7i.2xlarge (8 vCPU / 32 GiB) for GitOps/build headroom;
# m5.xlarge packed out during ESO + operator image builds (Pending pods).
default_instance_type = "m7i.2xlarge"
default_min_replicas  = 1
default_max_replicas  = 2

# BGP Route Server + ESO IAM (Secrets Manager secret {cluster}-bgp-config)
enable_route_server        = true
route_server_asn           = 64512
enable_secrets_manager_iam = true

# BGP Router Machine Pools - one baremetal node per AZ
# Labels match the operator's routerNodeSelector (bgp_router: "true")
# and per-AZ selectors (bgp_router_subnet, az)
additional_machine_pools = {
  "bgp-router-0" = {
    subnet_index        = 0
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "1"
      az                = "1"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "1"
      az                = "1"
    }
    ec2_metadata_http_tokens = "required"
  }
  "bgp-router-1" = {
    subnet_index        = 1
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "2"
      az                = "2"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "2"
      az                = "2"
    }
    ec2_metadata_http_tokens = "required"
  }
  "bgp-router-2" = {
    subnet_index        = 2
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "3"
      az                = "3"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "3"
      az                = "3"
    }
    ec2_metadata_http_tokens = "required"
  }
}

# GitOps Bootstrap - installs OpenShift Virtualization via ArgoCD
# Break-glass HTPasswd admin for make cluster.bgp.login (module default is false)
enable_cluster_admin = true

enable_gitops_bootstrap    = true
gitops_git_repo_url        = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path            = "dev/bgp"
gitops_git_target_revision = "HEAD"

# DNS
enable_persistent_dns_domain = true

# Disable features not needed for BGP testing
enable_cert_manager_iam             = false
enable_termination_protection       = false
enable_cloudwatch_logging           = false
enable_audit_logging                = false
enable_control_plane_log_forwarding = false

# Timing
enable_timing = true
