# Scripts Documentation

This directory contains bash scripts for managing ROSA HCP clusters. The scripts are organized by functionality and can be called directly from CI/CD pipelines or via the Makefile wrapper.

## Script Structure

```
scripts/
├── common.sh              # Shared functions (colors, validation, helpers)
├── cluster/               # Cluster management scripts
│   ├── init-infrastructure.sh
│   ├── plan-infrastructure.sh
│   ├── apply-infrastructure.sh
│   ├── destroy-infrastructure.sh
│   ├── cleanup-infrastructure.sh
│   └── bootstrap-gitops.sh
├── tunnel/               # Tunnel management scripts
│   ├── start.sh
│   ├── stop.sh
│   └── status.sh
├── utils/                # Utility scripts
│   ├── get-admin-password.sh
│   ├── get-k8s-token.sh
│   ├── get-infra-outputs.sh
│   ├── check-cluster.sh
│   └── get-network-config.sh
├── info/                 # Information scripts
│   ├── show-endpoints.sh
│   ├── show-credentials.sh
│   └── login.sh
└── verify_cluster.py     # Python script to verify cluster deployment and GitOps
```

## Usage

### Direct Script Usage

Scripts can be called directly from the command line:

```bash
# Initialize infrastructure
./scripts/cluster/init-infrastructure.sh my-cluster

# Plan infrastructure changes
./scripts/cluster/plan-infrastructure.sh my-cluster

# Apply infrastructure
./scripts/cluster/apply-infrastructure.sh my-cluster
```

### Via Makefile

The Makefile provides a convenient wrapper:

```bash
# Initialize infrastructure
make cluster.my-cluster.init-infrastructure

# Plan infrastructure
make cluster.my-cluster.plan-infrastructure

# Apply infrastructure
make cluster.my-cluster.apply-infrastructure
```

## Script Details

### Common Functions (`common.sh`)

Shared functions used across all scripts:

- `error()`, `warn()`, `info()`, `success()` - Colored output functions
- `get_project_root()` - Get repository root directory
- `get_cluster_dir()` - Validate and return cluster directory path
- `get_terraform_dir()` - Get terraform infrastructure directory
- `check_backend_config()` - Check for remote backend config
- `check_required_tools()` - Verify required tools are installed
- `get_tfvar()` - Extract value from terraform.tfvars

### Cluster Management Scripts

#### Infrastructure Scripts

- **`init-infrastructure.sh`**: Initialize infrastructure Terraform backend
- **`plan-infrastructure.sh`**: Plan infrastructure changes
- **`apply-infrastructure.sh`**: Apply infrastructure changes
- **`destroy-infrastructure.sh`**: Destroy infrastructure (with confirmation)
- **`cleanup-infrastructure.sh`**: Sleep infrastructure (destroy with preserved resources, auto-approve, CI/CD friendly)

#### GitOps Bootstrap Script

- **`bootstrap-gitops.sh`**: Bootstrap GitOps operator on ROSA HCP cluster using Helm charts

**Usage:**
```bash
# Via Makefile (recommended)
make cluster.<cluster-name>.bootstrap

# Directly (from terraform/): write values, export env vars, run script
# terraform output -raw gitops_bootstrap_hub_values > clusters/<name>/cluster-bootstrap-values.yaml
# eval $(terraform output -raw gitops_bootstrap_env_exports)
# export BOOTSTRAP_VALUES_FILE=$PWD/clusters/<name>/cluster-bootstrap-values.yaml
$(terraform output -raw gitops_bootstrap_script_path)
```

**Debug mode:**
Set `DEBUG=true` to enable command tracing (`set -x`):
```bash
DEBUG=true make cluster.<cluster-name>.bootstrap
```

**Output:**
- Creates values file at `clusters/<cluster-dir>/cluster-bootstrap-values.yaml` for inspection
- Installs OpenShift GitOps operator via Helm charts
- Configures ArgoCD instances (`cluster-gitops` and `application-gitops`)

### Utility Scripts

- **`get-admin-password.sh`**: Get admin password from AWS Secrets Manager
- **`get-k8s-token.sh`**: Extract Kubernetes token via `oc login` with retry logic
- **`get-infra-outputs.sh`**: Extract infrastructure outputs and export as TF_VAR_* environment variables
- **`check-cluster.sh`**: Validate cluster directory exists
- **`get-network-config.sh`**: Extract network_type and zero_egress from terraform.tfvars

### Tunnel Scripts

- **`start.sh`**: Start sshuttle tunnel (wrapper for existing tunnel-start.sh)
- **`stop.sh`**: Stop sshuttle tunnel (wrapper for existing tunnel-stop.sh)
- **`status.sh`**: Check tunnel status

### Info Scripts

- **`show-endpoints.sh`**: Show cluster API and console URLs
- **`show-credentials.sh`**: Show admin credentials
- **`login.sh`**: Login to cluster via oc CLI

## Environment Variables

### Backend Configuration

For remote S3 backend:

```bash
export TF_BACKEND_CONFIG_BUCKET="my-terraform-state-bucket"
export TF_BACKEND_CONFIG_REGION="us-east-1"
export TF_BACKEND_CONFIG_DYNAMODB_TABLE="terraform-state-lock"  # Optional
```

### CI/CD Variables

- `AUTO_APPROVE=true`: Skip confirmation prompts (used by sleep/cleanup scripts)
- `TF_VAR_k8s_token`: Kubernetes token (if not set, script will obtain via oc login)
- `TF_VAR_admin_password_override`: Override admin password (if secret not available)

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Initialize infrastructure
        run: ./scripts/cluster/init-infrastructure.sh my-cluster

      - name: Plan infrastructure
        run: ./scripts/cluster/plan-infrastructure.sh my-cluster

      - name: Apply infrastructure
        run: ./scripts/cluster/apply-infrastructure.sh my-cluster
```

### GitLab CI Example

```yaml
stages:
  - infrastructure

variables:
  CLUSTER_NAME: my-cluster

infrastructure:
  stage: infrastructure
  script:
    - ./scripts/cluster/init-infrastructure.sh $CLUSTER_NAME
    - ./scripts/cluster/plan-infrastructure.sh $CLUSTER_NAME
    - ./scripts/cluster/apply-infrastructure.sh $CLUSTER_NAME
```

## Destroy vs Sleep

- **`destroy-*`**: Shows warnings, prompts for confirmation (interactive). For permanent cluster removal.
- **`cleanup-*`** (used by `make sleep`): Same as destroy but uses `-auto-approve` flag (non-interactive). Designed for temporarily shutting down clusters while preserving resources.

**Sleep** preserves:
- DNS domain (if `enable_persistent_dns_domain=true`)
- Admin password in AWS Secrets Manager
- IAM roles and OIDC configuration
- KMS keys and EFS (if not explicitly destroyed)
- GitOps configurations (automatically redeployed when cluster is recreated)

**Note**: Sleep does NOT hibernate the cluster - it destroys cluster resources. The cluster must be recreated using `make apply` to "wake" it. Since GitOps manages all important configurations and applications, they will be automatically redeployed.

For CI/CD pipelines, use `cleanup-*` scripts or set `AUTO_APPROVE=true`:

```bash
AUTO_APPROVE=true ./scripts/cluster/cleanup-infrastructure.sh my-cluster
```

## Error Handling

All scripts use `set -euo pipefail` for strict error handling:
- `-e`: Exit immediately if a command exits with a non-zero status
- `-u`: Treat unset variables as an error
- `-o pipefail`: Return value of a pipeline is the status of the last command to exit with a non-zero status

## Script Standards

All scripts follow these standards:

- Use `set -euo pipefail` for error handling
- Source `common.sh` for shared functions
- Validate inputs
- Provide clear error messages
- Return appropriate exit codes
- Be idempotent where possible

## Dependencies

Scripts require:

- `terraform` - Terraform CLI
- `oc` - OpenShift CLI (for cluster access)
- `aws` - AWS CLI (for Secrets Manager access)
- `jq` - JSON processor (for parsing terraform outputs)
- `sshuttle` - VPN tunnel tool (for egress-zero clusters)

## Troubleshooting

### Script not found

Ensure scripts are executable:

```bash
chmod +x scripts/**/*.sh
```

### Permission denied

Check script permissions and ensure you're running from the repository root:

```bash
ls -la scripts/cluster/init-infrastructure.sh
```

### Backend configuration errors

Ensure backend environment variables are set correctly:

```bash
echo $TF_BACKEND_CONFIG_BUCKET
echo $TF_BACKEND_CONFIG_REGION
```

### Tunnel issues

For egress-zero clusters, ensure:

1. Bastion is deployed (`enable_bastion=true`)
2. SSM agent is online
3. VPC endpoints are configured
4. `sshuttle` is installed

Check tunnel status:

```bash
./scripts/tunnel/status.sh my-cluster
```
