# Bootstrap Admin Module

Creates a **short-lived** HTPasswd identity provider and `cluster-admins` user for GitOps bootstrap `oc login`.

This module is a thin wrapper around [`../htpasswd-idp`](../htpasswd-idp) with bootstrap defaults (`idp_name` / `username` = `bootstrap`). Optional long-lived break-glass admin uses a **separate** instance of `htpasswd-idp` in the cluster module — both can exist at once.

## Purpose

- Enabled while bootstrap runs (`enable_bootstrap_admin_user=true` with `-target=module.bootstrap_admin`)
- Password: optional input, or `random_password` when null (module usable outside the bootstrap script)
- `bootstrap-admin.sh` always generates a password and passes it in so GitOps never reads terraform outputs for the secret
- Torn down by applying with `enable_bootstrap_admin_user=false` and the same `-target`

See: `docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md` (#29).

## Usage

```hcl
module "bootstrap_admin" {
  source = "../modules/infrastructure/bootstrap-admin"

  # Pass cluster_id as a root variable (not module.cluster.cluster_id) so
  # -target=module.bootstrap_admin does not pull in the cluster module.
  enabled    = var.enable_bootstrap_admin_user
  cluster_id = var.bootstrap_admin_cluster_id
  password   = var.bootstrap_admin_password # null → module generates one
}
```

Bootstrap orchestration (`scripts/cluster/bootstrap-admin.sh`):

```bash
# create generates a password, applies the IDP, prints export lines on stdout
eval "$(./scripts/cluster/bootstrap-admin.sh <cluster> create)"
# … oc login / GitOps using BOOTSTRAP_* …
./scripts/cluster/bootstrap-admin.sh <cluster> destroy
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| enabled | Create resources when true | `false` |
| cluster_id | ROSA cluster ID | `null` |
| password | Optional HTPasswd password (`null` → random) | `null` |
| idp_name | HTPasswd IDP name | `bootstrap` |
| username | HTPasswd username | `bootstrap` |
| admin_group | Group for membership | `cluster-admins` |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| username | Bootstrap username | no |
| password | Effective password (supplied or generated) | **yes** |
| idp_name | IDP name | no |
| identity_provider_id | RHCS IDP id | no |
| enabled | Whether resources exist | no |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| rhcs | ~> 1.7 |
| random | >= 3.0 |
