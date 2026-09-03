# Built-in OAuth with OpenID Connect

Use `oidc_identity_providers` to attach one or more OpenID Connect providers to
a ROSA HCP cluster that uses OpenShift's built-in OAuth server. Do not use this
input when `external_auth_providers_enabled = true`; that cluster shape has no
built-in OAuth identity-provider surface.

The map shape follows the RHCS identity-provider API. Its keys are Terraform
instance identities, not provider display names. This lets Terraform know
resource cardinality before the cluster id exists.

## Entra ID example

Create the confidential-client secret in AWS Secrets Manager before planning.
Store only its locator in tfvars. The AWS provider reads the complete
SecretString as the client secret.

```hcl
# Purpose: attach an Entra OpenID registration to built-in OpenShift OAuth.
# What this is not: the locator avoids a secret literal in source; it does not
# keep the resolved secret out of Terraform state.
# Prerequisites: external auth disabled, an HTTPS Entra issuer, a registered
# confidential web client, and an encrypted owner-restricted state backend.
# Authoritative references:
# - https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# Covers: external_auth_providers_enabled, oidc_identity_providers, entra, name, client_id, client_secret_secret_id, issuer, mapping_method, extra_scopes, claims, email, preferred_username, groups
# Does: Configures one Entra registration and the claim fallbacks OpenShift reads.
# Why: Explicit values make identity mapping and secret custody reviewable before apply.
# Change: `claim` refuses automatic attachment; use `add` only for an intentional identity merge.
# Trap: the `groups` claim needs app configuration and disappears above the overage limit.
# Evidence: https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims
# Omission: an empty map creates no identity provider; omitted optional claim
# lists do not populate those OpenShift user fields.
external_auth_providers_enabled = false

oidc_identity_providers = {
  entra = {
    name                    = "entra-id"
    client_id               = "<application-client-id>"
    client_secret_secret_id = "<secrets-manager-secret-id>"
    issuer                  = "https://login.microsoftonline.com/<tenant-id>/v2.0"
    mapping_method          = "claim"
    extra_scopes            = ["email", "profile"]
    claims = {
      email              = ["email"]
      name               = ["name"]
      preferred_username = ["preferred_username", "upn"]
      groups             = ["groups"]
    }
  }
}
```

The provider organization's reference ROSA HCP module independently uses the
same caller-owned shape: its root accepts an `identity_providers` map, iterates
the map with `for_each`, passes each entry's `idp_type` to a child module, and
keeps the generated cluster id inside the child resource body. This pattern
uses stronger local types but preserves that cardinality design.

## The callback URL contains the provider name

OpenShift derives one callback URL per identity provider from the `name` you
configure:

```text
https://oauth-openshift.apps.<cluster-domain>/oauth2callback/<name>
```

Register that exact URL as a redirect URI at the provider before the first
login attempt. Two consequences are easy to miss:

- **The Terraform map key is not the callback name.** The key is a Terraform
  instance identity; `name` is what appears in the URL and in `rosa list idps`.
- **Changing `name` changes the callback URL.** The registration must change
  with it. RHCS 1.7.7 plans this as an in-place update but refuses that update
  at apply, so change the registration and deliberately replace the exact
  identity-provider instance.

## Keycloak example

Keycloak is a generic OpenID Connect provider, so it uses the same input. The
implementation is provider-neutral: the same map serves Okta, Ping, or any other
OpenID Connect provider. This example adds Keycloak beside the Entra entry to
show that the map creates one identity provider per key.

Create the client in Keycloak first: a client with **Client authentication**
enabled (a confidential client) and the **Standard flow** enabled, whose valid
redirect URI is the callback URL above. Store the client secret in AWS Secrets
Manager and put only its locator in tfvars.

```hcl
# Purpose: attach a Keycloak realm to built-in OpenShift OAuth beside Entra.
# What this is not: this does not create the realm, the client, or the group
# mapper; those are configured in Keycloak before the first login.
# Prerequisites: external auth disabled, a confidential Keycloak client whose
# redirect URI is the cluster callback URL, and an HTTPS issuer the OAuth
# server can reach and trust.
# Authoritative references:
# - https://www.keycloak.org/docs/latest/server_admin/index.html
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# Covers: oidc_identity_providers, entra, keycloak, name, client_id, client_secret_secret_id, issuer, mapping_method, ca, extra_scopes, claims, email, preferred_username, groups
# Does: Creates two identity providers from one map without a second module call.
# Why: One realm per map key keeps every provider's identity stable across plans.
# Change: Removing a key deletes only that provider and leaves the other intact.
# Trap: The issuer must equal the realm's own iss claim exactly, with no trailing slash.
# Evidence: https://www.keycloak.org/docs/latest/server_admin/index.html
# Omission: omitting ca requires the issuer certificate to chain to a public
# authority the cluster already trusts.
oidc_identity_providers = {
  entra = {
    name                    = "entra-id"
    client_id               = "<application-client-id>"
    client_secret_secret_id = "<entra-secrets-manager-secret-id>"
    issuer                  = "https://login.microsoftonline.com/<tenant-id>/v2.0"
    mapping_method          = "claim"
    extra_scopes            = ["email", "profile"]
    claims = {
      email              = ["email"]
      name               = ["name"]
      preferred_username = ["preferred_username", "upn"]
      groups             = ["groups"]
    }
  }

  keycloak = {
    name                    = "keycloak"
    client_id               = "<keycloak-client-id>"
    client_secret_secret_id = "<keycloak-secrets-manager-secret-id>"
    issuer                  = "https://<keycloak-host>/realms/<realm-name>"
    mapping_method          = "claim"
    extra_scopes            = ["email", "profile", "groups"]
    ca                      = <<-PEM
      -----BEGIN CERTIFICATE-----
      <issuer-ca-certificate>
      -----END CERTIFICATE-----
    PEM
    claims = {
      email              = ["email"]
      name               = ["name"]
      preferred_username = ["preferred_username"]
      groups             = ["groups"]
    }
  }
}
```

Four Keycloak-specific points:

- **Issuer path.** Current Keycloak serves a realm at
  `https://<host>/realms/<realm>`. Distributions before Keycloak 17 served it at
  `https://<host>/auth/realms/<realm>`. Use whichever your deployment publishes,
  with no trailing slash, and confirm it below rather than assuming.
- **`ca` is the issuer's certificate authority, not a secret.** Supply it when
  the issuer's TLS certificate chains to a private authority; omit it entirely
  when the chain is publicly trusted. It is a PEM string, so a variable
  definitions file carries it as a literal heredoc.
- **`extra_scopes` must request whatever scope carries your claims.** In this
  example a dedicated `groups` client scope is requested. If the group mapper
  lives on a default client scope instead, that scope is sent automatically and
  does not belong here.
- **`preferred_username` needs no fallback.** Keycloak emits it natively, unlike
  Entra, where `upn` is the useful second choice.

Confirm the issuer before applying, because a mismatch between the configured
issuer and the realm's own `iss` claim fails at login rather than at apply:

```bash
# Purpose: read the realm's published issuer and endpoints from the realm itself.
# What this is not: reachability from your workstation is not reachability from
# the OpenShift OAuth server, which performs the real discovery and token calls.
# Prerequisites: the Keycloak host resolvable from where this runs, plus jq.
# Authoritative references:
# - https://www.keycloak.org/docs/latest/server_admin/index.html
# Covers: realms, .well-known/openid-configuration, issuer, jwks_uri
# Does: Prints the exact issuer string the realm asserts in its tokens.
# Why: The configured issuer must equal this value character for character.
# Change: Replace both placeholders with the deployment host and realm name.
# Trap: A trailing slash or a legacy /auth prefix produces a login-time failure only.
# Evidence: https://www.keycloak.org/docs/latest/server_admin/index.html
# Omission: skipping this read moves the first detection of a mismatch to a
# failed browser login with no Terraform error.
curl -sS "https://<keycloak-host>/realms/<realm-name>/.well-known/openid-configuration" \
  | jq -r '.issuer, .authorization_endpoint, .token_endpoint, .jwks_uri'
```

## Secret custody

`client_secret_secret_id` is a locator, not a secret value. The caller needs
`secretsmanager:GetSecretValue` for that exact secret. The resolved
SecretString enters the RHCS resource and Terraform state. Encrypt the state
backend, restrict state and backup readers, and rotate the client secret after
any suspected state disclosure. This pattern does not provide write-only
provider arguments.

## Entra group claims

Entra emits no `groups` claim when the app manifest's
`groupMembershipClaims` is `None` or null. Configure the app registration to
emit the group set OpenShift should map. For JWT/OIDC tokens, Entra includes at
most 200 memberships; above that limit it omits `groups` and emits an overage
reference through `_claim_names` and `_claim_sources`. The OpenShift mapping
expects a list claim and does not follow Microsoft Graph overage references, so
username and email mapping can succeed while group mapping produces no groups.

Prefer groups assigned to the application when that models the authorization
boundary and keeps tokens below the limit. Verify the decoded ID token contains
a `groups` array before diagnosing OpenShift RBAC.

Primary sources:

- [Configure Entra group claims](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims)
- [Microsoft identity-platform group-overage claim](https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference#groups-overage-claim)
- [Entra service limits: JWT/OIDC group memberships](https://learn.microsoft.com/en-us/entra/identity/users/directory-service-limits-restrictions)

## Keycloak group claims

Keycloak has the same silent failure as Entra, arriving by a different route: it
emits no `groups` claim until a mapper puts one there. Username and email
mapping succeed, group mapping produces nothing, and OpenShift RBAC looks
misconfigured when the token simply has no groups in it.

Add a **Group Membership** mapper to the client scope the client requests, with
the token claim name `groups`, and include it in the ID token and the userinfo
response.

**Turn "Full group path" off.** With it on, Keycloak emits `/engineering`
rather than `engineering`, and nested groups arrive as `/parent/child`.
OpenShift's OAuth group mapper uses each value as the exact name of a
`user.openshift.io/v1 Group`; a leading slash is not a valid Kubernetes resource
name. On ROSA HCP 4.20.33, the issuer returned an authorization code but the
OpenShift OAuth callback refused the login. With full path off, the same
optional `groups` scope produced a bare group name and the group-bound RBAC
worked. `[tested]`

OpenShift source for the tested 4.20 line shows the two steps directly:

- [OpenID claims populate provider groups](https://github.com/openshift/oauth-server/blob/715ae668b8765b029cb7851a509b9948b8cc57a0/pkg/oauth/external/openid/openid.go)
- [The group mapper creates Groups from those exact values](https://github.com/openshift/oauth-server/blob/715ae668b8765b029cb7851a509b9948b8cc57a0/pkg/groupmapper/groupmapper.go)

Two further points worth knowing before diagnosing RBAC:

- **Scope placement decides whether the claim is sent at all.** A mapper on a
  *default* client scope is always included; a mapper on an *optional* client
  scope is included only when the client requests that scope, which is what
  `extra_scopes` is for.
- **Groups are not roles.** Keycloak realm and client *roles* arrive in
  different claims than group membership. Map whichever the authorization model
  actually uses, and confirm the decoded token before changing OpenShift RBAC.

Decode an issued ID token and confirm a `groups` array is present, with the
exact strings the bindings expect, before assuming the problem is in OpenShift.

Primary source:

- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)

## Plan and verify

Run the normal infrastructure plan. A greenfield plan may show the cluster id
as unknown while still creating one identity-provider instance per configured
map key. An existing-cluster add or change must not replace the cluster.

After apply, read the owning API rather than treating Terraform completion as
realization proof:

```bash
# Purpose: verify the exact provider at the ROSA management authority.
# What this is not: this read does not prove a browser login or group mapping.
# Prerequisites: an authenticated ROSA CLI subject allowed to read the cluster.
# Authoritative references:
# - https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/authentication_and_authorization/sts-using-idp
# Covers: --cluster, --name
# Does: Selects one cluster and one identity provider for the owning-API read.
# Why: Exact identities prevent a successful read of a neighbouring provider.
# Change: Replace both placeholders to bind the read to the intended provider.
# Trap: A successful readback still needs a real login and group-membership check.
# Evidence: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/authentication_and_authorization/sts-using-idp
# Omission: without the provider name the read is not bound to this resource.
rosa describe idp --cluster <cluster-name> --name entra-id -o json
rosa describe idp --cluster <cluster-name> --name keycloak -o json
```

## Change or remove a provider

RHCS 1.7.7 supports create and delete for OpenID identity providers, but its
`Update` implementation rejects every non-HTPasswd provider. Its `Read` keeps
the prior client secret when OCM omits it, yet Terraform 1.5.0 member-level
ignore still plans an update. The module ignores the complete `openid`
attribute to avoid a permanently dirty plan. This workaround hides changes to `ca`,
`client_id`, `client_secret`, `issuer`, `extra_scopes`,
`extra_authorize_parameters`, and `claims` from an ordinary plan.

Inspect the ordinary plan first. When an existing provider must change, replace
that exact instance deliberately:

```bash
# Purpose: replace one OpenID identity provider whose configuration changed.
# What this is not: this is not an in-place update; authentication through this
# provider can be unavailable between delete and successful recreation.
# Prerequisites: a reviewed ordinary plan, RHCS 1.7.7 credentials, a current
# Secrets Manager value, and a separate administrator path for recovery.
# Authoritative references:
# - https://developer.hashicorp.com/terraform/cli/commands/plan#replace-address
# - https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/provider/identityprovider/identity_provider_resource.go
# Change: replace `entra` with the map key of the one provider being changed.
# Omission: without `-replace`, the broad lifecycle workaround hides every
# OpenID member change from the plan.
# Trap: replacement deletes before recreation because the service name already
# exists; retain a separate administrator path and verify the recreated IDP.
terraform -chdir=terraform plan \
  -replace='module.oidc_identity_provider["entra"].rhcs_identity_provider.this'
terraform -chdir=terraform apply \
  -replace='module.oidc_identity_provider["entra"].rhcs_identity_provider.this'
```

To remove a provider, delete its map entry and apply. Confirm absence with
`rosa list idps --cluster <cluster-name> -o json`. Removal prevents new logins
through that provider but does not by itself prove immediate invalidation of
already-issued OAuth tokens. On ROSA HCP 4.20.33, a pre-delete token remained
accepted through 463.657 seconds after OCM reported the provider absent. That is
a lower bound on session survival, not an expiry promise. `[tested]`

Plan validation establishes graph shape and input guards. A live Keycloak run
on ROSA HCP 4.20.33 with RHCS 1.7.7 established OCM acceptance for two map
entries, OAuth-server reachability through private-CA Routes, browser login,
claim mapping, the absent/default/optional group cases, group-bound RBAC,
replacement recovery, callback coupling and deletion. It also established that
ordinary non-HTPasswd update reaches the provider and is refused. Entra-specific
acceptance and claims remain `[to confirm]`; the Entra example is `[docs]` and
`[plan-tested]`, not live evidence.

One of those is worth stating separately because it is the most common cause of
a working configuration that still fails to log in: **the OpenShift OAuth server
performs the discovery, token and userinfo requests, not your workstation.** The
issuer must be reachable from the cluster and its certificate chain trusted
there. A `curl` that succeeds from a laptop proves nothing about that path, and
on a private or restricted-egress cluster the two are frequently different.

References:

- [Provider-organization ROSA HCP identity-provider map](https://github.com/terraform-redhat/terraform-rhcs-rosa-hcp/blob/e052f532c39fc28dd368f3b31bc92ec02954e9b9/main.tf)
- [Provider-organization identity-provider child module](https://github.com/terraform-redhat/terraform-rhcs-rosa-hcp/blob/e052f532c39fc28dd368f3b31bc92ec02954e9b9/modules/idp/main.tf)
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)
