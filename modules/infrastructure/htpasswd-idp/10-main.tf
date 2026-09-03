# Shared HTPasswd identity provider + cluster-admins membership.
# Used by:
# - modules/infrastructure/bootstrap-admin (short-lived bootstrap user)
# - modules/infrastructure/cluster (optional long-lived break-glass admin)
# Relates to #29 / docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md

locals {
  # Every resource count must depend only on plan-known intent. Neither
  # cluster_id nor password is guaranteed known: a greenfield cluster id and a
  # caller-generated password are both apply-time values. Callers therefore
  # state whether the IDP exists and, when needed, who generates its password.
  # Resource bodies may consume those unknown values after identity is fixed.
  create = var.enabled
  # Covers: generate_password
  # Does: Resolves explicit source intent before falling back to compatibility inference.
  # Why: An explicit choice stays known when the caller's generated value does not.
  # Change: Null preserves the prior literal-password and omitted-password interface.
  # Trap: Unknown password nullability is unsafe unless the caller chooses explicitly.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  generate_password = var.generate_password != null ? var.generate_password : var.password == null
  password = local.create ? (
    local.generate_password ? random_password.this[0].result : var.password
  ) : null
}

resource "random_password" "this" {
  # Covers: count
  # Does: Creates a password only from plan-known module intent.
  # Why: Terraform must know resource cardinality before any generated value exists.
  # Change: False removes this child generator without changing caller-owned passwords.
  # Trap: Counting from var.password reintroduces Invalid count argument for generated callers.
  # Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
  count = local.create && local.generate_password ? 1 : 0

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

    precondition {
      # Covers: condition, error_message
      # Does: Rejects explicit caller-owned mode when no caller password exists.
      # Why: A known source choice must still lead to a usable resource-body value.
      # Change: Supplying password or choosing module generation satisfies the contract.
      # Trap: This is an apply-time value guard, never a resource-count predicate.
      # Evidence: https://developer.hashicorp.com/terraform/language/expressions/custom-conditions
      condition     = local.generate_password || var.password != null
      error_message = "htpasswd-idp: password must be supplied when generate_password=false."
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
