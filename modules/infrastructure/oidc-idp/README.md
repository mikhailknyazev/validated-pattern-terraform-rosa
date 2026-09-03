# OpenID Connect identity provider

Purpose: attach one generic OpenID Connect provider to a ROSA HCP cluster that
uses built-in OpenShift OAuth.

What this is not: tenant-registration automation, a secret-management boundary,
or evidence that authentication succeeded in a live cluster.

Prerequisites: a configured OpenID registration, a protected client-secret
input, and external authentication disabled on the target cluster.

Authoritative references:

- [RHCS 1.7.7 identity-provider resource](https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider)

This module attaches one generic OpenID Connect provider to a ROSA HCP
cluster's built-in OpenShift OAuth server. The root module owns `for_each`, so
provider names are stable Terraform instance keys while the cluster id may be
unknown during a greenfield plan.

The client secret is sensitive but state-resident. A protected input channel
prevents committing the secret; it does not remove the resolved value from
Terraform state. Protect state and its backups accordingly.

RHCS 1.7.7 retains the prior client secret when OCM omits it on read, but a
Terraform 1.5.0 member-level ignore still plans an update. The module therefore
ignores the complete `openid` attribute to prevent a permanently dirty plan. That
workaround also hides changes to `ca`, `client_id`, `client_secret`, `issuer`,
`extra_scopes`, `extra_authorize_parameters`, and `claims`. The same provider
version rejects non-HTPasswd updates, so replace the identity provider
deliberately when any of those values changes.

Use `mapping_method = "claim"` when a new identity must not attach to an
existing OpenShift user automatically. Use `add` only when that attachment is
an explicit migration decision.

References:

- [RHCS 1.7.7 identity provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider)
- [RHCS 1.7.7 read and update implementation](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/provider/identityprovider/identity_provider_resource.go)
- [OpenShift identity mapping](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-identity-provider)
