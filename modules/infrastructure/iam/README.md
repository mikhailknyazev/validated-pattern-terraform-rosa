# IAM Module

This module creates the IAM roles, OIDC configuration, and KMS keys required for ROSA HCP clusters.

## Features

- Managed OIDC configuration
- AWS IAM OIDC provider
- Account roles (Installer, Support, Worker) using terraform-redhat/rosa-hcp/rhcs module
- Operator roles for ROSA HCP:
  - Ingress Operator
  - Control Plane Operator
  - CSI Driver Operator
  - Image Registry Operator
  - Network Operator
  - Node Pool Operator
- **KMS Keys** (EBS, EFS, ETCD encryption)
- **Storage IAM Resources** (KMS CSI policy, EBS CSI attachment, EFS CSI role/policy)
- **Control Plane Log Forwarding IAM** (new ROSA managed log forwarder - for control plane logs to CloudWatch/S3)
- **CloudWatch Audit Logging IAM** (legacy, deprecated - for SIEM audit log forwarding)
- **CloudWatch Logging IAM** (for OpenShift Logging Operator)
- **Cert Manager IAM** (for AWS Private CA integration)
- **Secrets Manager IAM** (for ArgoCD Vault Plugin)
- Role prefixing for uniqueness across clusters

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  cluster_name         = "my-rosa-cluster"
  account_role_prefix  = "my-rosa-cluster-"  # Optional, defaults to cluster_name
  operator_role_prefix = "my-rosa-cluster-"  # Optional, defaults to cluster_name

  # KMS configuration
  enable_storage       = true
  etcd_encryption      = true
  kms_key_deletion_window = 10
  enable_efs           = true

  # IAM feature flags
  enable_control_plane_log_forwarding        = true  # New ROSA managed log forwarder
  control_plane_log_cloudwatch_enabled       = false  # Default: S3 is more cost-effective
  control_plane_log_cloudwatch_log_group_name = null  # Optional: uses default pattern if null
  enable_audit_logging        = false  # Legacy, deprecated - use control_plane_log_forwarding instead
  enable_cloudwatch_logging   = true
  enable_cert_manager_iam     = true
  enable_secrets_manager_iam  = true
  aws_private_ca_arn         = "arn:aws:acm-pca:region:account:certificate-authority/..."
  additional_secrets          = ["my-secret-1", "my-secret-2"]

  # Cluster credentials secret ARN (from cluster module, for Secrets Manager IAM)
  cluster_credentials_secret_arn = module.cluster.cluster_credentials_secret_arn

  tags = {
    Environment = "production"
    Project     = "rosa-hcp"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | ~> 5.0 |
| rhcs | ~> 1.7 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the ROSA HCP cluster | `string` | n/a | yes |
| account_role_prefix | Prefix for account roles to ensure uniqueness. Defaults to cluster_name | `string` | `null` | no |
| operator_role_prefix | Prefix for operator roles to ensure uniqueness. Defaults to cluster_name | `string` | `null` | no |
| zero_egress | Enable zero egress mode. When true, attaches AmazonEC2ContainerRegistryReadOnly policy to worker role (required for egress-zero clusters) | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| persists_through_sleep | Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active | `bool` | `true` | no |
| persists_through_sleep_iam | Override persists_through_sleep for IAM resources. If null, uses persists_through_sleep value | `bool` | `null` | no |
| enable_storage | Enable storage resources (KMS keys) | `bool` | `false` | no |
| enable_efs | Enable EFS file system (required for EFS CSI driver IAM role) | `bool` | `false` | no |
| etcd_encryption | Enable etcd encryption (requires etcd KMS key) | `bool` | `false` | no |
| kms_key_deletion_window | KMS key deletion window in days | `number` | `10` | no |
| enable_control_plane_log_forwarding | Enable control plane log forwarding IAM resources (new ROSA managed log forwarder). Replaces legacy audit logging | `bool` | `false` | no |
| control_plane_log_cloudwatch_enabled | Enable CloudWatch destination for control plane log forwarding. Default disabled for cost; S3 is more cost-effective | `bool` | `false` | no |
| control_plane_log_cloudwatch_log_group_name | CloudWatch log group name. If null, uses default pattern: ${cluster_name}-control-plane-logs. Must match name used in cluster module | `string` | `null` | no |
| enable_audit_logging | [DEPRECATED] Enable CloudWatch audit logging IAM resources (legacy implementation). Use enable_control_plane_log_forwarding instead | `bool` | `false` | no |
| enable_cloudwatch_logging | Enable CloudWatch logging IAM resources | `bool` | `false` | no |
| enable_cert_manager_iam | Enable cert-manager IAM resources | `bool` | `false` | no |
| enable_secrets_manager_iam | Enable Secrets Manager IAM resources | `bool` | `false` | no |
| aws_private_ca_arn | AWS Private CA ARN for cert-manager (optional) | `string` | `null` | no |
| additional_secrets | Additional Secrets Manager secret names for IAM policy (optional) | `list(string)` | `null` | no |
| cluster_credentials_secret_arn | ARN of cluster credentials secret (for Secrets Manager IAM policy) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| oidc_config_id | ID of the OIDC configuration |
| oidc_endpoint_url | OIDC endpoint URL |
| oidc_provider_arn | ARN of the OIDC provider |
| installer_role_arn | ARN of the Installer account role |
| support_role_arn | ARN of the Support account role |
| worker_role_arn | ARN of the Worker account role |
| operator_role_arns | Map of operator role names to ARNs |
| ebs_kms_key_id | ID of the EBS KMS key (null if enable_storage is false) |
| ebs_kms_key_arn | ARN of the EBS KMS key (null if enable_storage is false) |
| efs_kms_key_id | ID of the EFS KMS key (null if enable_storage is false) |
| efs_kms_key_arn | ARN of the EFS KMS key (null if enable_storage is false) |
| etcd_kms_key_id | ID of the ETCD KMS key (null if enable_storage is false or etcd_encryption is false) |
| etcd_kms_key_arn | ARN of the ETCD KMS key (null if enable_storage is false or etcd_encryption is false) |
| control_plane_log_forwarding_role_arn | ARN of the control plane log forwarding IAM role (null if enable_control_plane_log_forwarding is false) |
| cloudwatch_audit_logging_role_arn | [DEPRECATED] ARN of the CloudWatch audit logging IAM role (null if enable_audit_logging is false). Use control_plane_log_forwarding_role_arn instead |
| cloudwatch_logging_role_arn | ARN of the CloudWatch logging IAM role (null if enable_cloudwatch_logging is false) |
| secrets_manager_role_arn | ARN of the Secrets Manager IAM role (null if enable_secrets_manager_iam is false) |
| cert_manager_role_arn | ARN of the cert-manager IAM role (null if enable_cert_manager_iam is false) |

## Account Roles

The module uses the `terraform-redhat/rosa-hcp/rhcs` module to create account roles:

- **Installer Role**: Used during cluster installation
- **Support Role**: Used by Red Hat support
- **Worker Role**: Used by worker nodes

These roles are account-wide but prefixed to ensure uniqueness across clusters.

## Operator Roles

The module creates the following operator roles required for ROSA HCP:

- **ingress**: Ingress Operator for load balancers
- **control-plane**: Control Plane Operator
- **csi-driver**: CSI Driver Operator for storage
- **image-registry**: Image Registry Operator
- **network**: Network Operator
- **node-pool**: Node Pool Operator

All operator roles are linked to the OIDC provider and use least-privilege principles.

## Role Prefixing

By default, roles are prefixed with the cluster name to ensure uniqueness. You can override this with the `account_role_prefix` and `operator_role_prefix` variables.

Example:
- Cluster name: `prod-hcp-01`
- Account role prefix: `prod-hcp-01-` (default)
- Operator role prefix: `prod-hcp-01-` (default)

This ensures multiple clusters can coexist in the same AWS account without role name conflicts.

## KMS Keys

The module creates KMS keys for encryption:

- **EBS KMS Key**: Used for EBS volume encryption (created when `enable_storage = true`)
- **EFS KMS Key**: Used for EFS file system encryption (created when `enable_storage = true`, used by cluster module)
- **ETCD KMS Key**: Used for etcd encryption (created when `enable_storage = true` and `etcd_encryption = true`)

All KMS keys persist through sleep operations (tagged with `persists_through_sleep = "true"`).

## Storage IAM Resources

The module creates IAM resources for CSI drivers:

- **KMS CSI Policy**: Grants KMS access to EBS and EFS CSI drivers
- **EBS CSI Attachment**: Attaches KMS policy to EBS CSI driver operator role (created by operator-roles module)
- **EFS CSI Role**: IAM role for EFS CSI driver with EFS and KMS permissions

## CloudWatch Logging IAM

The module creates IAM roles for CloudWatch logging:

- **Control Plane Log Forwarding** (new): IAM role for ROSA managed log forwarder (`CustomerLogDistribution-RH`). Uses STS assume role with ROSA's central log distribution role. Supports forwarding multiple log groups (api, authentication, controller manager, scheduler) to CloudWatch and/or S3. Note: 'Other' group is not supported by ROSA CLI despite documentation.
- **CloudWatch Audit Logging** (deprecated): IAM role for OpenShift audit log exporter (`openshift-config-managed:cloudwatch-audit-exporter`). Uses OIDC federation. Replaced by control plane log forwarding.
- **CloudWatch Logging**: IAM role for OpenShift Logging Operator (`openshift-logging:logging`). Uses OIDC federation for application logs.

These are separate roles for different use cases (control plane logs vs. application logs).

## Cert Manager IAM

The module creates an IAM role for cert-manager to use AWS Private CA:

- **Cert Manager Role**: IAM role for cert-manager service account (`cert-manager:cert-manager`)
- Grants permissions to issue certificates from AWS Private CA

## Secrets Manager IAM

The module creates an IAM role for ArgoCD Vault Plugin to access AWS Secrets Manager:

- **Secrets Manager Role**: IAM role for ArgoCD Vault Plugin (`openshift-gitops:vplugin`)
- Uses explicit secret ARN lists for maximum security (no wildcards for GetSecretValue)
- Requires `cluster_credentials_secret_arn` from cluster module (set after cluster is created)

## Dependencies

- Requires AWS credentials with permissions to create IAM roles, OIDC providers, and KMS keys
- Requires RHCS provider token or AWS SSO access
- Account roles module requires specific permissions (see terraform-redhat/rosa-hcp documentation)
- **Note**: EFS file system is created in cluster module (depends on cluster security groups), but EFS KMS key is created here