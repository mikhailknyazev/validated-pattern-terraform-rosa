# Cluster Configurations

This directory contains cluster-specific Terraform configurations for ROSA HCP clusters. Each directory under `/clusters/` represents a single cluster. The `public` and `egress-zero` directories are reference examples.

## RHCS API Authentication

Set RHCS credentials **before** using any `make` or Terraform commands. This project does not manage credentials.

- **Option 1 (Token):** `export RHCS_TOKEN="your-offline-token"` — Get token from https://console.redhat.com/openshift/token/rosa/show
- **Option 2 (Service account):** `export RHCS_CLIENT_ID="..."` and `export RHCS_CLIENT_SECRET="..."` — Create in Red Hat Hybrid Cloud Console → User Management → Service accounts

See [README.md](../README.md#rhcs-api-authentication) for full documentation.

## Directory Structure

```
clusters/
├── public/                               # Example public cluster
│   └── terraform.tfvars                  # Cluster-specific variables
├── egress-zero/                          # Example egress-zero cluster
│   └── terraform.tfvars                  # Cluster-specific variables
├── egress-zero2/                         # Additional egress-zero cluster (example)
└── us-east-1-production/                 # Additional cluster (example)
```

Each directory under `/clusters/` represents a single cluster. The `public` and `egress-zero` directories are reference examples. You can create additional clusters by creating new directories at the same level.

## Cluster Types

### Public Clusters (`clusters/public/`)

Public clusters use a public API endpoint and have internet egress via NAT Gateway. Suitable for development and non-production environments.

**Characteristics:**
- Public API endpoint (accessible from internet)
- Internet egress via NAT Gateway
- Public and private subnets
- Relaxed security settings (no encryption, etc.)
- Suitable for development/testing

**Usage:**
```bash
# Initialize and apply the example public cluster
make cluster.public.init
make cluster.public.apply

# Or use a different cluster directory (e.g., my-public-cluster)
make cluster.my-public-cluster.init
make cluster.my-public-cluster.apply
```

### Egress-Zero Clusters (`clusters/egress-zero/`)

Egress-zero clusters have strict egress control with zero internet egress. All external access must go through VPC endpoints. Suitable for high-security production environments.

**Characteristics:**
- Private API endpoint (PrivateLink only)
- Zero internet egress (strict security groups)
- Private subnets only (no public subnets)
- VPC endpoints for AWS services
- Optional VPC Flow Logs for audit logging
- Production hardening (encryption, FIPS, etc.)
- Requires VPN tunnel (sshuttle) for API access

**Usage:**
```bash
# Initialize and apply the example egress-zero cluster
make cluster.egress-zero.init
make cluster.egress-zero.apply

# Or use a different cluster directory (e.g., egress-zero2, us-east-1-production)
make cluster.egress-zero2.init
make cluster.egress-zero2.apply
make cluster.us-east-1-production.init
make cluster.us-east-1-production.apply
```

## Creating a New Cluster

1. **Choose a cluster type**: `public` or `egress-zero`

2. **Create cluster directory**:
   ```bash
   mkdir -p clusters/<cluster-name>
   ```
   Example: `mkdir -p clusters/egress-zero2` or `mkdir -p clusters/us-east-1-production`

3. **Copy example configuration**:
   ```bash
   cp clusters/<type>/terraform.tfvars clusters/<cluster-name>/
   ```
   Example: `cp clusters/egress-zero/terraform.tfvars clusters/egress-zero2/`

4. **Update `terraform.tfvars`**:
   - Set `cluster_name` (uncomment and set value)
   - Set `network_type` to `public` or `private`
   - For egress-zero clusters: set `zero_egress = true` (with `network_type = "private"`)
   - Set `region`, `vpc_cidr`, and other variables
   - Configure production variables if needed (KMS, version pinning, etc.)

5. **Initialize and apply**:
   ```bash
   make cluster.<cluster-name>.init
   make cluster.<cluster-name>.apply
   ```
   Example: `make cluster.egress-zero2.init`

## Key Differences Between Cluster Types

| Feature | Public | Private | Egress-Zero |
|---------|--------|---------|-------------|
| network_type | `public` | `private` | `private` |
| zero_egress | `false` | `false` | `true` |
| API Endpoint | Public | Private (PrivateLink) | Private (PrivateLink) |
| Internet Egress | Yes (NAT Gateway) | Yes (NAT Gateway) | No (VPC endpoints only) |
| Subnets | Public + Private | Private only | Private only |
| Security Groups | Standard | Standard | Strict egress control |
| VPC Flow Logs | Optional | Optional | Recommended |
| Encryption | Optional | Optional | Recommended (KMS) |
| FIPS | Optional | Optional | Optional |
| VPN Tunnel Required | No | No | Yes (for API access) |
| Use Case | Development/Testing | Production (private API) | Production (high security) |

## Configuration Files

### `terraform.tfvars`

Contains cluster-specific variables:
- `cluster_name`: Name of the cluster (must be set)
- `network_type`: Network topology type (`public` or `private`)
- `zero_egress`: Enable zero egress mode (no internet egress, only VPC endpoints). Set to `true` with `network_type="private"` for egress-zero clusters. Matches ROSA API property name.
- `region`: AWS region
- `vpc_cidr`: VPC CIDR block
- `multi_az`: Multi-AZ deployment (true/false)
- `instance_type`: EC2 instance type for worker nodes
- Production variables (KMS, version pinning, etc.) - typically used with egress-zero

### Backend Configuration

Backend configuration is now handled via environment variables or `-backend-config` flags:

**Local Development** (default):
- Backend path is automatically set to `clusters/<name>/infrastructure.tfstate`
- No configuration files needed

**CI/CD with Remote Backend** (S3, Terraform Cloud, etc.):
- Set environment variables before running `terraform init`:
  ```bash
  export TF_BACKEND_CONFIG_BUCKET="my-terraform-state"
  export TF_BACKEND_CONFIG_REGION="us-east-1"
  export TF_BACKEND_CONFIG_DYNAMODB_TABLE="terraform-locks"
  ```
- Or use `-backend-config` flags directly in your pipeline

## Makefile Usage

The unified Makefile supports both cluster types with a consistent interface:

```bash
# Initialize cluster
make cluster.<cluster-name>.init

# Plan changes
make cluster.<cluster-name>.plan

# Apply changes
make cluster.<cluster-name>.apply

# Destroy cluster
make cluster.<cluster-name>.destroy

# Show endpoints and credentials
make cluster.<cluster-name>.show-endpoints
make cluster.<cluster-name>.show-credentials

# Login to cluster
make cluster.<cluster-name>.login

# Tunnel management (egress-zero clusters only)
make cluster.<cluster-name>.tunnel-start
make cluster.<cluster-name>.tunnel-stop
```

## Script-Based Usage (CI/CD Friendly)

For CI/CD pipelines, you can call scripts directly without Make:

```bash
# Initialize infrastructure
./scripts/cluster/init-infrastructure.sh <cluster-name>

# Plan infrastructure
./scripts/cluster/plan-infrastructure.sh <cluster-name>

# Apply infrastructure
./scripts/cluster/apply-infrastructure.sh <cluster-name>

# All operations are handled through infrastructure scripts
```

See [scripts/README.md](../scripts/README.md) for complete script documentation and CI/CD examples.

## Egress-Zero Specific Notes

### VPN Tunnel Requirement

Egress-zero clusters use a private API endpoint (PrivateLink), so you need a VPN tunnel to access the API. The Makefile automatically starts the tunnel when needed for cluster operations.

**Manual tunnel management:**
```bash
# Start tunnel
make cluster.<cluster-name>.tunnel-start

# Check tunnel status
make cluster.<cluster-name>.tunnel-status

# Stop tunnel
make cluster.<cluster-name>.tunnel-stop
```

### Bastion Host

The bastion host is required for VPN tunnel access. Ensure `enable_bastion = true` in your `terraform.tfvars` for egress-zero clusters.

**Connect to bastion:**
```bash
make cluster.<cluster-name>.bastion-connect
```


## Troubleshooting

### Cluster Not Found

If you get "Cluster directory does not exist":
- Check that the cluster directory exists: `clusters/<cluster-name>/`
- Verify the cluster name in the command matches the directory name
- Example: `make cluster.egress-zero2.init` uses `clusters/egress-zero2/`
- List available clusters: `ls clusters/`

### Tunnel Issues (Egress-Zero)

If tunnel fails to start:
- Ensure bastion is deployed: `enable_bastion = true`
- Check bastion status: `make cluster.egress-zero.bastion-connect`
- Verify SSM VPC endpoints are configured
- Check AWS credentials and permissions

### Backend Configuration Errors

If backend config errors occur:
- For local development: Ensure Terraform state directory exists (will be created automatically)
- For CI/CD: Verify `TF_BACKEND_CONFIG_*` environment variables are set correctly
- Check that backend configuration matches your Terraform backend type (local, S3, etc.)

### Infrastructure Outputs Not Available

If you need to access infrastructure outputs:
- Verify infrastructure outputs are available: `cd terraform && terraform output`
- Use `terraform output` to view all available outputs

## See Also

- [Main README](../README.md) - Project overview and architecture
- [PLAN.md](../PLAN.md) - Implementation plan and architecture decisions
- [Network Module Documentation](../modules/infrastructure/network-private/README.md) - Network module details
