# ROSA HCP Infrastructure - Implementation Plan

## Executive Summary

This document outlines the implementation plan for a production-grade Terraform repository for deploying Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP). The architecture follows a **Directory-Per-Cluster** pattern to ensure state isolation and supports multiple network topologies (standard, private, egress zero).

**Repository Strategy**: This is Repository 1 (Infrastructure) - a Terraform repository dedicated to provisioning AWS VPC, IAM roles, and the ROSA HCP cluster itself. GitOps bootstrap is integrated into the cluster module. Additional Day 2 operations (cert-manager, external-dns, ingress controllers) are deployed via GitOps using Helm charts in the cluster-config repository.

---

## Step 1: Repository Structure

**Repository Name**: `rosa-hcp-infrastructure`

**Directory Structure**:
```
rosa-hcp-infrastructure/
├── modules/
│   └── infrastructure/         # Infrastructure modules
│       ├── network-public/     # Public VPC with NAT Gateways
│       ├── network-private/     # Private VPC (PrivateLink API, supports egress-zero mode)
│       ├── network-existing/    # Use existing VPC
│       ├── iam/                # IAM & OIDC module
│       ├── cluster/            # ROSA HCP Cluster module (includes identity provider, storage, GitOps bootstrap)
│       └── bastion/            # Bastion host for private cluster access
├── terraform/                  # Unified Terraform configuration (shared across clusters)
│   ├── 00-providers.tf
│   ├── 01-variables.tf
│   ├── 10-main.tf             # Conditionally uses network-public or network-private
│   └── 90-outputs.tf
└── clusters/
    ├── public/                 # Example public cluster (reference)
    │   └── terraform.tfvars   # Cluster-specific variables (network_type="public")
    └── egress-zero/            # Example egress-zero cluster (reference)
        └── terraform.tfvars   # Cluster-specific variables (network_type="private", zero_egress=true)
```

---

## Step 2: Network Modules

### 2.1 Network Module: Public

**Path**: `modules/infrastructure/network-public/`

**Provider**: `hashicorp/aws`

**Resources**:
- 1 VPC with `enable_dns_hostnames = true` and `enable_dns_support = true`
- Private Subnets (for Worker Nodes): 3 subnets across 3 AZs if `multi_az = true`, 1 subnet if `multi_az = false`
- 1 Internet Gateway
- **NAT Gateway Configuration** (conditional based on `nat_gateway_type`):
  - **Regional NAT Gateway** (default): Single regional NAT Gateway that automatically spans AZs
    - **No public subnets required** (Regional NAT Gateway doesn't need them)
    - Lower cost (~$32/month vs ~$96/month for 3 zonal gateways)
    - Simpler architecture, enhanced security
    - Note: May take up to 60 minutes to expand to new AZs
  - **Zonal NAT Gateways** (optional): 1 NAT Gateway per AZ (3 if `multi_az = true`, 1 if `multi_az = false`)
    - **Requires Public Subnets** (one per AZ for NAT Gateways)
    - Immediate availability, no expansion delay
    - Higher cost but predictable per-AZ routing
- Route tables for private subnets (and public subnets if using zonal NAT)
- VPC endpoints for AWS services (S3, ECR, etc.) for cost optimization

**Tags** (CRITICAL - ROSA requires these):
- Private Subnets: `kubernetes.io/role/internal-elb = "1"`
- Public Subnets (if using zonal NAT): `kubernetes.io/role/elb = "1"`
- All resources: Standard tags (Name, Environment, ManagedBy, etc.)

**Variables**:
- `vpc_cidr` (default: "10.0.0.0/16")
- `availability_zones` (list of AZs - should match `multi_az`: 3 AZs if true, 1 AZ if false)
- `multi_az` (default: true, boolean - creates resources across multiple AZs for HA)
- `private_subnet_cidrs` (list - length should match number of AZs)
- `public_subnet_cidrs` (list, required only if `nat_gateway_type = "zonal"` - length should match number of AZs)
- `nat_gateway_type` (default: "regional", options: "regional" | "zonal")
- `enable_nat_gateway` (default: true)
- `tags` (map of tags)

**Outputs**:
- `vpc_id`
- `vpc_cidr_block`
- `private_subnet_ids` (list)
- `public_subnet_ids` (list, empty if using regional NAT)
- `nat_gateway_id` (single ID for regional, or list of IDs for zonal)
- `nat_gateway_type` (output for reference)
- `internet_gateway_id`

**Architecture Decision**:
- **Default: Regional NAT Gateway** - Recommended for cost savings, simplicity, and security (no public subnets needed)
- **Use Zonal NAT Gateways** if you need immediate availability without expansion delays or require private connectivity scenarios

---

### 2.2 Network Module: Private

**Path**: `modules/infrastructure/network-private/`

**Provider**: `hashicorp/aws`

**Resources**:
- 1 VPC with `enable_dns_hostnames = true` and `enable_dns_support = true`
- Private Subnets (for Worker Nodes): 3 subnets across 3 AZs if `multi_az = true`, 1 subnet if `multi_az = false`
- **NO Public Subnets** (PrivateLink only)
- **NO Internet Gateway**
- **NAT Gateway** (optional, controlled by `enable_nat_gateway`):
  - Default: Enabled for standard private clusters (allows internet egress via NAT)
  - Disabled when `zero_egress = true` (zero-egress mode)
- VPC endpoints for all AWS services (S3, ECR, CloudWatch, STS, etc.)
- Route tables for private subnets only
- PrivateLink endpoints configuration
- **Zero-egress mode** (when `zero_egress = true`):
  - Additional security group with strict egress rules (HTTPS 443, DNS 53 only)
  - VPC Flow Logs support (optional, via `flow_log_s3_bucket`)
  - **Note**: ROSA API VPC endpoint security group configuration is handled by the cluster module (see Cluster Module section)

**Tags** (CRITICAL):
- Private Subnets: `kubernetes.io/role/internal-elb = "1"`
- All resources: Standard tags

**Variables**:
- `vpc_cidr`
- `availability_zones` (list of AZs - should match `multi_az`: 3 AZs if true, 1 AZ if false)
- `multi_az` (default: true, boolean - creates resources across multiple AZs for HA)
- `private_subnet_cidrs` (list - length should match number of AZs)
- `enable_nat_gateway` (default: true, boolean - set to false for egress-zero mode)
- `zero_egress` (default: false, boolean - enables zero-egress mode when true, matches ROSA API property name)
- `flow_log_s3_bucket` (optional, string - enables VPC Flow Logs if provided)
- `tags`

**Outputs**:
- `vpc_id`
- `vpc_cidr_block`
- `private_subnet_ids` (list)
- `vpc_endpoint_ids` (map of service -> endpoint ID)
- `security_group_id` (for egress-zero mode, null otherwise)

**Note**: This topology requires PrivateLink for API access and VPC endpoints for all AWS service access. When `zero_egress = true`, the module operates in zero-egress mode with no internet egress allowed.

---

### 2.3 Network Module: Egress Zero (Consolidated)

**⚠️ DEPRECATED**: The `network-egress-zero` module has been **consolidated into `network-private`**.

**Migration**: Use `network-private` with `enable_nat_gateway = false` and `zero_egress = true` to achieve zero-egress functionality.

**Path**: `modules/infrastructure/network-private/` (with `zero_egress = true`)

**How to Use**:
```hcl
module "network" {
  source = "../../modules/infrastructure/network-private"

  # ... standard variables ...

  enable_nat_gateway = false  # No NAT Gateway for zero-egress
  zero_egress        = true    # Enable zero egress mode (matches ROSA API property name)
  flow_log_s3_bucket = var.flow_log_s3_bucket  # Optional: VPC Flow Logs
}
```

**Note**: The standalone `network-egress-zero` module remains for backward compatibility but is deprecated. New deployments should use the consolidated `network-private` module.

---

## Step 3: IAM Module

**Path**: `modules/infrastructure/iam/`

**Provider**: `terraform-redhat/rhcs`

**Resources**:

1. **OIDC Configuration**:
   - `rhcs_rosa_oidc_config`: Managed OIDC configuration
   - `rhcs_rosa_oidc_provider`: The AWS IAM OIDC provider linking to the config above

2. **Account Roles** (using `terraform-redhat/rosa-hcp/rhcs` module):
   - Installer Role
   - Support Role
   - Worker Role
   - These are account-wide but prefixed for uniqueness

3. **Operator Roles** (using individual `rhcs_operator_iam_role` resources):
   - Ingress Operator
   - Control Plane Operator
   - CSI Driver Operator
   - Image Registry Operator
   - Network Operator
   - Node Pool Operator
   - All linked to the OIDC provider

**Variables**:
- `cluster_name` (required)
- `account_role_prefix` (default: cluster_name to ensure uniqueness)
- `operator_role_prefix` (default: cluster_name)
- `tags` (map of tags)

**Outputs**:
- `oidc_config_id`
- `oidc_endpoint_url`
- `oidc_provider_arn`
- `installer_role_arn`
- `support_role_arn`
- `worker_role_arn`
- `operator_role_arns` (map of operator name -> ARN)

---

## Step 4: Cluster Module (Thin Wrapper with Organizational Defaults)

**Path**: `modules/infrastructure/cluster/`

**Provider**: `terraform-redhat/rhcs`

**Architecture Decision**: This is a **thin wrapper module** that provides organizational defaults while passing through all provider variables. This approach balances consistency with flexibility.

**Why Use a Module vs Direct Provider Call?**

**Benefits of Module Approach**:
1. **Organizational Defaults**: Enforces security hardening (private=true, etcd_encryption=true) across all clusters
2. **Consistency**: Ensures all clusters follow organizational standards
3. **Validation**: Can add validation logic for variable combinations
4. **Future Extensibility**: Easy to add org-specific resources (monitoring, integrations)
5. **Documentation**: Module documents organizational standards and best practices
6. **Reusability**: Single source of truth for cluster configuration patterns

**When to Call Provider Directly**:
- One-off clusters with unique requirements
- Prototyping/testing new configurations
- When you need 100% control without any abstraction

**Recommendation**: Use the module for production clusters. Call provider directly only for special cases.

**Resources**:

1. **Cluster Resource**:
   - `rhcs_cluster_rosa_hcp`: The HCP cluster itself
   - **Passes through ALL provider variables** (see Variables section below)

2. **Machine Pools**:
   - `rhcs_hcp_machine_pool`: Default worker pool with autoscaling
   - Additional pools can be created via variables

**Organizational Defaults** (can be overridden):
- `private = true` (PrivateLink API only) - **Enforced by default**
- `etcd_encryption = false`
- `fips = false` (set to true if FIPS compliance required)
- `disable_workload_monitoring = false`
- `multi_az = true` (for machine pools)

**Variables** (Pass-through to Provider):

**Required Variables**:
- `cluster_name` (required)
- `region` (required)
- `vpc_id` (from network module)
- `subnet_ids` (private subnet IDs from network module)
- `installer_role_arn` (from IAM module)
- `support_role_arn` (from IAM module)
- `worker_role_arn` (from IAM module)
- `operator_role_arns` (map from IAM module)
- `oidc_config_id` (from IAM module)

**Cluster Configuration Variables** (all provider variables supported):
- `availability_zones` (list - should match `multi_az`: 3 AZs if true, 1 AZ if false)
- `private` (default: true - organizational default, can override)
- `etcd_encryption` (default: true - organizational default, can override)
- `fips` (default: false)
- `disable_workload_monitoring` (default: false)
- `kms_key_arn` (optional, for encryption)
- `service_cidr` (optional, default: "172.30.0.0/16")
- `pod_cidr` (optional, default: "10.128.0.0/14")
- `host_prefix` (optional, default: 23)
- `channel_group` (optional, default: "stable")
- `version` (optional, e.g., "4.15.0")
- `tags` (map)
- **All other `rhcs_cluster_rosa_hcp` provider variables** - module passes through

**Machine Pool Variables**:
- `machine_pools` (optional, list of machine pool configurations)
  - If not provided, creates default pool with:
    - `multi_az` (default: true)
    - `instance_type` (default: "m5.xlarge")
    - `min_replicas` (default: 3 - recommended: 3 for multi_az, 1 for single AZ)
    - `max_replicas` (default: 6 - recommended: 6 for multi_az, 3 for single AZ)
    - `autoscaling_enabled` (default: true)
    - `name` (default: "worker")
- **All other `rhcs_hcp_machine_pool` provider variables** supported

**Outputs** (Pass-through from Provider):
- `cluster_id`
- `cluster_name`
- `api_url`
- `console_url`
- `kubeconfig` (sensitive)
- `cluster_admin_password` (sensitive)
- **All other `rhcs_cluster_rosa_hcp` outputs** - module passes through

---

## Step 5: Example Cluster Implementations

This step creates **three example clusters** demonstrating different network topologies and security postures:

1. **Public Cluster** (`clusters/public/`) - Development example (reference)
2. **Egress-Zero Cluster** (`clusters/egress-zero/`) - Production-ready example with extra hardening (reference)

### 5.1 Example 1: Public Cluster (Development)

**Path**: `clusters/public/` (uses `terraform/`)

**Purpose**: Development/Testing cluster with internet access via NAT Gateway

**Infrastructure Configuration** (`terraform/10-main.tf`):

The infrastructure layer uses a unified configuration that conditionally selects the network module based on `network_type`:

```hcl
# Conditionally select network module based on network_type
module "network_public" {
  count  = var.network_type == "public" ? 1 : 0
  source = "../../modules/infrastructure/network-public"
  # ... variables
}

module "network_private" {
  count  = var.network_type == "private" ? 1 : 0
  source = "../../modules/infrastructure/network-private"

  enable_nat_gateway = !local.is_egress_zero  # Disable NAT for zero-egress
  zero_egress        = local.is_egress_zero   # Enable zero egress for zero-egress
  # ... other variables
}

locals {
  is_egress_zero = var.network_type == "private" && var.zero_egress
  network = var.network_type == "public" ? module.network_public[0] : module.network_private[0]
}
```

module "iam" {
  source = "../../../../modules/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = "${var.cluster_name}-"
  operator_role_prefix = "${var.cluster_name}-"
  tags                 = var.tags
}

module "cluster" {
  source = "../../../../modules/cluster"

  # Required: Pass outputs from Network and IAM modules
  cluster_name        = var.cluster_name
  region              = var.region
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  installer_role_arn  = module.iam.installer_role_arn
  support_role_arn    = module.iam.support_role_arn
  worker_role_arn     = module.iam.worker_role_arn
  operator_role_arns  = module.iam.operator_role_arns
  oidc_config_id      = module.iam.oidc_config_id

  # Dev defaults - relaxed security for development
  private            = false  # Public API endpoint for easier access
  etcd_encryption    = false  # Dev doesn't require encryption
  multi_az           = var.multi_az
  availability_zones = var.availability_zones

  # Machine pool configuration - smaller for dev
  machine_pools = [
    {
      name                = "worker"
      instance_type       = var.instance_type
      min_replicas        = var.multi_az ? 1 : 1  # Single AZ for cost savings
      max_replicas        = var.multi_az ? 3 : 2
      multi_az            = var.multi_az
      autoscaling_enabled = true
    }
  ]

  tags = var.tags
}
```

**Infrastructure State Management** (`terraform/00-providers.tf`):

```hcl
terraform {
  # Backend configuration is provided via -backend-config flags or environment variables
  # For local development: terraform init -backend-config="path=../../clusters/<name>/infrastructure.tfstate"
  # For CI/CD with S3: terraform init -backend-config="bucket=..." -backend-config="key=..." etc.
  backend "local" {
    # path provided via -backend-config flag or environment variable
  }
  # ... providers
}
```

**Note**: GitOps bootstrap is integrated into the cluster module. The bootstrap script is run manually after cluster deployment using `make cluster.<name>.bootstrap` or by sourcing Terraform outputs and running the script directly.

**Infrastructure Variables** (`clusters/public/terraform.tfvars`):

```hcl
network_type = "public"
zero_egress  = false  # Public clusters don't use zero egress
region       = "us-east-1"
vpc_cidr     = "10.10.0.0/16"
multi_az     = false  # Single AZ for dev cost savings
instance_type = "m5.large"  # Smaller instance for dev
```

---

### 5.2 Example 2: Private Cluster (Development)

**Note**: Private cluster example has been consolidated into `clusters/public/` with `network_type="private"`. See public cluster example.

**Purpose**: Development cluster with PrivateLink API but VPC endpoints for AWS services

**Main Configuration** (`10-main.tf`):

```hcl
module "network" {
  source = "../../../../modules/network-private"

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  multi_az           = var.multi_az
  tags               = var.tags
}

module "iam" {
  source = "../../../../modules/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = "${var.cluster_name}-"
  operator_role_prefix = "${var.cluster_name}-"
  tags                 = var.tags
}

module "cluster" {
  source = "../../../../modules/cluster"

  cluster_name        = var.cluster_name
  region              = var.region
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  installer_role_arn  = module.iam.installer_role_arn
  support_role_arn    = module.iam.support_role_arn
  worker_role_arn     = module.iam.worker_role_arn
  operator_role_arns  = module.iam.operator_role_arns
  oidc_config_id      = module.iam.oidc_config_id

  # Dev defaults - PrivateLink API but relaxed encryption
  private            = true   # PrivateLink API
  etcd_encryption    = false  # Dev doesn't require encryption
  multi_az           = var.multi_az
  availability_zones = var.availability_zones

  machine_pools = [
    {
      name                = "worker"
      instance_type       = var.instance_type
      min_replicas        = var.multi_az ? 1 : 1
      max_replicas        = var.multi_az ? 3 : 2
      multi_az            = var.multi_az
      autoscaling_enabled = true
    }
  ]

  tags = var.tags
}
```

**State Management** (`00-providers.tf`):

```hcl
terraform {
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "clusters/private/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
  # ... providers
}
```

**Terraform Variables** (`terraform.tfvars`):

```hcl
cluster_name      = "dev-private-01"
region            = "us-east-1"
vpc_cidr          = "10.20.0.0/16"
multi_az          = false
availability_zones = ["us-east-1a"]
instance_type     = "m5.large"
```

---

### 5.3 Example 3: Egress-Zero Cluster (Production-Ready)

**Path**: `clusters/egress-zero/` (uses `terraform/`)

**Purpose**: Production-ready cluster with maximum security hardening and zero internet egress

**Main Configuration** (`terraform/10-main.tf`):

The infrastructure layer uses a unified configuration. For zero-egress clusters, set `network_type = "private"` and `zero_egress = true`:

```hcl
# In clusters/egress-zero/terraform.tfvars:
network_type = "private"
zero_egress  = true
flow_log_s3_bucket = var.flow_log_s3_bucket  # Optional: Audit logging
```

The unified infrastructure configuration will automatically use `network-private` with egress-zero settings:

```hcl
module "network_private" {
  count  = var.network_type == "private" ? 1 : 0
  source = "../../modules/infrastructure/network-private"

  enable_nat_gateway = !local.is_egress_zero  # false for zero-egress
  zero_egress        = local.is_egress_zero   # true for zero-egress
  flow_log_s3_bucket   = var.flow_log_s3_bucket
  # ... other variables
}
```

module "iam" {
  source = "../../../../modules/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = "${var.cluster_name}-"
  operator_role_prefix = "${var.cluster_name}-"
  tags                 = var.tags
}

module "cluster" {
  source = "../../../../modules/cluster"

  cluster_name        = var.cluster_name
  region              = var.region
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  installer_role_arn  = module.iam.installer_role_arn
  support_role_arn    = module.iam.support_role_arn
  worker_role_arn     = module.iam.worker_role_arn
  operator_role_arns = module.iam.operator_role_arns
  oidc_config_id      = module.iam.oidc_config_id

  # Production hardening - maximum security
  private            = true          # PrivateLink API only
  etcd_encryption    = true          # Encrypt etcd data
  fips               = var.fips      # FIPS 140-2 compliance if required
  kms_key_arn        = var.kms_key_arn  # Customer-managed KMS for encryption
  multi_az           = true          # Always multi-AZ for production
  availability_zones = var.availability_zones

  # Pin to stable version for production
  version            = var.openshift_version

  # Custom network CIDRs (if needed to avoid conflicts)
  service_cidr      = var.service_cidr
  pod_cidr          = var.pod_cidr
  host_prefix       = var.host_prefix

  # Production machine pools - larger instances, proper scaling
  machine_pools = [
    {
      name                = "worker"
      instance_type       = var.instance_type
      min_replicas        = 3  # Minimum for HA
      max_replicas        = var.max_replicas
      multi_az            = true
      autoscaling_enabled = true
    }
  ]

  tags = merge(var.tags, {
    Environment = "production"
    Security    = "high"
    Compliance  = var.fips ? "fips-140-2" : "standard"
  })
}
```

**State Management**: Backend configuration is provided via `-backend-config` flags or environment variables. See infrastructure state management section above for details.

**Terraform Variables** (`clusters/egress-zero/terraform.tfvars`):

```hcl
network_type = "private"
zero_egress  = true  # Enables zero-egress mode (matches ROSA API property name)
region       = "us-east-1"
vpc_cidr     = "10.30.0.0/16"
multi_az     = true

# Production instance sizing
instance_type = "m5.xlarge"
max_replicas  = 12

# Encryption
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/abc123..."

# Version pinning for production
openshift_version = "4.15.0"

# Network CIDRs (customize if needed)
service_cidr = "172.30.0.0/16"
pod_cidr     = "10.128.0.0/14"
host_prefix  = 23

# Compliance
fips = false  # Set to true for FIPS 140-2 compliance

# Audit logging
flow_log_s3_bucket = "my-org-vpc-flow-logs"

tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "rosa-hcp"
}
```

**Additional Production Hardening**:

The egress-zero example includes:
- ✅ **PrivateLink API** - No public API endpoints
- ✅ **ETCD Encryption** - Encrypted etcd data at rest
- ✅ **KMS Encryption** - Customer-managed KMS keys
- ✅ **Multi-AZ** - High availability across availability zones
- ✅ **Zero Internet Egress** - All traffic via VPC endpoints
- ✅ **VPC Flow Logs** - Audit logging to S3
- ✅ **Version Pinning** - Stable OpenShift version
- ✅ **FIPS Support** - Optional FIPS 140-2 compliance
- ✅ **Production Tagging** - Comprehensive resource tagging
- ✅ **Proper Scaling** - Production-appropriate instance sizes and scaling

---

### 5.4 Common Variables (`01-variables.tf`)

All examples share common variable definitions:

```hcl
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Production-specific variables (egress-zero only)
variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "openshift_version" {
  description = "OpenShift version to pin"
  type        = string
  default     = null
}

variable "fips" {
  description = "Enable FIPS 140-2 compliance"
  type        = bool
  default     = false
}

# ... other variables
```

**Note**: Secrets (pull secrets, client IDs) should NOT be in `terraform.tfvars`. See Variable Strategy below.

### 5.5 Outputs (`outputs.tf`)

Expose cluster information:

```hcl
output "cluster_id" {
  description = "ROSA HCP Cluster ID"
  value       = module.cluster.cluster_id
}

output "api_url" {
  description = "Cluster API URL"
  value       = module.cluster.api_url
}

output "console_url" {
  description = "Cluster Console URL"
  value       = module.cluster.console_url
}

# ... other outputs
```

---

## Variable Strategy

### Global Defaults
Defined in the `variables.tf` of each module (e.g., `default_instance_type = "m5.xlarge"`).

### Cluster Specifics
Saved in the `terraform.tfvars` file inside the cluster directory (`clusters/production/us-east-1/cluster-01/terraform.tfvars`).

**This file IS committed to Git** and contains:
- `cluster_name`
- `vpc_cidr`
- `region`
- `network_type`
- Instance sizing
- Other non-sensitive configuration

### Secrets Management

**DO NOT** put secrets in `terraform.tfvars`.

**Option A (Easy)**: Pass as Environment Variables during `terraform apply`:
```bash
export TF_VAR_pull_secret='{"auths":{...}}'
export TF_VAR_oidc_client_secret='secret-value'
terraform apply
```

**Option B (Advanced)**: Use AWS Secrets Manager:
```hcl
data "aws_secretsmanager_secret_version" "pull_secret" {
  secret_id = "rosa/pull-secret"
}

locals {
  pull_secret = jsondecode(data.aws_secretsmanager_secret_version.pull_secret.secret_string)
}
```

---

## Implementation Checklist

| Phase | Step | Action | Tool |
|-------|------|--------|------|
| 1 | Prepare | Fork/Clone `terraform-redhat/terraform-rhcs-rosa-hcp` as reference | Git |
| 2 | Repo 1 | Build `network-public` module. Use Regional NAT Gateway (default) with zonal option. Ensure tags are correct | Terraform |
| 3 | Repo 1 | Build `network-private` module with zero-egress support. Ensure VPC endpoints are configured and zero egress controls are available via `zero_egress` | Terraform |
| 4 | Repo 1 | ~~Build `network-egress-zero` module~~ **CONSOLIDATED**: Egress-zero functionality is now part of `network-private` module | N/A |
| 5 | Repo 1 | Build `iam` module. Use rhcs provider for account & operator roles | Terraform |
| 6 | Repo 1 | Build `cluster` module. Reference hardened specs (Private, Encrypted) | Terraform |
| 7 | Repo 1 | Create example clusters in `clusters/`: public (dev), egress-zero (prod-ready) | Terraform |
| 8 | Verify | Run end-to-end `terraform apply` for each example. Verify configurations and connectivity | CLI |
| 9 | Future | Build Repository 2 for Bootstrap, GitOps, IDP, Logging, Monitoring | Terraform/GitOps |

---

## References & Best Practices

### Terraform Modules
- **terraform-redhat/rosa-hcp/rhcs**: Official Terraform module for ROSA HCP
  - Submodules: `account-iam-resources`, `rosa-cluster-hcp`
  - Registry: https://registry.terraform.io/modules/terraform-redhat/rosa-hcp/rhcs/latest

### Documentation
- **ROSA HCP Installation**: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html-single/install_clusters/index
- **ROSA HCP Getting Started**: https://docs.aws.amazon.com/rosa/latest/userguide/getting-started-hcp.html
- **RHCS Provider**: https://search.opentofu.org/provider/terraform-redhat/rhcs/v1.7.2

### Best Practices
1. **State Isolation**: Each cluster directory has its own S3 state path
2. **Tagging**: Always apply ROSA-required tags to subnets
3. **Network Selection**: Choose network module based on security requirements:
   - **Public**: Development/Staging, needs internet access (uses Regional NAT Gateway by default)
   - **Private**: Production, PrivateLink API, VPC endpoints for AWS services
   - **Egress Zero**: High-security, no internet egress, all via VPC endpoints
4. **IAM Roles**: Use prefixes to avoid conflicts across clusters
5. **Secrets**: Never commit secrets to Git; use environment variables or Secrets Manager

### GitOps Integration

GitOps bootstrap is integrated into the cluster module. After cluster deployment, run `make cluster.<name>.bootstrap` to deploy the OpenShift GitOps operator. Additional Day 2 operations are deployed via Helm charts in the cluster-config Git repository:

- **cert-manager**: Deployed via `app-of-apps-infrastructure` chart
- **external-dns**: Deployed via `app-of-apps-infrastructure` chart
- **Ingress Controllers**: Deployed via Helm charts (see `docs/improvements/ingress.md`)
- **Identity Providers**: Configured via GitOps (cluster-config repository)
- **Logging**:
  - **Control Plane Log Forwarding** (new): ROSA managed log forwarder for control plane logs (api, authentication, controller manager, scheduler) to CloudWatch/S3 - IAM roles and resources created in Terraform. Note: 'Other' group is not supported by ROSA CLI despite documentation.
  - **Application Logging**: CloudWatch logging IAM roles created in Terraform, ClusterLogForwarder deployed via GitOps
  - **Legacy Audit Logging** (deprecated): CloudWatch audit logging IAM roles created in Terraform, configured via ROSA CLI
- **Monitoring**: Deployed via GitOps (cluster-config repository)

**Pattern**: Terraform creates AWS infrastructure (VPC, IAM roles, Route53 zones), GitOps deploys Kubernetes resources and cluster configuration.

---

## Architecture Decisions

### Why Directory-Per-Cluster?
- **State Isolation**: Each cluster has independent Terraform state
- **Parallel Deployments**: Multiple clusters can be managed without conflicts
- **Clear Ownership**: Easy to identify which cluster is which
- **Selective Updates**: Update one cluster without affecting others

### Why Multiple Network Modules?
Different security postures require different network topologies:
- **Standard**: Simplest, good for dev/test
- **Private**: Production-grade, PrivateLink API, no public internet
- **Egress Zero**: Highest security, no internet egress at all

### Why Separate IAM Module?
- IAM resources can be shared or reused across clusters
- Clear separation of concerns
- Easier to audit permissions

### Why Module-Based Approach?
- **Reusability**: Same modules for multiple clusters
- **Consistency**: Ensures all clusters follow same patterns
- **Maintainability**: Update modules, all clusters benefit
- **Testing**: Test modules independently before cluster deployment

### Why a Thin Wrapper Cluster Module vs Direct Provider Call?
The cluster module is a **thin wrapper** that provides organizational defaults while passing through all provider variables. This approach:

**Benefits**:
- **Organizational Standards**: Enforces security hardening (private=true, etcd_encryption=true) by default
- **Consistency**: All clusters follow organizational patterns automatically
- **Flexibility**: Can override any default - module doesn't restrict provider capabilities
- **Future-Proof**: Easy to add org-specific resources (monitoring, integrations) without changing cluster code
- **Documentation**: Module serves as living documentation of organizational standards

**Trade-offs**:
- **Abstraction Layer**: Adds one level of indirection (minimal overhead)
- **Maintenance**: Must keep module in sync with provider updates (but pass-through minimizes this)

**Alternative**: Call `rhcs_cluster_rosa_hcp` directly in cluster directories for one-off or experimental clusters. Use the module for production clusters to ensure consistency.
