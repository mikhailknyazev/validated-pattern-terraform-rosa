# BYO Network Requirements

Specifications for VPCs pre-provisioned before Terraform runs with `network_type = "existing"`.

## ROSA HCP note on VPC endpoints

For **ROSA HCP**, EC2 and KMS operations are performed by the Red Hat-managed control plane. **EC2 and KMS VPC endpoints in the customer VPC are not required** for cluster installation.

## Required for all BYO deployments

| Requirement | Details |
|-------------|---------|
| VPC DNS | `enableDnsSupport` and `enableDnsHostnames` = `true` |
| Private subnets | Tagged `kubernetes.io/role/internal-elb = "1"` |
| Subnet count | 1 for single-AZ (`multi_az = false`); 3 for multi-AZ (one per AZ) |
| Machine CIDR | `vpc_cidr` in tfvars must match VPC CIDR used at cluster creation |
| CIDR sizing | Minimum `/25` per subnet; recommended `/23` VPC or larger for production |

## Requirement matrix by posture

| Requirement | Standard (`zero_egress=false`) | Zero egress (`zero_egress=true`) |
|-------------|-------------------------------|----------------------------------|
| Private subnets | 1 or 3 (match `multi_az`) | 1 or 3 |
| Public subnets | Required if `private = false` (external LBs); tag `kubernetes.io/role/elb = "1"` | Usually none |
| NAT on private routes | **Required** (unless all egress via endpoints) | **Must not exist** |
| IGW route on private subnets | Must not exist | Must not exist |
| S3 gateway endpoint | Recommended | **Required** |
| STS interface endpoint | Recommended with NAT | **Required** |
| ECR API interface endpoint | Recommended with NAT | **Required** |
| ECR DKR interface endpoint | Recommended with NAT | **Required** |
| CloudWatch logs/monitoring endpoints | If `control_plane_log_cloudwatch_enabled = true` | Same |
| Interface endpoint PrivateDnsEnabled | `true` | `true` |
| Endpoint security group | HTTPS 443 inbound from VPC CIDR | Same |
| Worker ECR policy | Optional (NAT pulls from internet) | **Required** — Terraform IAM module attaches `AmazonEC2ContainerRegistryReadOnly` when `zero_egress = true` |

## VPC endpoints detail

| Service | Type | Service name pattern |
|---------|------|----------------------|
| S3 | Gateway | `com.amazonaws.<region>.s3` |
| STS | Interface | `com.amazonaws.<region>.sts` |
| ECR API | Interface | `com.amazonaws.<region>.ecr.api` |
| ECR DKR | Interface | `com.amazonaws.<region>.ecr.dkr` |
| CloudWatch Logs | Interface (optional) | `com.amazonaws.<region>.logs` |
| CloudWatch Monitoring | Interface (optional) | `com.amazonaws.<region>.monitoring` |

## IP capacity (zero egress / private subnets)

Per `/25` private subnet (128 IPs):

| Consumer | IPs |
|----------|-----|
| AWS reserved | 5 |
| Interface VPC endpoints (STS, ECR API, ECR DKR) | 3 per AZ |
| ROSA PrivateLink API ENI | 1 |
| NLB for ingress | ~1–8 under load |
| Worker nodes | Remainder (~100+ for initial 3-node cluster) |

See [Red Hat subnet guidance](https://cloud.redhat.com/experts/rosa/ip-addressing-and-subnets/) for sizing.

## Validation

```bash
./scripts/validate/byo-network.sh --vpc-id vpc-xxx --region us-east-1 --zero-egress
make cluster.my-byo.validate-network
```

## Zero egress overlay

When `zero_egress = true` on a BYO VPC:

1. Remove NAT Gateway routes from private subnet route tables
2. Ensure all four required endpoints are `available`
3. Set `private = true` for PrivateLink API
4. Enable Client VPN for operator access (`enable_client_vpn = true`)
5. Plan GitOps mirroring — [Egress-Zero GitOps](../../guides/egress-zero-gitops.md)

Example: `clusters/byo-vpc-egress-zero/terraform.tfvars`

## Related

- [Handoff Checklist](handoff-checklist.md)
- [Bring Your Own — Overview](index.md)
