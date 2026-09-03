# Purpose: attach one generic OpenID Connect provider to OpenShift built-in
# OAuth after ROSA creates the cluster.
# What this is not: this module does not create an OIDC registration, manage
# tenant consent, or keep the resolved client secret out of Terraform state.
# Prerequisites: built-in OAuth (external auth disabled), an HTTPS issuer, and
# a confidential-client secret supplied through a protected caller surface.
# Authoritative references:
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# - https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-oidc-identity-provider
# Covers: cluster, name, mapping_method, openid, ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, claims, ignore_changes
# Does: Sends one complete OpenID provider request to the cluster owning API.
# Why: Keeping the cluster identifier in the body preserves plan-known cardinality.
# Change: Any OpenID member change requires deliberate replacement with RHCS 1.7.7.
# Trap: The broad workaround hides ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, and claims from ordinary plans.
# Evidence: https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/provider/identityprovider/identity_provider_resource.go

resource "rhcs_identity_provider" "this" {
  # The caller owns cardinality. Keeping the cluster id in the body lets its
  # greenfield value remain unknown until apply without making instance count
  # unknown at plan time.
  cluster        = var.cluster_id
  name           = var.name
  mapping_method = var.mapping_method

  openid = {
    ca                         = var.openid.ca
    client_id                  = var.openid.client_id
    client_secret              = var.openid.client_secret
    issuer                     = var.openid.issuer
    extra_scopes               = var.openid.extra_scopes
    extra_authorize_parameters = var.openid.extra_authorize_parameters
    claims                     = var.openid.claims
  }

  lifecycle {
    # RHCS 1.7.7 retains the prior secret when OCM omits it, but Terraform's
    # member-level ignore still plans an update. Ignore the complete attribute
    # to prevent a permanently dirty plan. The guide requires an explicit
    # replacement for every intentional OpenID change because this also hides
    # ca, client_id, issuer, scopes, parameters, and claims.
    ignore_changes = [openid]
  }
}
