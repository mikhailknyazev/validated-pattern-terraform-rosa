# Minimal ROSA HCP cluster with AutoNode (Karpenter) — Private Preview style example
# See clusters/README.md ("AutoNode") and issue #15 for constraints.

# cluster_name = "autonode"

# AutoNode preview constraints (verify current Red Hat docs / your preview program):
# - AWS region typically must be us-east-1
# - OpenShift version >= 4.19
# Enablement is Terraform rhcs_cluster_rosa_hcp `auto_node` (no ROSA CLI required).
openshift_version = "4.22.0"
region            = "us-east-1"

network_type = "public"
zero_egress  = false
private      = false

vpc_cidr = "10.1.0.0/16"

multi_az = false

# default_instance_type = "m6g.xlarge"
default_min_replicas = 2
default_max_replicas = 2

additional_machine_pools = {}

persists_through_sleep = true

enable_gitops_bootstrap      = true
gitops_git_repo_url          = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path              = "dev/autonode"
gitops_git_target_revision   = "HEAD" # Default branch of cluster-config repo
enable_persistent_dns_domain = false

# AutoNode: Terraform creates Karpenter IAM + tags + rhcs_cluster_rosa_hcp auto_node block
enable_autonode = true

# Optional: if Karpenter fails to launch nodes after apply, set this to the ROSA cluster ID
# from `terraform output cluster_id` so IAM policy kubernetes.io/cluster/<id> matches AWS tags.
# autonode_kubernetes_cluster_tag_id = "your-rhcs-cluster-id"

# additional_cluster_properties = {
#   provision_shard_id = "9f11dd2b-98c1-11f0-8fe5-0a580a830a08"
# }

# Minimal optional features for a lab cluster
enable_audit_logging                = false
enable_control_plane_log_forwarding = false
enable_cloudwatch_logging           = false
enable_cert_manager_iam             = false
enable_termination_protection       = false

enable_timing = true
