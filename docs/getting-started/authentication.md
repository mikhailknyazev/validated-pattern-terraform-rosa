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

## Post-creation: notification contacts

After the cluster is **Ready**, add notification contacts in [OpenShift Cluster Manager](https://console.redhat.com/openshift) — service accounts do not receive email alerts by default. See the [Enablement Guide](../deployment/enablement.md) for details.
