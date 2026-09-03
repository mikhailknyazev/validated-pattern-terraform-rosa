# Identity Providers and Group Memberships
# Break-glass HTPasswd via shared modules/infrastructure/htpasswd-idp.
# Bootstrap uses a separate instance (module.bootstrap_admin → htpasswd-idp) — both can coexist (#29).
# Single credentials secret in this module (Fixes #28) — no duplicate root plain-password secret.
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/05-identity.tf

locals {
  break_glass_enabled    = var.enable_identity_provider && local.persists_through_sleep && !(var.external_auth_providers_enabled == true)
  break_glass_password   = var.admin_password_for_bootstrap != null ? var.admin_password_for_bootstrap : "CHANGE_ME_PASSWORD_NOT_SET"
  break_glass_cluster_id = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null
  # Resource identity follows caller intent, never the generated password. The
  # separate boolean keeps the secret present while a sleeping cluster removes
  # its IDP and makes greenfield cardinality known before the password exists.
  # Covers: create_credentials_secret, condition, error_message
  # Does: Counts credentials from caller intent and requires a password only at apply.
  # Why: A generated password is unknown during planning but valid inside resource bodies.
  # Change: False removes the credentials secret while true preserves it through cluster sleep.
  # Trap: Deriving count from password nullability recreates the greenfield count failure.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  create_credentials_secret = var.create_cluster_credentials_secret
}

module "break_glass_htpasswd" {
  source = "../htpasswd-idp"

  # Covers: enabled, cluster_id, password, generate_password, idp_name, username, admin_group
  # Does: Supplies one long-lived administrator and fixes its password source as caller-owned.
  # Why: The root-generated password is unknown at plan time and cannot decide child count.
  # Change: False prevents a second child generator while preserving the supplied password.
  # Trap: Changing this to null makes child cardinality depend on password nullability again.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  enabled           = local.break_glass_enabled
  cluster_id        = local.break_glass_cluster_id
  password          = local.break_glass_enabled ? local.break_glass_password : null
  generate_password = false
  idp_name          = var.admin_username
  username          = var.admin_username
  admin_group       = var.admin_group

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Preserve state for clusters that already have break-glass IDP resources.
moved {
  from = rhcs_identity_provider.admin[0]
  to   = module.break_glass_htpasswd.rhcs_identity_provider.this[0]
}

moved {
  from = rhcs_group_membership.admin[0]
  to   = module.break_glass_htpasswd.rhcs_group_membership.this[0]
}

# Break-glass cluster credentials — single source of truth (Fixes #28).
# GitOps bootstrap does NOT use this secret — it uses module.bootstrap_admin (#29).
# Format for login/show-credentials scripts:
# {
#   "user": "admin",
#   "password": "...",
#   "url": "https://api.cluster.example.com:6443"
# }
resource "aws_secretsmanager_secret" "cluster_credentials" {
  count = local.create_credentials_secret ? 1 : 0

  name                    = "${var.cluster_name}-credentials"
  description             = "Break-glass cluster credentials for ROSA HCP cluster ${var.cluster_name} (persists through sleep)"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-credentials"
    Purpose                = "ClusterCredentials"
    persists_through_sleep = "true"
  })

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]

  lifecycle {
    precondition {
      condition     = var.admin_password_for_bootstrap != null
      error_message = "create_cluster_credentials_secret requires admin_password_for_bootstrap; the password may be unknown during plan but must be supplied at apply."
    }
  }
}

resource "aws_secretsmanager_secret_version" "cluster_credentials" {
  count = local.create_credentials_secret && local.persists_through_sleep ? 1 : 0

  secret_id = aws_secretsmanager_secret.cluster_credentials[0].id
  secret_string = jsonencode({
    user     = var.admin_username
    password = local.break_glass_password
    url      = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].api_url) : ""
  })

  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_secretsmanager_secret.cluster_credentials,
    module.break_glass_htpasswd
  ]
}
