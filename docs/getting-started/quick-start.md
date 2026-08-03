# Quick Start

Deploy the example **public** cluster (`clusters/public/`).

## Prerequisites

Complete [Account Prerequisites](../prerequisites/account.md) first, then install:

- Terraform >= 1.5.0
- AWS CLI (configured)
- `oc`, `helm`, `jq` (for bootstrap and login)

## 1. Authenticate

Set RHCS credentials before any `make` or Terraform command:

```bash
export RHCS_TOKEN="your-offline-token"
# Or for CI/CD:
# export RHCS_CLIENT_ID="..."
# export RHCS_CLIENT_SECRET="..."
```

Example clusters set `enable_cluster_admin = true` so a break-glass HTPasswd admin is created for `make login`. Override the generated password only if needed:

```bash
# optional
export TF_VAR_admin_password_override="your-secure-password"
```

See [Authentication](authentication.md) for break-glass vs bootstrap login.

## 2. Validate prerequisites (recommended)

```bash
make cluster.public.validate
```

## 3. Initialize, plan, apply

```bash
make cluster.public.init
make cluster.public.plan
make cluster.public.apply
```

Or use scripts directly (CI/CD friendly):

```bash
./scripts/cluster/init-infrastructure.sh public
./scripts/cluster/plan-infrastructure.sh public
./scripts/cluster/apply-infrastructure.sh public
```

## 4. Bootstrap GitOps

After the cluster reaches **Ready**. Bootstrap creates its own short-lived HTPasswd user, then tears it down — it does not use the break-glass admin:

```bash
make cluster.public.bootstrap
```

## 5. Access the cluster (break-glass)

Requires `enable_cluster_admin = true` (already set in example tfvars):

```bash
make cluster.public.show-endpoints
make cluster.public.login
make cluster.public.show-credentials
```

## Other cluster profiles

Copy an example `terraform.tfvars` and customize:

```bash
cp clusters/egress-zero/terraform.tfvars clusters/my-prod/
# Edit clusters/my-prod/terraform.tfvars
make cluster.my-prod.init
make cluster.my-prod.apply
```

| Profile | Example | Notes |
|---------|---------|-------|
| Public dev | `clusters/public/` | Public API, NAT egress |
| Egress-zero | `clusters/egress-zero/` | Zero egress, Client VPN |
| BYO VPC | `clusters/byo-vpc/` | Pre-provisioned network |
| BYO + zero egress | `clusters/byo-vpc-egress-zero/` | BYO VPC with zero egress |

See [Cluster Configurations](../deployment/cluster-configurations.md) and [Full-Stack Prerequisites](../prerequisites/full-stack.md).

## Next steps

- [Enablement Guide](../deployment/enablement.md) — full adoption path
- [Prerequisites](../prerequisites/index.md) — account, BYO, zero egress
