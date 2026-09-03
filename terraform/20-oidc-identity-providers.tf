# Purpose: create generic OpenID providers from variable-owned map keys while
# resolving each confidential-client secret from AWS Secrets Manager.
# What this is not: the locator prevents a secret literal in tfvars but does
# not prevent the resolved SecretString from being stored in Terraform state.
# Prerequisites: external authentication disabled, one secret in this AWS
# provider's Region per map entry, and state encrypted with restricted access.
# Authoritative references:
# - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# Covers: for_each, secret_id, source, cluster_id, name, mapping_method, openid, ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, claims
# Does: Resolves each secret and creates one module instance per configured map key.
# Why: Caller-owned keys keep instance identity known before cluster creation completes.
# Change: A changed key destroys one identity provider and creates a different instance.
# Trap: Secret lookup protects tfvars only; the resolved value remains in Terraform state.
# Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each

data "aws_secretsmanager_secret_version" "oidc_identity_provider" {
  # Map keys come only from input configuration and are known at plan time.
  for_each = var.oidc_identity_providers

  secret_id = each.value.client_secret_secret_id
}

module "oidc_identity_provider" {
  source   = "../modules/infrastructure/oidc-idp"
  for_each = var.oidc_identity_providers

  # The cluster output is intentionally inside the module body. Terraform can
  # order creation even when this value is unknown during a greenfield plan.
  cluster_id     = module.cluster.cluster_id
  name           = each.value.name
  mapping_method = each.value.mapping_method
  openid = {
    ca                         = each.value.ca
    client_id                  = each.value.client_id
    client_secret              = data.aws_secretsmanager_secret_version.oidc_identity_provider[each.key].secret_string
    issuer                     = each.value.issuer
    extra_scopes               = each.value.extra_scopes
    extra_authorize_parameters = each.value.extra_authorize_parameters
    claims                     = each.value.claims
  }
}
