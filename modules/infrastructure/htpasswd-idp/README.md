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

  enabled           = true
  cluster_id        = var.cluster_id
  idp_name          = "bootstrap"
  username          = "bootstrap"
  password          = random_password.caller.result
  # The caller-owned generator is unknown during planning. Fixing the source
  # choice independently keeps this module's resource count plan-known.
  generate_password = false
}
```

Omit both `password` and `generate_password` to preserve the module's original
behavior: the module generates its own password. A caller that supplies a
literal password may omit `generate_password`. A caller that supplies an
apply-time generated value must set `generate_password = false`; otherwise the
module cannot infer resource cardinality from that unknown value during plan.

Optional-password validation uses a lazy conditional. The former boolean `||`
form evaluates `length(null)` and fails when the password is omitted on
Terraform 1.5.0, 1.9.8, 1.10.5 and 1.11.0; it first passes unchanged on 1.12.2.
The conditional preserves the module's documented Terraform `>= 1.5` floor and
still rejects a supplied value shorter than 14 characters.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| enabled | Create resources when true | `false` |
| cluster_id | ROSA cluster ID | `null` |
| password | Optional caller-supplied HTPasswd password; null generates one when `generate_password` is also null | `null` |
| generate_password | Optional plan-known password-source choice; true creates this module's password, false requires the caller's password, and null preserves literal/null inference | `null` |
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
