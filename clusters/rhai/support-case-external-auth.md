# ROSA HCP External Auth + Entra ID: Console Unauthorized Loop

## Summary

OpenShift console on ROSA HCP 4.22.8 with external authentication (Entra ID) enters an infinite login loop. OAuth succeeds but all API calls return Unauthorized. The console bridge proxies the Microsoft Graph access token (aud: `00000003-0000-0000-c000-000000000000`) to the Kubernetes API server instead of the OIDC ID token. The API server rejects the Graph token. The console classifies the user as "unknown" and auto-logs out, creating an infinite redirect loop.

The ID token is valid and works with `oc login --token=<id-token>` — confirmed via both CLI login and Kubernetes TokenReview API.

## Environment

- **ROSA HCP**: 4.22.8
- **Region**: ap-southeast-2
- **Cluster name**: rhai
- **External auth**: enabled at cluster creation (`external_auth_providers_enabled = true`)
- **Identity provider**: Microsoft Entra ID (Azure AD) v2.0
- **Tenant ID**: `64dc69e4-d083-49fc-9569-ebece1dd1408`
- **Application (client) ID**: `e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e`
- **App registration name**: rhai-auth

## External Auth Provider Configuration

```bash
rosa create external-auth-provider \
  --cluster=rhai \
  --name=entraid \
  --issuer-url=https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0 \
  --issuer-audiences=e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e \
  --claim-mapping-username-claim=preferred_username \ (also tried email but our users dont have an email property)
  --claim-mapping-groups-claim=groups \
  --console-client-id=e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e \
  --console-client-secret="<redacted>"
```

```
$ rosa describe external-auth-provider entraid -c rhai

ID:                                    entraid
Cluster ID:                            2saovm13jstt2gu2mq5nu86khtnh0n2f
Issuer audiences:                      e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
Issuer Url:                            https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0
Claim mappings group:                  groups
Claim mappings username:               preferred_username
Console client id:                     e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
```

## Azure App Registration Configuration

```
$ az ad app show --id e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e

displayName: rhai-auth
appId: e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
identifierUris: ['api://e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e']
signInAudience: AzureADMyOrg
requestedAccessTokenVersion: 2

Redirect URIs:
  - https://console-openshift-console.apps.rosa.rhai.jzwm.p3.openshiftapps.com/auth/callback

Exposed API scopes:
  - user_impersonation (admin consent, enabled)

Optional claims:
  ID token: email, preferred_username, groups
  Access token: groups

API permissions:
  - Microsoft Graph: openid, email (delegated)
  - Own API: user_impersonation (delegated, admin consented)

Enterprise Application:
  - Group 6c26fe18-f4de-4e1b-bee8-097a4328dfb2 assigned
```

## RBAC Configuration

```bash
$ oc get clusterrolebinding entraid-cluster-admins -o yaml

subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: 6c26fe18-f4de-4e1b-bee8-097a4328dfb2
roleRef:
  kind: ClusterRole
  name: cluster-admin

$ oc get clusterrolebinding entraid-admin-user -o yaml

subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: pafoster@redhat.com
roleRef:
  kind: ClusterRole
  name: cluster-admin
```

## Evidence 1: ID Token Works — CLI Login

```
$ oc login --token=<id-token> --server=https://api.rhai.jzwm.p3.openshiftapps.com:443

Logged into "https://api.rhai.jzwm.p3.openshiftapps.com:443" as
"https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0#pafoster@redhat.com"
using the token provided.

You have access to 82 projects, the list has been suppressed. You can list all projects with 'oc projects'
Using project "default".
```

## Evidence 2: TokenReview — ID Token Accepted

```bash
$ cat <<EOF | oc create -f - -o json
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "<id-token>"
EOF
```

Result:
```json
{
  "authenticated": true,
  "user": {
    "groups": [
      "6c26fe18-f4de-4e1b-bee8-097a4328dfb2",
      "system:authenticated"
    ],
    "uid": "zGgI_r8-RWmRZk6c0KhqWoRdvLlreVhe6LJriSTLHSM",
    "username": "https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0#pafoster@redhat.com"
  }
}
```

## Evidence 3: TokenReview — Access Token Rejected

```bash
$ cat <<EOF | oc create -f - -o json
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "<access-token>"
EOF
```

Result:
```json
{
  "error": "invalid bearer token",
  "user": {}
}
```

## Evidence 4: Token Analysis

### Access Token (sent by console to API server)
```
aud: 00000003-0000-0000-c000-000000000000   <-- Microsoft Graph, NOT the app
iss: https://sts.windows.net/64dc69e4-.../   <-- v1.0 issuer
ver: 1.0
scp: openid profile email
app_displayname: rhai-auth
appid: e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
NO groups claim
```

### ID Token (correct, but not used by console)
```
aud: e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e   <-- correct app client ID
iss: https://login.microsoftonline.com/64dc69e4-.../v2.0   <-- correct v2.0 issuer
ver: 2.0
groups: ["6c26fe18-f4de-4e1b-bee8-097a4328dfb2"]
preferred_username: pafoster@redhat.com
```

## Evidence 5: Console Logs (verbosity increased)

```
I0821 11:33:16.513138  auth.go:368] oauth success, redirecting to: "https://console-openshift-console.apps.rosa.rhai.jzwm.p3.openshiftapps.com/"
E0821 11:33:16.526109  metrics.go:175] Error in auth.metrics isKubeAdmin: Unauthorized
E0821 11:33:16.562157  metrics.go:161] Error in auth.metrics canGetNamespaces: Unauthorized
I0821 11:33:16.562179  metrics.go:103] auth.Metrics loginSuccessfulSync - increase metric for role "unknown"
I0821 11:33:16.952613  proxy.go:104] PROXY: `https://kubernetes.default.svc/apis/authorization.k8s.io/v1/selfsubjectaccessreviews`
I0821 11:33:16.953108  proxy.go:104] PROXY: `https://kubernetes.default.svc/apis/authentication.k8s.io/v1/selfsubjectreviews`
I0821 11:33:16.953228  proxy.go:104] PROXY: `https://kubernetes.default.svc/apis/authorization.k8s.io/v1/selfsubjectaccessreviews`
[... multiple proxy calls, all return Unauthorized ...]
I0821 11:33:17.016504  metrics.go:119] auth.Metrics LogoutRequested with reason "unknown"
I0821 11:33:17.032751  middleware.go:27] authentication failed: a session was not found on server or is expired
[... session destroyed, infinite redirect loop ...]
```

### Console log flow:
1. `oauth success` — OIDC authentication with Entra ID succeeds
2. Console proxies API calls to `kubernetes.default.svc` with bearer token
3. All API calls return `Unauthorized` — bearer token is the Graph access token
4. Console classifies user role as `"unknown"`
5. `LogoutRequested with reason "unknown"` — console auto-logs out
6. Session destroyed → `session was not found` → redirect to login → infinite loop

## Evidence 6: Console OIDC Configuration

```
$ oc get configmap console-config -n openshift-console -o yaml

auth:
  authType: oidc
  clientID: e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
  clientSecretFile: /var/oauth-config/clientSecret
  oidcExtraScopes:
    - e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e/.default
  oidcIssuer: https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0
```

Note: `oidcExtraScopes` was set via OCM API (`ocm patch`) to try to force Azure to issue an app-scoped access token. This did not change the access token audience — Azure still issues a Graph access token when `openid profile email` scopes are present.

## Evidence 7: Cluster Authentication Config

```
$ oc get authentication.config.openshift.io cluster -o json

spec.oidcProviders[0]:
  name: entraid
  issuer:
    issuerURL: https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0
    audiences: ["e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e"]
  claimMappings:
    username: { claim: preferred_username }
    groups: { claim: groups }
  oidcClients[0]:
    clientID: e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e
    componentName: console
    componentNamespace: openshift-console
    extraScopes: ["e6a75a64-95ce-4dfd-9fbf-a5835bfe4a5e/.default"]
```

## Evidence 8: Patching Blocked by ROSA HCP

```
$ oc patch authentication.config.openshift.io cluster --type=json \
  -p '[{"op":"replace","path":"/spec/oidcProviders/0/oidcClients/0/extraScopes","value":["..."]}]'

The authentications "cluster" is invalid: : ValidatingAdmissionPolicy 'config'
with binding 'config-binding' denied request: This resource cannot be created,
updated, or deleted. Please ask your administrator to modify the resource in
the HostedCluster object.
```

## Root Cause

The OpenShift console bridge (`authType: oidc`) uses the OAuth2 **access token** as the bearer token when proxying API calls to `kubernetes.default.svc`. With Microsoft Entra ID, the access token is always issued for Microsoft Graph (`aud: 00000003-...`) when `openid profile email` scopes are requested — regardless of `extraScopes`, `accessTokenAcceptedVersion`, or Expose an API configuration. This is a fundamental Azure OAuth2 behavior: you cannot mix scopes for different resources in a single authorization request.

The Kubernetes API server with external OIDC validates the **ID token** (which has the correct audience, issuer, groups, and username claims). The ID token works perfectly — proven via `oc login --token` and TokenReview.

## What Is Needed

Either:
1. **Console bridge should use the `id_token`** (not the `access_token`) as the bearer token for API server calls when `authType: oidc` — the Kubernetes API server is configured to validate ID tokens via the OIDC provider
2. **Or `rosa create external-auth-provider` should support `--console-extra-scopes`** to allow requesting app-specific scopes that force Azure to issue an access token with the correct audience

## Workarounds Available

- CLI access with `oc login --token=<id-token>` works
- Break-glass credentials work (`rosa create break-glass-credential`)
- `oidc-login` kubectl plugin works for persistent CLI access
- Console access is blocked (infinite login loop)
