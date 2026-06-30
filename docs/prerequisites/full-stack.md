# Full-Stack Deployment

Layer **1** — one platform team runs the complete Terraform lifecycle from this repository.

## What Terraform creates

When using `network_type = "public"` or `network_type = "private"`, the root module creates:

| Component | Module |
|-----------|--------|
| VPC, subnets, route tables | `network-public` or `network-private` |
| VPC endpoints (private/zero egress) | `network-private` |
| IAM account roles, OIDC, operator roles | `iam` |
| KMS keys (EBS, EFS, etcd) | `iam` |
| ROSA HCP cluster, machine pools | `cluster` |
| Optional Client VPN, bastion, EFS | `client-vpn`, `bastion`, `cluster` |

You provide `clusters/<name>/terraform.tfvars` and RHCS/AWS credentials.

## Before you start

1. Complete [Account Prerequisites](account.md)
2. Run validation:

   ```bash
   make cluster.<name>.validate
   ```

3. Choose a cluster profile (copy an example tfvars)

## Cluster profiles

| Profile | Example | Key variables |
|---------|---------|---------------|
| Public (dev) | `clusters/public/` | `network_type = "public"`, `zero_egress = false` |
| Private + NAT | `clusters/egress-zero/` with `zero_egress = false` | `network_type = "private"`, `private = true` |
| Zero egress | `clusters/egress-zero/` | `network_type = "private"`, `zero_egress = true`, `private = true` |

### Zero egress (full-stack)

Terraform's `network-private` module with `zero_egress = true`:

- Disables NAT Gateway
- Creates required VPC endpoints (S3, STS, ECR API, ECR DKR, CloudWatch)
- Attaches `AmazonEC2ContainerRegistryReadOnly` to worker role via IAM module
- Sets cluster property `zero_egress: true`

**Operator access:** enable Client VPN (`enable_client_vpn = true`) — see `clusters/egress-zero/terraform.tfvars`.

**GitOps:** plan CodeCommit mirroring — [Egress-Zero GitOps](../guides/egress-zero-gitops.md).

## Deployment workflow

```bash
export RHCS_CLIENT_ID="..."      # or RHCS_TOKEN for dev
export RHCS_CLIENT_SECRET="..."

make cluster.<name>.validate
make cluster.<name>.init
make cluster.<name>.plan
make cluster.<name>.apply
make cluster.<name>.bootstrap      # after cluster Ready
```

## Post-network validation (optional)

After apply (or for Terraform-managed VPC before cluster apply), verify VPC configuration:

```bash
make cluster.<name>.validate-network
```

This uses `terraform output vpc_id` when the cluster has been initialized.

## Configuration dimensions

These compose independently in `terraform.tfvars`:

| Dimension | Variables |
|-----------|-----------|
| Network source | `network_type` (`public`, `private`) |
| Egress | `zero_egress` |
| API access | `private` (PrivateLink) |
| Operator VPN | `enable_client_vpn` |
| Compute | `multi_az`, `default_instance_type`, `additional_machine_pools` |
| GitOps | `enable_gitops_bootstrap`, `gitops_git_repo_url` |

See the [Enablement Guide](../deployment/enablement.md) §8 for decision diagrams.

## Next steps

- [Quick Start](../getting-started/quick-start.md)
- [Enablement Guide](../deployment/enablement.md)
- [Cluster Configurations](../deployment/cluster-configurations.md)
