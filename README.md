# ROSA HCP Infrastructure

Production-grade Terraform repository for deploying Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP).

**Documentation:** [https://rh-mobb.github.io/validated-pattern-terraform-rosa/](https://rh-mobb.github.io/validated-pattern-terraform-rosa/) — prerequisites, enablement guide, module reference, and validation scripts. Local preview: `make docs-preview`.

## Overview

This repository provides reusable Terraform modules and example configurations for deploying ROSA HCP clusters with different network topologies and security postures. The architecture follows a **Directory-Per-Cluster** pattern to ensure state isolation and proper lifecycle management.

### Repository Structure

The repository is organized around infrastructure modules:

- **Infrastructure**: Foundational AWS and ROSA resources (VPC, IAM roles and KMS keys, cluster with EFS, GitOps bootstrap script)


## Quick Start

See [Quick Start](docs/getting-started/quick-start.md) and [Account Prerequisites](docs/prerequisites/account.md) in the documentation site.

```bash
# 1. Authenticate (see docs/getting-started/authentication.md)
export RHCS_CLIENT_ID="..." RHCS_CLIENT_SECRET="..."

# 2. Validate prerequisites
make cluster.public.validate

# 3. Deploy
make cluster.public.init
make cluster.public.plan
make cluster.public.apply
make cluster.public.bootstrap
```

Example clusters: `public`, `egress-zero`, `byo-vpc`, `byo-vpc-egress-zero` — see [clusters/README.md](clusters/README.md).

Admin credentials (HTPasswd) are stored once in AWS Secrets Manager as `{cluster_name}-credentials` (JSON: `user`, `password`, `url`). Retrieve with `cluster_credentials_secret_arn` or `make cluster.<name>.show-credentials`. See [Authentication](docs/getting-started/authentication.md).

## Repository Structure

The repository is organized around infrastructure modules:

```
rosa-hcp-infrastructure/
├── modules/                    # Reusable Terraform modules
│   └── infrastructure/         # Infrastructure modules
│       ├── network-public/     # Public VPC with NAT Gateways
│       ├── network-private/    # Private VPC (PrivateLink API)
│       ├── network-existing/   # Use existing VPC
│       ├── iam/                # IAM roles, OIDC configuration, KMS keys, operator IAM roles
│       ├── cluster/            # ROSA HCP Cluster module (optional break-glass IDP, EFS, GitOps bootstrap)
│       ├── htpasswd-idp/       # Shared HTPasswd IDP + group membership (bootstrap + break-glass)
│       ├── bootstrap-admin/    # Short-lived bootstrap admin (wrapper around htpasswd-idp)
│       ├── bastion/            # Bastion host (deprecated; use client-vpn)
│       └── client-vpn/         # AWS Client VPN for private cluster access (recommended)
└── clusters/                   # Cluster configurations
    ├── public/                 # Example public cluster (reference)
    │   └── terraform.tfvars
    ├── egress-zero/            # Example egress-zero cluster (reference)
    │   └── terraform.tfvars
    ├── byo-vpc/                # BYO VPC example
    └── byo-vpc-egress-zero/    # BYO VPC + zero egress
```

### Infrastructure Modules

**Infrastructure** (`modules/infrastructure/`):
- **Network** (`network-public`, `network-private`, `network-existing`): VPC, subnets, NAT gateways, VPC endpoints
- **IAM** (`iam`): IAM roles, OIDC configuration, **KMS encryption** (EBS, EFS, ETCD — via external ARNs or internal key creation), **IAM roles for operators** (CloudWatch logging, Cert Manager, Secrets Manager, CSI drivers)
- **Cluster** (`cluster`): ROSA HCP cluster, machine pools, optional break-glass HTPasswd admin, **EFS file system**, GitOps bootstrap outputs, **API endpoint CIDR restrictions**, **channel-based version pinning**
- **HTPasswd IDP** (`htpasswd-idp`): Shared HTPasswd identity provider + group membership
- **Bootstrap admin** (`bootstrap-admin`): Short-lived bootstrap HTPasswd user for GitOps `oc login`
- **Bastion** (`bastion`): Deprecated; optional bastion for sshuttle (use Client VPN instead)
- **Client VPN** (`client-vpn`): Optional AWS Client VPN endpoint for private cluster access (recommended)

### Module Architecture

Each module is **self-contained** and **reusable**:

- **Inputs**: Well-defined variables with descriptions and types
- **Outputs**: Clear outputs for integration with other modules
- **Documentation**: Complete README.md with usage examples
- **State Isolation**: Modules can be used independently or composed together

## Makefile and scripts

Use `make cluster.<name>.<operation>` — see `make help` and [scripts/README.md](scripts/README.md).

Common operations: `init`, `plan`, `apply`, `bootstrap`, `login`, `validate`, `validate-account`, `validate-network`, `vpn-config`, `destroy`, `sleep`.

```bash
make cluster.egress-zero.validate
make cluster.egress-zero.apply
make cluster.egress-zero.bootstrap
```

## Further reading

| Topic | Document |
|-------|----------|
| Prerequisites (account, full-stack, BYO) | [docs/prerequisites/index.md](docs/prerequisites/index.md) |
| Enablement (three-repository pattern) | [docs/deployment/enablement.md](docs/deployment/enablement.md) |
| Local multi-repo dev (Gitea + Argo) | [docs/guides/local-multi-repo-dev.md](docs/guides/local-multi-repo-dev.md) |
| Cluster examples | [clusters/README.md](clusters/README.md) |
| Module reference | [docs/modules/cluster.md](docs/modules/cluster.md) |
| Validation scripts | [docs/operations/validation.md](docs/operations/validation.md) |
| Egress-zero GitOps | [docs/egress-zero-gitops.md](docs/egress-zero-gitops.md) |
| CI/CD | [docs/CI_CD.md](docs/CI_CD.md) |

Local docs preview: `make docs-preview`

## Documentation

**Published site:** [https://rh-mobb.github.io/validated-pattern-terraform-rosa/](https://rh-mobb.github.io/validated-pattern-terraform-rosa/)

| Resource | Path |
|----------|------|
| Documentation home | [docs/index.md](docs/index.md) |
| Prerequisites | [docs/prerequisites/index.md](docs/prerequisites/index.md) |
| Enablement guide | [docs/deployment/enablement.md](docs/deployment/enablement.md) |
| Module reference | [docs/modules/cluster.md](docs/modules/cluster.md) |
| Validation scripts | [docs/operations/validation.md](docs/operations/validation.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

Internal (not on published site): [PLAN.md](PLAN.md), [docs/TODO.md](docs/TODO.md)

Local preview: `make docs-preview`

## Module Status

- ✅ **network-public**: Production-ready
- ✅ **network-private**: Production-ready
- ⚠️ **network-egress-zero**: Deprecated (use `network-private` with `zero_egress = true`)
- ✅ **iam**: Production-ready (includes KMS keys, IAM roles for operators)
- ✅ **cluster**: Production-ready (optional break-glass IDP, EFS storage, GitOps bootstrap)
- ✅ **bastion**: Deprecated (use client-vpn)

## Development Setup

### Reference Repositories

To improve Cursor's accuracy and provide better code suggestions, clone the following reference repositories into the `./reference/` directory:

```bash
# Create reference directory if it doesn't exist
mkdir -p reference

# Clone reference repositories
cd reference

# 1. ROSA HCP Dedicated VPC - Comprehensive production example
git clone https://github.com/redhat-rosa/rosa-hcp-dedicated-vpc.git rosa-hcp-dedicated-vpc

# 2. Terraform ROSA - Red Hat MOBB's all-in-one ROSA module
git clone https://github.com/rh-mobb/terraform-rosa.git terraform-rosa

# 3. Terraform Provider RHCS - Source code for the RHCS provider
git clone https://github.com/terraform-redhat/terraform-provider-rhcs.git terraform-provider-rhcs

# 4. OCM SDK - Go SDK for OCM API
git clone https://github.com/openshift-online/ocm-sdk-go.git ocm-sdk-go

# 5. GitOps cluster-config (Day 2 manifests — local dev loop)
git clone https://github.com/rh-mobb/rosa-cluster-config.git rosa-cluster-config

# 6. Helm charts (bootstrap + app-of-apps — local dev loop)
git clone https://github.com/rh-mobb/validated-pattern-helm-charts.git validated-pattern-helm-charts

cd ..
```

**Local multi-repo development:** After cloning cluster-config and helm-charts under `reference/`, use `make cluster.<profile>.bootstrap-gitea` and `make dev.private.sync`. See [local-multi-repo-dev.md](docs/guides/local-multi-repo-dev.md).

**Additional Reference Files:**

The following files should be downloaded/exported to the `./reference/` directory:

- **OCM API Specification** (`./reference/OCM.json`):
  - **Purpose**: Complete OpenAPI specification for the OpenShift Cluster Manager (OCM) API
  - **How to obtain**: Export from OCM API endpoint or download from OCM documentation
  - **Useful for**: Verifying API field names, structures, and available endpoints when implementing provider features
  - **Example**: Used to verify CloudWatch audit log structure (`AWS.audit_log.role_arn`)

**Why clone/download these repositories and files?**

- **Improved Cursor Accuracy**: Having these repositories locally allows Cursor to reference actual ROSA HCP Terraform patterns, improving code suggestions and understanding
- **Reference Implementations**: These repositories contain production-grade examples and patterns that can be referenced when implementing new features
- **Provider Documentation**: The provider source code includes comprehensive documentation and examples
- **Pattern Matching**: Cursor can better understand ROSA HCP patterns by analyzing these reference implementations

**What each repository/file provides:**

1. **rosa-hcp-dedicated-vpc**: Advanced production features (API endpoint security, secrets management, logging, SIEM, storage, VPN, bootstrap scripts, alerting, ingress)
2. **terraform-rosa**: Module structure patterns, file organization, simpler deployment patterns
3. **terraform-provider-rhcs**: Complete provider documentation, examples, and resource implementations
4. **ocm-sdk-go**: Go SDK for the OCM API - useful for verifying SDK method names and patterns when implementing provider features
5. **OCM.json**: OpenAPI specification for the OCM API - authoritative source for API field names, structures, and endpoints

**Note**: These repositories are for reference only and are not part of the main repository. They are excluded from version control (see `.gitignore`).

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

**Quick Start:**
1. Review [PLAN.md](PLAN.md) before making changes
2. Follow [.cursorrules](.cursorrules) guidelines
3. Check `./reference/` repositories for similar patterns before implementing new features
4. Install development tools (see [CONTRIBUTING.md](CONTRIBUTING.md) for macOS/Linux instructions)
5. Run tests: `make test`
6. Update [CHANGELOG.md](CHANGELOG.md) with changes
7. Ensure all code passes linting: `make lint`

For detailed setup instructions, development workflow, and code style guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## References

- [ROSA HCP Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest)
- **OCM API Specification**: `./reference/OCM.json` - OpenAPI spec for OCM API (see Reference Repositories section above)
- **OCM SDK**: `./reference/ocm-sdk-go/` - Go SDK for OCM API (see Reference Repositories section above)
- [OCM SDK Source](https://github.com/openshift-online/ocm-sdk-go) - GitHub repository for OCM SDK
- [Red Hat MOBB Rules](https://github.com/rh-mobb/mobb-rules)

## License

Copyright 2024 Red Hat, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
