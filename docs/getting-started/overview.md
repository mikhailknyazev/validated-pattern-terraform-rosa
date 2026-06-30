# Overview

This repository deploys **ROSA HCP** clusters on AWS using composable Terraform modules and a **directory-per-cluster** layout.

## Repository layout

```
vp-terraform-rosa/
├── terraform/                    # Root module (providers, variables, module wiring)
├── modules/infrastructure/       # Reusable modules
│   ├── network-public/           # Public VPC + NAT
│   ├── network-private/          # Private VPC, VPC endpoints, zero-egress support
│   ├── iam/                      # Account roles, OIDC, operator roles, KMS
│   ├── cluster/                  # ROSA HCP cluster, machine pools, GitOps bootstrap
│   ├── client-vpn/               # AWS Client VPN for private cluster access
│   └── bastion/                  # Optional bastion (deprecated; prefer Client VPN)
├── clusters/<name>/              # Per-cluster terraform.tfvars and state
└── scripts/                      # Init, plan, apply, bootstrap, validation
```

## Deployment phases

| Phase | What happens | Driven by |
|-------|--------------|-----------|
| **Day 0** | VPC, IAM, KMS, cluster, EFS, logging IAM, bootstrap values | Terraform (`make cluster.<name>.apply`) |
| **Day 1** | OpenShift GitOps operator, Argo CD repo wiring | `make cluster.<name>.bootstrap` |
| **Day 2+** | cert-manager, ingress, applications | Argo CD sync from cluster-config |

## Network sources

Cluster shape is defined in `clusters/<name>/terraform.tfvars`. The **`network_type`** variable selects where the VPC comes from:

| `network_type` | Who creates the VPC |
|----------------|---------------------|
| `public` | Terraform (`network-public` module) |
| `private` | Terraform (`network-private` module) |
| `existing` | Your network team (BYO VPC) |

**`zero_egress`** and **`private`** are independent flags — they can combine with any network source. See [Prerequisites — Choose Your Path](../prerequisites/index.md).

## Multi-team composition

Large organizations may split ownership:

- **Network team** — VPC, subnets, endpoints
- **Security/IAM team** — roles, OIDC, KMS keys
- **Platform team** — cluster and GitOps bootstrap

The unified root module (`terraform/`) runs all layers in one apply by default. Multi-team separation uses module outputs passed via `TF_VAR_*` or remote state — see [BYO IAM and KMS](../prerequisites/byo/iam-kms.md).

## Module documentation

Each infrastructure module has a README with inputs, outputs, and examples:

- [Cluster module](../modules/cluster.md)
- [IAM module](../modules/iam.md)
- [Network (Private)](../modules/network-private.md)
- [Network (Public)](../modules/network-public.md)

## Next steps

- [Quick Start](quick-start.md) — deploy a public cluster
- [Authentication](authentication.md) — RHCS credentials
- [Account Prerequisites](../prerequisites/account.md) — before any deployment
