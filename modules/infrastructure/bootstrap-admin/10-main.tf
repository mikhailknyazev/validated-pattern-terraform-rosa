# Short-lived HTPasswd bootstrap admin for GitOps oc login.
# Thin wrapper around modules/infrastructure/htpasswd-idp with bootstrap defaults.
# Enabled only during bootstrap via -target=module.bootstrap_admin.
# Relates to #29 / docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md

module "idp" {
  source = "../htpasswd-idp"

  # Covers: enabled, cluster_id, password, generate_password, idp_name, username, admin_group
  # Does: Forwards one bootstrap identity and its plan-known password-source choice.
  # Why: The shared child must not infer resource count from an apply-time password.
  # Change: Changing identity values replaces or updates only the bootstrap-owned path.
  # Trap: Omitting generate_password for a generated caller value recreates unknown count.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  enabled           = var.enabled
  cluster_id        = var.cluster_id
  password          = var.password
  generate_password = var.generate_password
  idp_name          = var.idp_name
  username          = var.username
  admin_group       = var.admin_group
}

# Preserve state addresses if a bootstrap admin was mid-lifecycle during the refactor.
moved {
  from = random_password.bootstrap[0]
  to   = module.idp.random_password.this[0]
}

moved {
  from = rhcs_identity_provider.bootstrap[0]
  to   = module.idp.rhcs_identity_provider.this[0]
}

moved {
  from = rhcs_group_membership.bootstrap[0]
  to   = module.idp.rhcs_group_membership.this[0]
}
