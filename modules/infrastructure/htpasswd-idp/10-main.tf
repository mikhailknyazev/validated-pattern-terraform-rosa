# Shared HTPasswd identity provider + cluster-admins membership.
# Used by:
# - modules/infrastructure/bootstrap-admin (short-lived bootstrap user)
# - modules/infrastructure/cluster (optional long-lived break-glass admin)
# Relates to #29 / docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md

locals {
  # Count MUST depend only on var.enabled (a known bool). Do not gate on cluster_id:
  # on greenfield apply cluster_id is "(known after apply)", which makes
  # `cluster_id != null && cluster_id != ""` unknown and fails plan with
  # "Invalid count argument". Callers set enabled=false when no IDP is wanted
  # (bootstrap-admin leaves cluster_id null until the targeted create step).
  create = var.enabled
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

  lifecycle {
    precondition {
      condition     = var.cluster_id != null && var.cluster_id != ""
      error_message = "htpasswd-idp: cluster_id must be set when enabled=true (got null/empty)."
    }
  }
}

resource "rhcs_group_membership" "this" {
  count = local.create ? 1 : 0

  cluster = var.cluster_id
  user    = var.username
  group   = var.admin_group

  depends_on = [rhcs_identity_provider.this]
}
