# Authentication

Set **RHCS (Red Hat Cloud Services)** credentials before using any `make` or Terraform command. This project does not manage credentials for you.

## Option 1: Offline token (local development)

1. Get a token from [console.redhat.com/openshift/token/rosa/show](https://console.redhat.com/openshift/token/rosa/show)
2. Export it:

```bash
export RHCS_TOKEN="your-offline-token"
```

Suitable for short local experiments. **Not recommended for production** — clusters created with a personal token are tied to that user as OCM owner.

## Option 2: Service account (recommended for production and CI/CD)

1. Sign in to [Red Hat Hybrid Cloud Console](https://console.redhat.com)
2. Go to **User Management → Service accounts**
3. Create a service account and copy **client ID** and **client secret** (secret shown once)
4. Add the service account to a User Access group with OCM roles (e.g. Cluster Provisioner)
5. Export credentials:

```bash
export RHCS_CLIENT_ID="your-client-id-uuid"
export RHCS_CLIENT_SECRET="your-client-secret"
# Do not set RHCS_TOKEN when using a service account
```

## Credentials file (recommended locally)

```bash
# .rhcs_creds (add to .gitignore)
export RHCS_CLIENT_ID="..."
export RHCS_CLIENT_SECRET="..."

source .rhcs_creds
make cluster.public.plan
```

## AWS credentials

Configure AWS CLI separately:

```bash
aws configure
# or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
aws sts get-caller-identity
```

## ROSA CLI (optional)

For account linking verification and admin user creation:

```bash
rosa login --token="$RHCS_TOKEN"
rosa whoami
```

See [Account Prerequisites](../prerequisites/account.md) for OCM role and Marketplace linking.

## Cluster admin (break-glass) vs GitOps bootstrap

Two separate HTPasswd paths share `modules/infrastructure/htpasswd-idp`:

| Path | When | User / IDP | Secrets Manager | Used by |
|------|------|------------|-----------------|---------|
| **Bootstrap** | Only during `make cluster.<name>.bootstrap` | `bootstrap` | No | GitOps `oc login` (created then destroyed automatically) |
| **Break-glass** | When `enable_cluster_admin = true` | `admin` | Yes (`{cluster_name}-credentials` JSON) | `make cluster.<name>.login` / `show-credentials` |

**GitOps bootstrap** does not need break-glass credentials. `bootstrap-admin.sh` generates a password, creates a short-lived HTPasswd user, polls until `oc login` works, runs GitOps, then tears the user down (password is not stored in Secrets Manager).

**Break-glass admin** (human / day-0 login until OIDC or similar):

```hcl
# terraform.tfvars
enable_cluster_admin = true
# optional: admin_password_override / TF_VAR_admin_password_override
```

```bash
# Optional password override (otherwise Terraform generates one)
export TF_VAR_admin_password_override="your-secure-password-at-least-14-chars"
```

- Variable **default** is `false` (no long-lived HTPasswd admin).
- Example cluster `terraform.tfvars` in this repo set `enable_cluster_admin = true` so `make cluster.<name>.login` works after apply.
- Credentials live in a single Secrets Manager secret `{cluster_name}-credentials` (JSON: `user`, `password`, `url`) — not a separate plain-password secret.
- Without break-glass, `make login` exits with instructions — it does not use the bootstrap user (that user is already destroyed).

Retrieve the break-glass password after apply:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(cd terraform && terraform output -raw cluster_credentials_secret_arn)" \
  --query SecretString --output text | jq -r .password
```

Or use `make cluster.<name>.show-credentials` / `scripts/utils/get-admin-password.sh`.

### Turn the long-lived administrator on or off at any point

`enable_cluster_admin` can be set before the cluster exists or changed on an
existing cluster, in either direction, while Terraform still generates the
password. All three transitions plan without `-target`:

| Transition | Planned result |
|---|---|
| Enable on a greenfield workspace | creates the generated password, identity provider, `cluster-admins` membership and credentials secret alongside the cluster |
| Enable on an existing cluster | creates those same resources; the cluster itself is neither updated nor replaced |
| Disable on an existing cluster | deletes those same resources; the cluster itself is neither updated nor replaced |

The target-first password workaround is retired. A count predicate may not
reach anything unknown at plan time. A generated password is a resource output,
even when configuration later treats it like a local secret, so it belongs only
inside resource bodies; caller-known booleans control cardinality.

`enable_cluster_admin` controls the HTPasswd identity provider, its
`cluster-admins` membership, the generated password, and the credentials secret.
Its resource counts depend only on caller configuration, so a generated password
may remain unknown during planning without requiring a target-first apply.
The root also passes the password-source choice separately to the shared
HTPasswd module. Without that second plan-known input, the child would recreate
the same `Invalid count argument` while deciding whether to generate another
password.

The shared and bootstrap modules also use a lazy conditional when validating an
optional password. The former `var.password == null || length(var.password) >=
14` expression fails on an omitted password with Terraform 1.5.0, 1.9.8,
1.10.5 and 1.11.0, and passes on 1.12.2. Because this repository declares
Terraform `>= 1.5.0`, the conditional form avoids `length(null)` across the
supported floor while still rejecting a supplied password shorter than 14
characters.

**Disabling destroys the credential and re-enabling issues a different one.**
The generated password is a managed resource, so turning the administrator off
deletes it together with the Secrets Manager object, and turning it back on
generates a new value. Anything holding the previous password stops working at
that point. Set `admin_password_override` when one specific password has to
survive the toggle.

```bash
# Purpose: preview adding or removing the complete long-lived administrator path.
# What this is not: a successful plan or apply is not proof that OCM has realized
# the identity provider or that Secrets Manager has completed deletion.
# Prerequisites: an existing built-in-OAuth cluster, Terraform 1.5.0, RHCS 1.7.7,
# an OCM subject allowed to manage IDPs, and AWS permission for the named secret.
# Authoritative references:
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# - https://docs.aws.amazon.com/secretsmanager/latest/userguide/manage_delete-secret.html
# Covers: plan, apply
# Does: Plans and applies one explicit long-lived administrator lifecycle transition.
# Why: The same reviewed boolean must control the IDP, membership, password, and secret.
# Change: Set true to add every surface or false to remove every surface.
# Trap: External-authentication clusters have no built-in OAuth identity-provider surface.
# Evidence: https://developer.hashicorp.com/terraform/cli/commands/plan
# Omission: the default false creates no long-lived HTPasswd administrator.
terraform -chdir=terraform plan -var='enable_cluster_admin=<true-or-false>'
terraform -chdir=terraform apply -var='enable_cluster_admin=<true-or-false>'
```

Verify the three owning authorities independently after apply:

```bash
# Purpose: confirm the IDP, administrator membership, and secret lifecycle where
# each is owned instead of treating Terraform completion as realization proof.
# What this is not: these reads do not prove that an already-issued OAuth session
# was invalidated when the identity provider was removed.
# Prerequisites: replace the placeholders and authenticate both CLIs read-only.
# Authoritative references:
# - https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/authentication_and_authorization/sts-using-idp
# - https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/describe-secret.html
# Covers: --cluster, --secret-id
# Does: Reads the IDP, group membership, and credential from their owning authorities.
# Why: Independent reads prevent Terraform completion from standing in for realization.
# Change: After enable expect all three; after disable expect all three absent.
# Trap: Scheduled secret deletion is not absence; inspect the returned deletion state.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/describe-secret.html
# Omission: skipping the AWS read can mistake scheduled deletion for absence.
rosa list idps --cluster <cluster-name> -o json
oc get group cluster-admins -o json
aws secretsmanager describe-secret --secret-id <cluster-name>-credentials
```

Removal prevents new logins through this HTPasswd provider. It does not, by
itself, prove that previously issued OAuth access tokens have stopped working;
verify session revocation separately when immediate invalidation is required.
The targeted `module.bootstrap_admin` workflow remains intentional: it isolates
temporary bootstrap credentials from unrelated cluster reconciliation and is not
retired by this lifecycle fix.

## External authentication providers

When `external_auth_providers_enabled = true` in `terraform.tfvars`, the cluster uses external OIDC identity providers instead of the built-in OAuth server. This is a **create-time only** setting (immutable after cluster creation).

**What changes:**

- The RHCS API rejects all `rhcs_identity_provider` resources (HTPasswd, LDAP, etc.)
- `enable_cluster_admin` (break-glass HTPasswd admin) is automatically disabled
- Bootstrap uses ROSA break-glass credentials instead of HTPasswd admin
- `make cluster.<name>.login` is replaced by `make cluster.<name>.break-glass-login`

**Temporary admin access (break-glass credentials):**

```bash
make cluster.<name>.break-glass-login
```

This creates a ROSA break-glass credential (valid 24 hours), exports a kubeconfig, and verifies access. Requires `rosa` CLI >= 1.2.36.

```bash
# Manual workflow:
rosa create break-glass-credential --cluster=$CLUSTER_NAME --expiration=24h
rosa list break-glass-credential --cluster=$CLUSTER_NAME
rosa describe break-glass-credential $ID --cluster=$CLUSTER_NAME --kubeconfig > break-glass.kubeconfig
export KUBECONFIG=break-glass.kubeconfig
oc whoami
```

**Revoking credentials:**

```bash
rosa revoke break-glass-credentials --cluster=$CLUSTER_NAME
```

**Bootstrap:** `make cluster.<name>.bootstrap` automatically detects external auth and uses break-glass credentials for the GitOps bootstrap flow. No manual intervention needed.

## Post-creation: notification contacts

After the cluster is **Ready**, add notification contacts in [OpenShift Cluster Manager](https://console.redhat.com/openshift) — service accounts do not receive email alerts by default. See the [Enablement Guide](../deployment/enablement.md) for details.
