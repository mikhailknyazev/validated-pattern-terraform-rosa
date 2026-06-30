# BYO Handoff Checklist

Use this checklist when the network team hands off to the platform team for `network_type = "existing"`.

## Network team delivers

- [ ] VPC ID
- [ ] Private subnet IDs (ordered consistently for `subnet_index` in machine pools)
- [ ] Public subnet IDs (if `private = false` and external LBs needed)
- [ ] VPC CIDR block (for `vpc_cidr` and `machine_cidr`)
- [ ] AWS region
- [ ] Confirmation: DNS support and hostnames enabled
- [ ] Confirmation: `kubernetes.io/role/internal-elb=1` on all private subnets
- [ ] Confirmation: `kubernetes.io/role/elb=1` on public subnets (if applicable)
- [ ] VPC endpoints verified (see [Network Requirements](network.md))
- [ ] For zero egress: no NAT/IGW routes on private subnets
- [ ] Endpoint security groups allow HTTPS from VPC CIDR

## Platform team configures (`terraform.tfvars`)

```hcl
network_type = "existing"
region       = "<region>"
vpc_cidr     = "<vpc-cidr>"

existing_vpc_id = "<vpc-id>"
existing_private_subnet_ids = [
  "<subnet-az-a>",
  "<subnet-az-b>",
  "<subnet-az-c>",
]
existing_public_subnet_ids = []  # or list of public subnet IDs

zero_egress = true   # or false
private     = true   # PrivateLink API
multi_az    = true
```

## Validation before apply

```bash
make cluster.<name>.validate
```

Expected: account checks pass; network checks pass for provided VPC.

## Optional handoff (IAM team — path 2b)

- [ ] Installer role ARN
- [ ] Support role ARN
- [ ] Worker role ARN
- [ ] OIDC config ID
- [ ] EBS KMS key ARN
- [ ] EFS KMS key ARN (if EFS enabled)
- [ ] etcd KMS key ARN (if `etcd_encryption = true`)
- [ ] Zero egress: ECR read-only on worker role

See [IAM and KMS Handoff](iam-kms.md).

## Terraform variables reference

| Variable | Required when `network_type = existing` |
|----------|----------------------------------------|
| `existing_vpc_id` | Yes |
| `existing_private_subnet_ids` | Yes (at least one) |
| `existing_public_subnet_ids` | Optional |
| `vpc_cidr` | Yes (must match VPC) |
| `region` | Yes |

Defined in [`terraform/01-variables.tf`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/terraform/01-variables.tf).

## Related

- [Customer Intake Form](../customer-intake.md)
- [BYO Network Requirements](network.md)
