# Identity Providers and Group Memberships
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/05-identity.tf
# HTPasswd Identity Provider for Admin User
# This creates an admin user for initial cluster access
# This can be removed once an external identity provider is configured

# HTPasswd Identity Provider for Admin User
resource "rhcs_identity_provider" "admin" {
  count = var.enable_identity_provider && local.persists_through_sleep ? 1 : 0

  cluster = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null
  name    = var.admin_username
  htpasswd = {
    users = [{
      username = var.admin_username
      password = var.admin_password_for_bootstrap != null ? var.admin_password_for_bootstrap : "CHANGE_ME_PASSWORD_NOT_SET"
    }]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Add Admin User to Cluster Admins Group
# Note: Using group membership resource is deprecated, but still functional
# Consider migrating to group membership via OCM API or console when available
resource "rhcs_group_membership" "admin" {
  count = var.enable_identity_provider && local.persists_through_sleep ? 1 : 0

  user    = var.admin_username
  group   = var.admin_group
  cluster = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null

  depends_on = [rhcs_identity_provider.admin]
}

# Cluster credentials secret — single source of truth for admin credentials (Fixes #28).
# Format expected by login/info scripts and GitOps bootstrap:
# {
#   "user": "admin",
#   "password": "...",
#   "url": "https://api.cluster.example.com:6443"
# }
# Persists through sleep operations to preserve credentials for cluster restart.
# Do not create a separate plain-password Secrets Manager secret at the root module.
resource "aws_secretsmanager_secret" "cluster_credentials" {
  # Always create secret (unconditional) so name/ARN remain stable across sleep/wake
  # Secret persists even when persists_through_sleep=false (sleep operation)
  count = 1

  name                    = "${var.cluster_name}-credentials"
  description             = "Cluster credentials for ROSA HCP cluster ${var.cluster_name} (persists through sleep)"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-credentials"
    Purpose                = "ClusterCredentials"
    persists_through_sleep = "true"
  })

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Store cluster credentials in the secret
# Password should be provided via admin_password_for_bootstrap variable from infrastructure level
# If not provided, secret will be created with placeholder that must be updated manually
# The secret can be updated later via AWS CLI or console if password is not available during cluster creation
# Only create/update secret version when cluster exists (not during sleep)
resource "aws_secretsmanager_secret_version" "cluster_credentials" {
  count = local.persists_through_sleep ? 1 : 0

  secret_id = aws_secretsmanager_secret.cluster_credentials[0].id
  secret_string = jsonencode({
    user     = var.admin_username
    password = var.admin_password_for_bootstrap != null ? var.admin_password_for_bootstrap : "CHANGE_ME_PASSWORD_NOT_SET"
    url      = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].api_url) : ""
  })

  # Allow secret to be updated manually if password changes
  # Scripts will read the current value from Secrets Manager
  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_secretsmanager_secret.cluster_credentials,
    rhcs_identity_provider.admin
  ]
}
