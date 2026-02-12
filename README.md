# ROSA HCP Infrastructure

Production-grade Terraform repository for deploying Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP).

## Overview

This repository provides reusable Terraform modules and example configurations for deploying ROSA HCP clusters with different network topologies and security postures. The architecture follows a **Directory-Per-Cluster** pattern to ensure state isolation and proper lifecycle management.

### Repository Structure

The repository is organized around infrastructure modules:

- **Infrastructure**: Foundational AWS and ROSA resources (VPC, IAM roles and KMS keys, cluster with EFS, GitOps bootstrap script)


## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Red Hat Cloud Services (RHCS) token (set via `TF_VAR_token` environment variable)
- `oc` CLI installed (for cluster access)
- `sshuttle` installed (for egress-zero cluster access via bastion) - `brew install sshuttle` on macOS

### Deploy a Public Cluster

**1. Set required environment variables:**
```bash
export TF_VAR_token="your-rhcs-token"
export TF_VAR_admin_password="your-secure-password"  # Optional, for admin user
```

**2. Initialize, plan, and apply:**

Using Makefile (recommended for local development):
```bash
# Initialize Terraform
make cluster.public.init

# Review the plan
make cluster.public.plan

# Apply the configuration
make cluster.public.apply
```

Or using scripts directly (recommended for CI/CD):
```bash
# Initialize infrastructure
./scripts/cluster/init-infrastructure.sh public

# Plan infrastructure
./scripts/cluster/plan-infrastructure.sh public

# Apply infrastructure
./scripts/cluster/apply-infrastructure.sh public
```

**3. Access the cluster:**
```bash
# Show cluster endpoints
make cluster.public.show-endpoints
# or
./scripts/info/show-endpoints.sh public

# Login to the cluster
make cluster.public.login
# or
./scripts/info/login.sh public

# Show admin credentials
make cluster.public.show-credentials
# or
./scripts/info/show-credentials.sh public
```

**4. Bootstrap GitOps (after cluster is ready):**
```bash
# Bootstrap GitOps operator on the cluster
make cluster.public.bootstrap
```

**5. Destroy the cluster:**
```bash
# Destroy all resources (with confirmation)
make cluster.public.destroy
# or
./scripts/cluster/destroy-infrastructure.sh public

# Sleep cluster (preserves DNS, admin password, IAM, etc. for easy restart)
make cluster.public.sleep
# or
AUTO_APPROVE=true ./scripts/cluster/cleanup-infrastructure.sh public
```

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
│       ├── cluster/            # ROSA HCP Cluster module (includes identity provider, EFS storage, GitOps bootstrap script)
│       └── bastion/            # Bastion host for egress-zero cluster access
└── clusters/                   # Cluster configurations
    ├── public/                 # Example public cluster (reference)
    │   └── terraform.tfvars   # Cluster-specific variables
    └── egress-zero/            # Example egress-zero cluster (reference)
        └── terraform.tfvars   # Cluster-specific variables
```

### Infrastructure Modules

**Infrastructure** (`modules/infrastructure/`):
- **Network** (`network-public`, `network-private`, `network-existing`): VPC, subnets, NAT gateways, VPC endpoints
- **IAM** (`iam`): IAM roles, OIDC configuration, **KMS keys** (EBS, EFS, ETCD), **IAM roles for operators** (CloudWatch logging, Cert Manager, Secrets Manager, CSI drivers)
- **Cluster** (`cluster`): ROSA HCP cluster, machine pools, identity provider, **EFS file system**, GitOps bootstrap script
- **Bastion** (`bastion`): Optional bastion host for egress-zero cluster access

### Module Architecture

Each module is **self-contained** and **reusable**:

- **Inputs**: Well-defined variables with descriptions and types
- **Outputs**: Clear outputs for integration with other modules
- **Documentation**: Complete README.md with usage examples
- **State Isolation**: Modules can be used independently or composed together

## Using Modules to Compose Custom Infrastructure

The modules are designed to be **composable** and **reusable**. You can mix and match modules to create custom infrastructure configurations.

### Basic Module Composition

Here's how the example clusters compose modules:

```hcl
# terraform/10-main.tf
module "network" {
  source = "../../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  tags        = var.tags
}

module "iam" {
  source = "../../modules/infrastructure/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name
  operator_role_prefix = var.cluster_name
  tags                 = var.tags
}

module "cluster" {
  source = "../../modules/infrastructure/cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  subnet_ids         = concat(module.network.private_subnet_ids, module.network.public_subnet_ids)
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url
  # ... other cluster configuration
}
```

The cluster module provides GitOps bootstrap functionality via a script that deploys the OpenShift GitOps operator and configures it to use your cluster-config Git repository. The bootstrap script is run manually after cluster deployment using `make cluster.<name>.bootstrap`.

### Multi-Team Scenarios

The modules support **separation of concerns** where different teams own different aspects of the infrastructure:

#### Scenario 1: Network Team Owns VPC

**Network Team** (`clusters/production/network/`):
```hcl
# Network team creates and manages VPC
module "network" {
  source = "../../../modules/network-private"

  name_prefix = "prod-network"
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true
  tags = {
    Team = "Network"
    Environment = "Production"
  }
}

# Outputs VPC details for other teams
output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}
```

**Platform Team** (`clusters/production/cluster/`):
```hcl
# Platform team receives network team's outputs as input variables
# In a multi-team scenario, network outputs would be passed via:
# - Environment variables: TF_VAR_vpc_id, TF_VAR_subnet_ids, etc.
# - Or a shared tfvars file generated from network team's outputs

module "iam" {
  source = "../../../modules/iam"
  # ... IAM configuration
}

module "cluster" {
  source = "../../../modules/cluster"

  vpc_id     = var.vpc_id      # From network team's outputs
  subnet_ids = var.subnet_ids  # From network team's outputs
  # ... cluster configuration
}
```

**Note**: In a multi-team scenario, teams would coordinate via:
- **Shared state outputs**: Network team exports outputs, platform team imports as variables
- **CI/CD pipeline**: Infrastructure outputs → Platform team inputs
- **Terraform workspaces**: Separate workspaces with output sharing

#### Scenario 2: IAM Team Owns Roles

**IAM Team** (`clusters/production/iam/`):
```hcl
# IAM team creates and manages all ROSA IAM resources
module "iam" {
  source = "../../../modules/iam"

  cluster_name         = "production"
  account_role_prefix  = "prod"
  operator_role_prefix = "prod"
  tags = {
    Team = "IAM"
    Environment = "Production"
  }
}

# Outputs role ARNs for platform team
output "installer_role_arn" {
  value = module.iam.installer_role_arn
}

output "worker_role_arn" {
  value = module.iam.worker_role_arn
}

output "oidc_config_id" {
  value = module.iam.oidc_config_id
}
```

**Platform Team** (`clusters/production/cluster/`):
```hcl
# Platform team receives IAM team's outputs as input variables
# IAM outputs would be passed via environment variables or tfvars file

module "cluster" {
  source = "../../../modules/cluster"

  installer_role_arn = var.installer_role_arn  # From IAM team's outputs
  worker_role_arn    = var.worker_role_arn     # From IAM team's outputs
  oidc_config_id     = var.oidc_config_id      # From IAM team's outputs
  # ... cluster configuration
}
```

#### Scenario 3: Complete Separation (Network, IAM, Cluster)

**Network Team** (`clusters/production/network/terraform.tfstate`):
- Manages VPC, subnets, VPC endpoints
- Outputs: `vpc_id`, `subnet_ids`, `vpc_cidr`

**IAM Team** (`clusters/production/iam/terraform.tfstate`):
- Manages OIDC, account roles, operator roles
- Outputs: `installer_role_arn`, `worker_role_arn`, `oidc_config_id`, `oidc_endpoint_url`

**Platform Team** (`clusters/production/cluster/terraform.tfstate`):
- Manages cluster deployment
- Reads from both network and IAM remote states
- Composes modules using outputs from other teams

### Creating Your Own Cluster Configuration

**1. Create a new cluster directory:**
```bash
mkdir -p clusters/my-cluster
cd clusters/my-cluster
```

**2. Create `00-providers.tf`:**
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }

  # Optional: Configure remote state backend
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "my-cluster/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}

provider "rhcs" {
  token = var.token
}
```

**3. Create `01-variables.tf`:**
```hcl
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "token" {
  description = "RHCS API token"
  type        = string
  sensitive   = true
  nullable    = false
}

# Add other variables as needed
```

**4. Create `10-main.tf` with module composition:**
```hcl
# Compose modules to create your infrastructure
module "network" {
  source = "../../modules/network-public"  # or network-private

  name_prefix = var.cluster_name
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true
  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

module "iam" {
  source = "../../modules/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name
  operator_role_prefix = var.cluster_name
  tags = {
    Environment = "production"
  }
}

module "cluster" {
  source = "../../modules/cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url
  vpc_cidr           = module.network.vpc_cidr_block
  availability_zones = module.network.private_subnet_azs

  # Cluster configuration
  private    = true
  multi_az   = true
  # ... other cluster settings
}
```

**5. Create `terraform.tfvars`:**
```hcl
cluster_name = "my-cluster"
region       = "us-east-1"
# token should be set via TF_VAR_token environment variable
```

**6. Use Makefile pattern rules:**
```bash
# The Makefile automatically detects cluster directories
# Just use the cluster name as the suffix
make init.my-cluster
make plan.my-cluster
make apply.my-cluster
```

## Available Modules

### Network Modules

- **network-public**: Public VPC with NAT Gateways
  - Public and private subnets
  - Zonal NAT Gateways (one per AZ)
  - VPC endpoints (S3, ECR, STS)
  - ROSA-required subnet tags

- **network-private**: Private VPC with PrivateLink API
  - Private subnets only
  - VPC endpoints for all AWS services
  - Optional Regional NAT Gateway for internet egress (default: enabled)
  - **Zero-egress mode**: Set `zero_egress = true` to disable NAT Gateway and enable zero egress controls
  - VPC Flow Logs support (optional, via `flow_log_s3_bucket`)
  - ROSA-required subnet tags

- **network-egress-zero**: ⚠️ **DEPRECATED** - Use `network-private` with `zero_egress = true`
  - This module remains for backward compatibility but is deprecated
  - New deployments should use the consolidated `network-private` module

### Core Modules

- **iam**: IAM roles, OIDC configuration, KMS keys, and operator IAM roles
  - Account roles (Installer, Support, Worker)
  - Operator roles (Ingress, Control Plane, CSI, etc.)
  - OIDC configuration and provider
  - **KMS keys** (EBS, EFS, ETCD encryption)
  - **Storage IAM resources** (KMS CSI policy, EBS CSI attachment, EFS CSI role/policy)
  - **CloudWatch logging IAM** (audit logging and application logging)
  - **Cert Manager IAM** (for AWS Private CA)
  - **Secrets Manager IAM** (for ArgoCD Vault Plugin)
  - Uses upstream `terraform-redhat/rosa-hcp/rhcs` modules

- **cluster**: ROSA HCP cluster deployment
  - Thin wrapper with organizational defaults
  - Machine pool management
  - Automatic version detection
  - Machine type validation
  - Identity provider (HTPasswd admin user) - integrated
  - **EFS file system** (storage infrastructure that depends on cluster security groups)
  - GitOps bootstrap script - provided (run manually via `make cluster.<name>.bootstrap`)
  - CloudWatch audit logging configuration (IAM role from IAM module)
  - Cluster termination protection

- **bastion**: Bastion host for egress-zero cluster access
  - SSM Session Manager support
  - Pre-installed tools (`oc`, `kubectl`)
  - **Development/demo use only** - not for production

## Scripts and Automation

This repository uses bash scripts for cluster management, with a Makefile wrapper for convenience. Scripts can be called directly from CI/CD pipelines without requiring Make.

### Script-Based Approach

All cluster operations are implemented as bash scripts in the `scripts/` directory:

- **`scripts/cluster/`**: Infrastructure and configuration management
- **`scripts/tunnel/`**: Tunnel management for egress-zero clusters
- **`scripts/utils/`**: Utility functions (password retrieval, token management, etc.)
- **`scripts/info/`**: Cluster information and access

See [scripts/README.md](scripts/README.md) for complete documentation.

### Makefile Usage

The Makefile provides convenient targets for managing clusters. Use **pattern syntax** for flexibility:

### Pattern Syntax (Recommended)

```bash
# Pattern: make <action>.<cluster>
make init.public
make plan.egress-zero
make apply.egress-zero
make destroy.public
make login.egress-zero
make tunnel-start.egress-zero
```

### Available Actions

**Cluster Management:**
- `init.<cluster>` - Initialize infrastructure
- `plan.<cluster>` - Plan infrastructure changes
- `apply.<cluster>` - Apply infrastructure
- `destroy.<cluster>` - Destroy infrastructure

**Infrastructure Management:**
- `init-infrastructure.<cluster>` - Initialize infrastructure only
- `plan-infrastructure.<cluster>` - Plan infrastructure changes
- `apply-infrastructure.<cluster>` - Apply infrastructure
- `destroy-infrastructure.<cluster>` - Destroy infrastructure

**GitOps:**
- `bootstrap.<cluster>` - Bootstrap GitOps operator on cluster

**Cluster Access:**
- `login.<cluster>` - Login to cluster using `oc`
- `show-endpoints.<cluster>` - Show API and console URLs
- `show-credentials.<cluster>` - Show admin credentials and endpoints

**Bastion & Tunnel (Egress-Zero clusters):**
- `tunnel-start.<cluster>` - Start sshuttle VPN tunnel
- `tunnel-stop.<cluster>` - Stop sshuttle tunnel
- `tunnel-status.<cluster>` - Check tunnel status
- `bastion-connect.<cluster>` - Connect to bastion via SSM

**Code Quality:**
- `make fmt` - Format all Terraform files
- `make validate` - Validate all Terraform configurations
- `make validate-modules` - Validate all modules

**Utilities:**
- `make clean` - Clean Terraform files
- `make init-all` - Initialize all example clusters
- `make plan-all` - Plan all example clusters

See `make help` for complete list of targets.

## Bastion Host for Egress-Zero Clusters

> **⚠️ Development/Demo Use Only**: The bastion host is provided for development and demonstration purposes. For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections instead.

Egress-zero clusters include an optional bastion host for secure access:

- **SSM Session Manager**: No public IP, access via AWS Systems Manager (recommended)
- **Pre-installed Tools**: OpenShift CLI (`oc`), Kubernetes CLI (`kubectl`)
- **sshuttle VPN Tunnel**: Routes all VPC traffic through bastion for full cluster access

### Using sshuttle Tunnel

The `tunnel-start.<cluster>` target creates a VPN-like tunnel using `sshuttle`:

```bash
# Start tunnel (requires sudo - you'll be prompted for password)
make tunnel-start.egress-zero

# Tunnel is now active - all traffic to VPC CIDR routes through bastion
# You can now use oc login with the direct API URL
make login.egress-zero

# Stop tunnel when done
make tunnel-stop.egress-zero
```

**Why sshuttle?** Unlike SSH port forwarding, sshuttle routes **all VPC traffic** through the bastion, enabling OAuth flows required for `oc login` to work correctly.

See `modules/bastion/README.md` for detailed documentation.

## Admin User Management

The cluster module includes identity provider functionality that creates a temporary admin user for initial cluster access. This is controlled by the `enable_identity_provider` variable (default: `true` when `persists_through_sleep = true`).

**Configuration**:
```hcl
module "cluster" {
  # ... other configuration ...

  # Identity provider configuration (integrated in cluster module)
  enable_identity_provider = true
  admin_username           = "admin"  # Optional, defaults to "admin"
  admin_password_for_bootstrap = var.admin_password  # Set via TF_VAR_admin_password
  admin_group              = "cluster-admins"  # Optional, defaults to "cluster-admins"
}
```

**Best Practice**: Set `enable_identity_provider = false` once you've configured an external identity provider (LDAP, OIDC, etc.).

The admin password is stored in AWS Secrets Manager (`{cluster_name}-credentials` secret) and persists through sleep operations for easy cluster restart.

## State Management

Each cluster directory uses its own Terraform state for isolation:

**Local State (Default):**
```hcl
# State stored locally in cluster directory
# No backend configuration needed
```

**Remote State (Recommended for Production):**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "my-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Multi-Team State Sharing:**
**Multi-Team Output Sharing**:
```hcl
# Teams share outputs via input variables (pipeline-friendly approach)
# Network team exports outputs, platform team receives as variables

# Network team exports:
# terraform output -json > network-outputs.json

# Platform team receives via:
# - Environment variables: TF_VAR_vpc_id, TF_VAR_subnet_ids, etc.
# - Or tfvars file: terraform.tfvars
# - Or CI/CD pipeline: infrastructure outputs → configuration inputs
```

**Alternative: Remote State** (if needed):
```hcl
# If remote state access is required, use terraform_remote_state data source
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-org-terraform-state"
    key    = "production/network/terraform.tfstate"
    region = "us-east-1"
  }
}
```

**Note**: The default approach uses input variables for better CI/CD pipeline integration and state isolation.

## Security Best Practices

- **Never commit secrets**: Use environment variables (`TF_VAR_token`, `TF_VAR_admin_password`) or AWS Secrets Manager
- **Least Privilege**: All IAM roles follow least-privilege principles
- **State Encryption**: Always enable encryption for S3 backends
- **State Locking**: Use DynamoDB for state locking in production
- **Separate State**: Each cluster has its own state file for isolation

## Destroy Protection

This repository implements a **destroy protection pattern** to prevent accidental resource destruction, which is critical for production environments and organizations with strict change control processes.

### How It Works

By default, all resources are active and managed by Terraform. The `persists_through_sleep` variable (default: `true`) controls whether resources persist or are put to sleep. Resources are gated using the `count` meta-argument:

- **When `persists_through_sleep = true` (default)**: `count = 1` → Resources exist and are managed by Terraform
- **When `persists_through_sleep = false`**: `count = 0` → Terraform puts resources to sleep (calls provider delete methods)

When you set `persists_through_sleep = false` and run `terraform apply`, Terraform sees that `count` has changed from `1` to `0`, which triggers resource destruction. This prevents accidental `terraform destroy` operations by requiring an explicit variable change.

### Usage

**Default Behavior (Protected):**
```hcl
# In terraform.tfvars
persists_through_sleep = true  # Default - resources are active
```

**To Allow Destruction:**
```hcl
# In terraform.tfvars
persists_through_sleep = false  # Puts cluster to sleep (destroys resources)
```

**Workflow for Intentional Destruction:**

**Option 1: Using Makefile (Recommended)**
```bash
# Permanently destroy all infrastructure (uses terraform destroy)
# Prompts for confirmation, destroys everything including preserved resources
make cluster.<cluster>.destroy

# Force destroy without confirmation prompt
make cluster.<cluster>.destroy_force

# Sleep cluster (sets persists_through_sleep=false and runs terraform apply)
# No confirmation prompt, preserves DNS, admin password, IAM, KMS, EFS, etc.
make cluster.<cluster>.sleep
```

**Option 2: Manual Terraform Commands**
1. **For sleep**: Set `persists_through_sleep = false` in `terraform.tfvars` (or use `TF_VAR_persists_through_sleep=false`) and run `terraform apply` - Terraform will sleep cluster (because `count` becomes `0`)
2. **For destroy**: Run `terraform destroy` - This destroys everything regardless of `persists_through_sleep` settings
3. Set `persists_through_sleep = true` again (or remove the variable) for future protection

### Per-Resource Overrides

For fine-grained control, you can override the global `persists_through_sleep` setting for specific resource types:

```hcl
# Global setting
persists_through_sleep = true

# Per-resource overrides
persists_through_sleep_cluster = false  # Allow sleeping cluster while preserving other resources
persists_through_sleep_iam     = false  # Allow sleeping IAM roles while preserving OIDC
persists_through_sleep_network = true   # Keep network active even if global is false
```

### Resources That Persist Through Sleep

Some resources are **never gated** and persist even when cluster is slept:
- **OIDC Configuration and Provider**: Shared across clusters, preserved for reuse
- **Subnet Tags**: Read-only tags managed by ROSA (in `network-existing` module)

### Benefits

- **Safety**: Prevents accidental sleeps by default
- **Compliance**: Works with permission constraints and change control processes
- **Flexibility**: Per-resource overrides for common scenarios (e.g., sleep cluster but preserve IAM/OIDC)
- **Bank-Ready**: Designed for enterprise environments with strict change control

### Example: Sleeping a Cluster While Preserving IAM

```hcl
# terraform.tfvars
persists_through_sleep = true
persists_through_sleep_cluster = false  # Only cluster resources can be slept
```

This allows sleeping the cluster while preserving IAM roles and OIDC configuration for reuse with other clusters.

### Sleep vs Destroy

**Sleep** (`make sleep.<cluster>`) is designed for temporarily shutting down a cluster while preserving resources for easy restart:

- **Preserves**:
  - DNS domain (if `enable_persistent_dns_domain=true`) - cluster will use the same domain when recreated
  - Admin password in AWS Secrets Manager - same credentials work after restart
  - IAM roles and OIDC configuration - reused when cluster is recreated
  - KMS keys and EFS (if not explicitly destroyed) - storage encryption keys preserved
  - GitOps configurations - all cluster configs and applications are managed via GitOps, so they'll be automatically redeployed when the cluster is recreated

- **Destroys**:
  - ROSA HCP cluster (compute nodes, control plane)
  - VPC and networking resources (unless protected)
  - Bastion host (if created)

**Important Notes**:
- **Sleep does NOT hibernate the cluster** - it destroys the cluster resources
- The cluster must be recreated using `make apply.<cluster>` to "wake" it
- Since GitOps manages all important configurations and applications, they will be automatically redeployed when the cluster is recreated
- This is ideal for cost savings (turn off clusters when not in use) while maintaining the same configuration

**Destroy** (`make cluster.<cluster>.destroy`) is for permanent removal and prompts for confirmation. Use `make cluster.<cluster>.destroy_force` to skip the confirmation prompt.

## Documentation

- **[PLAN.md](PLAN.md)** - Detailed implementation plan and architecture decisions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes
- **[docs/TODO.md](docs/TODO.md)** - Tracking of features from reference implementations
- **[docs/improvements/ingress.md](docs/improvements/ingress.md)** - Ingress controller implementation plan
- **Module READMEs** - See `modules/*/README.md` for module-specific documentation
- **[.cursorrules](.cursorrules)** - Development guidelines and best practices

## Module Status

- ✅ **network-public**: Production-ready
- ✅ **network-private**: Production-ready
- ⚠️ **network-egress-zero**: Deprecated (use `network-private` with `zero_egress = true`)
- ✅ **iam**: Production-ready (includes KMS keys, IAM roles for operators)
- ✅ **cluster**: Production-ready (includes identity provider, EFS storage, GitOps bootstrap script)
- ✅ **bastion**: Production-ready (dev/demo use only)

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

cd ..
```

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
