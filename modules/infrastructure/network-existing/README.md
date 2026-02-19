# Network Existing Module

> **DEPRECATED**: This module is deprecated. Use `network_type = "existing"` in the root Terraform configuration instead. When `network_type = "existing"`, no network module runs—you provide `existing_vpc_id`, `existing_private_subnet_ids`, and `existing_public_subnet_ids` directly. The root module uses data sources to look up subnets and passes them to the cluster. See `clusters/byo-vpc/terraform.tfvars` for an example. This module will be removed in a future release.

This module tags existing VPC subnets with ROSA-required tags. It does not create any VPC resources, making it suitable for scenarios where the VPC is managed by a separate network team.

## Purpose

This module is designed for multi-team scenarios where:
- Network team owns and manages the VPC
- Platform team needs to deploy ROSA clusters in existing subnets
- Subnets need to be tagged for ROSA load balancer placement

## Usage

```hcl
module "network" {
  source = "../../modules/infrastructure/network-existing"

  name_prefix       = var.cluster_name
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.0.0.0/16"
  private_subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0fedcba9876543210",
    "subnet-0abcdef0123456789"
  ]
  public_subnet_ids = []  # Optional, only if using public subnets

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

## Requirements

- Existing VPC with subnets already created
- Subnets must be in the same VPC
- Appropriate IAM permissions to tag subnets

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for resource names (used in tags) | `string` | n/a | yes |
| vpc_id | ID of the existing VPC | `string` | n/a | yes |
| vpc_cidr | CIDR block of the existing VPC | `string` | n/a | yes |
| private_subnet_ids | List of private subnet IDs (at least one required) | `list(string)` | `[]` | yes |
| public_subnet_ids | List of public subnet IDs (optional) | `list(string)` | `[]` | no |
| tags | Additional tags to apply | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the existing VPC |
| vpc_cidr_block | CIDR block of the VPC |
| private_subnet_ids | List of private subnet IDs |
| public_subnet_ids | List of public subnet IDs |
| private_subnet_azs | List of availability zones for private subnets |
| public_subnet_azs | List of availability zones for public subnets |
| nat_gateway_ids | Empty list (for compatibility with other network modules) |
| nat_gateway_id | Null (for compatibility with other network modules) |
| internet_gateway_id | Null (for compatibility with other network modules) |
| vpc_endpoint_ids | Empty map (for compatibility with other network modules) |

## ROSA-Required Tags

This module automatically applies the following tags required by ROSA:

- **Private Subnets**: `kubernetes.io/role/internal-elb = "1"`
- **Public Subnets**: `kubernetes.io/role/elb = "1"`

These tags tell ROSA where to place load balancers:
- Internal load balancers → private subnets
- External load balancers → public subnets

## Notes

- This module does NOT create any VPC resources
- VPC endpoints, NAT gateways, and route tables are assumed to exist or be managed separately
- The module validates that the VPC and subnets exist via data sources
- Tags are applied using `aws_ec2_tag` resources to avoid conflicts with existing tags
- Outputs are designed to be compatible with other network modules for easy module swapping

## Example: Multi-Team Scenario

**Network Team** manages VPC:
```hcl
# Network team's Terraform (separate repo/directory)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  # ... VPC configuration
}

resource "aws_subnet" "private" {
  count = 3
  vpc_id = aws_vpc.main.id
  # ... subnet configuration
}
```

**Platform Team** uses this module:
```hcl
# Platform team's Terraform
module "network" {
  source = "../../modules/infrastructure/network-existing"

  name_prefix       = var.cluster_name
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr          = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}
```

## Related Modules

- `network-public` - Creates a new public VPC with NAT gateways
- `network-private` - Creates a new private VPC with VPC endpoints (supports zero-egress mode via `zero_egress`)

## References

- [ROSA HCP Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/)
- [ROSA Subnet Tagging Requirements](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html-single/install_clusters/index)
