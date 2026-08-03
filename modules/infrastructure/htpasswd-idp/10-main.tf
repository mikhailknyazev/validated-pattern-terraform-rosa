# Shared HTPasswd identity provider + cluster-admins membership.
# Used by:
# - modules/infrastructure/bootstrap-admin (short-lived bootstrap user)
# - modules/infrastructure/cluster (optional long-lived break-glass admin)
# Relates to #29 / docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md

locals {
  create = var.enabled && var.cluster_id != null && var.cluster_id != ""
  # Prefer caller-supplied password; otherwise use generated random_password.
  password = local.create ? (
    var.password != null ? var.password : random_password.this[0].result
  ) : null
}

resource "random_password" "this" {
  # Only when enabled and caller did not supply a password
  count = local.create && var.password == null ? 1 : 0

  length           = 20
  special          = true
  upper            = true
  lower            = true
  numeric          = true
  override_special = "@#&*-_"

  # ROSA HTPasswd: 14+ chars, uppercase, symbol or number
}

resource "rhcs_identity_provider" "this" {
  count = local.create ? 1 : 0

  cluster = var.cluster_id
  name    = var.idp_name
  htpasswd = {
    users = [{
      username = var.username
      password = local.password
    }]
  }
}

resource "rhcs_group_membership" "this" {
  count = local.create ? 1 : 0

  cluster = var.cluster_id
  user    = var.username
  group   = var.admin_group

  depends_on = [rhcs_identity_provider.this]
}
