# Customer Intake Form

Information required from the customer before provisioning a ROSA HCP cluster. Items marked **Required** must be provided.

> **Scope:** Covers zero-egress and standard deployments. `zero_egress` and `private` are cluster-level decisions documented separately in [Network Requirements](byo/network.md).

## 1. AWS account

| # | Detail | Example | Required | Notes |
|---|--------|---------|----------|-------|
| 1.1 | **AWS Account ID** | `123456789012` | **Yes** | Account where cluster deploys |
| 1.2 | AWS Billing Account ID | `123456789012` | If different from 1.1 | Payer account for Marketplace |
| 1.3 | **AWS Region** | `ap-southeast-2` | **Yes** | Target region |

Customer configures AWS credentials on the operator machine — not collected in this form.

## 2. Red Hat account and ROSA

| # | Detail | Example | Required | Notes |
|---|--------|---------|----------|-------|
| 2.1 | **OCM offline token or service account** | — | **Yes** | For Terraform RHCS provider |
| 2.2 | **Marketplace subscription** | Completed | **Yes** | [ROSA HCP listing](https://aws.amazon.com/marketplace/pp/prodview-juiwfhpeizxro) |
| 2.3 | **AWS–Red Hat account linking** | Completed | **Yes** | AWS ROSA console → Continue to Red Hat |

See [Account Prerequisites](account.md) for the six-step linking process.

## 3. Cluster configuration

| # | Detail | Example | Default | Required |
|---|--------|---------|---------|----------|
| 3.1 | **Cluster name** | `prod-rosa-01` | — | **Yes** (max 15 chars, lowercase) |
| 3.2 | **Multi-AZ** | `true` | `false` | **Yes** |
| 3.3 | OpenShift version | `4.20.12` | Latest stable | No |
| 3.4 | FIPS | `false` | `false` | No |
| 3.5 | Termination protection | `false` | `false` | No |
| 3.6 | Zero egress | `true` / `false` | `false` | **Yes** |
| 3.7 | Private API (PrivateLink) | `true` / `false` | varies | **Yes** |

## 4. Network configuration

### Option A — Terraform creates VPC (`network_type = "private"` or `"public"`)

| # | Detail | Example | Default | Required |
|---|--------|---------|---------|----------|
| 4A.1 | **VPC CIDR** | `10.0.0.0/23` | — | **Yes** |
| 4A.2 | Service CIDR | `172.30.0.0/16` | `172.30.0.0/16` | No |
| 4A.3 | Pod CIDR | `10.128.0.0/14` | `10.128.0.0/14` | No |
| 4A.4 | Host prefix | `23` | `23` | No |

### Option B — Customer provides VPC (`network_type = "existing"`)

| # | Detail | Example | Required |
|---|--------|---------|----------|
| 4B.1 | **VPC ID** | `vpc-0abc123` | **Yes** |
| 4B.2 | **Private subnet IDs** | 1 or 3 subnets | **Yes** |
| 4B.3 | Public subnet IDs | — | If public API / external LBs |
| 4B.4–4B.6 | Service/pod CIDR, host prefix | defaults | No |

BYO prerequisites: [Network Requirements](byo/network.md)

## 5. Worker nodes

| # | Detail | Example | Default |
|---|--------|---------|---------|
| 5.1 | Instance type | `m5.xlarge` | `m5.xlarge` |
| 5.2 | Min replicas per AZ | `1` | module default |
| 5.3 | Max replicas per AZ | `2` | module default |
| 5.4 | Additional machine pools | — | `[]` |

## 6. Encryption (optional)

| # | Detail | Default |
|---|--------|---------|
| 6.1 | Customer KMS key ARN | Auto-created by IAM module |
| 6.2 | etcd encryption | `false` |

## 7. Logging (optional)

| # | Detail | Default |
|---|--------|---------|
| 7.1 | Control plane log forwarding | `false` |
| 7.2 | Forward to S3 | `false` |
| 7.3 | Forward to CloudWatch | `false` (requires CW VPC endpoints for zero egress) |

## 8. Tags (recommended)

```hcl
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "rosa-hcp"
}
```

## 9. Advanced options

| # | Detail | Default | When to change |
|---|--------|---------|----------------|
| 9.1 | Persistent DNS domain | `false` | Survive cluster recreation |
| 9.2 | GitOps bootstrap | `false` | Day 1 Argo CD |
| 9.3 | Client VPN | `false` | **Required** for private/zero-egress operator access |
| 9.4 | Cert-manager IAM | `false` | AWS Private CA integration |

## Minimum required (fastest path)

| # | Detail | Terraform variable |
|---|--------|-------------------|
| 1 | AWS account + region | credentials / `region` |
| 2 | RHCS authentication | `RHCS_*` env vars |
| 3 | Marketplace + linking | — (manual) |
| 4 | Cluster name | `cluster_name` |
| 5 | VPC CIDR **or** VPC + subnet IDs | `vpc_cidr` / `existing_*` |
| 6 | Multi-AZ | `multi_az` |
| 7 | Zero egress / private API | `zero_egress`, `private` |

## Related

- [Choose Your Path](index.md)
- [Handoff Checklist](byo/handoff-checklist.md)
