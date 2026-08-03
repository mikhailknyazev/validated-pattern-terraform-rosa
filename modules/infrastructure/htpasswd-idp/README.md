# HTPasswd Identity Provider Module

Creates an HTPasswd identity provider, a single user, and optional `cluster-admins` (or configurable) group membership.

## Purpose

Shared building block for:

| Caller | Typical `idp_name` / `username` | Lifecycle |
|--------|----------------------------------|-----------|
| `modules/infrastructure/bootstrap-admin` | `bootstrap` / `bootstrap` | Short-lived during GitOps bootstrap (#29) |
| `modules/infrastructure/cluster` (break-glass) | `admin` / `admin` | Long-lived when `enable_cluster_admin` is true |

Both can be enabled at once: they are **separate module instances** with different IDP names and usernames. Secrets Manager (if any) stays in the caller — this module never writes passwords to AWS.

## Usage

```hcl
module "example" {
  source = "../htpasswd-idp"

  enabled    = true
  cluster_id = var.cluster_id
  idp_name   = "bootstrap"
  username   = "bootstrap"
  password   = var.password # null → module generates random_password
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| enabled | Create resources when true | `false` |
| cluster_id | ROSA cluster ID | `null` |
| password | Optional HTPasswd password (`null` → random) | `null` |
| idp_name | HTPasswd IDP name | *(required)* |
| username | HTPasswd username | *(required)* |
| admin_group | Group for membership | `cluster-admins` |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| username | HTPasswd username | no |
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
