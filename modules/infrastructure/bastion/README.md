# Bastion Module

> **⚠️ IMPORTANT: Development/Demo Use Only**
>
> This bastion module is provided for **development and demonstration purposes only**. For production deployments, organizations should use enterprise-grade connectivity solutions such as:
> - **AWS Transit Gateway** for multi-VPC connectivity
> - **AWS Direct Connect** or **VPN** for on-premises connectivity
> - **Site-to-Site VPN** for secure network-to-network connections
>
> The bastion host is a convenience feature for quick access during development and testing. It should **not** be used in production environments where proper network architecture and security controls are required.

This module creates a bastion host for secure access to private ROSA HCP clusters. The bastion supports two access modes:

1. **SSM Session Manager** (recommended, default): No public IP, access via AWS Systems Manager
2. **Public IP**: Traditional SSH access with public IP address

## Features

- **SSM Session Manager Support**: Secure access without public IPs or SSH keys
- **Pre-installed Tools**: OpenShift CLI (`oc`), Kubernetes CLI (`kubectl`), and system utilities
- **Optional Public IP**: Can be enabled for traditional SSH access
- **IAM-based Access**: Uses IAM roles for authentication (no SSH key management for SSM)
- **VPN-like Access**: Supports `sshuttle` for full VPC access
- **SSH Tunnel Support**: Can forward ports for Terraform/API access

## Usage

### Basic Usage (SSM-only, recommended)

```hcl
module "bastion" {
  source = "../../modules/bastion"

  name_prefix        = var.cluster_name
  vpc_id             = module.network.vpc_id
  subnet_id          = module.network.private_subnet_ids[0]  # Use private subnet
  private_subnet_ids = module.network.private_subnet_ids     # All private subnets for SSM endpoints
  region             = var.region
  vpc_cidr           = var.vpc_cidr

  bastion_public_ip = false  # SSM-only access (more secure)

  tags = var.tags
}
```

### With Public IP (for testing)

```hcl
module "bastion" {
  source = "../../modules/bastion"

  name_prefix         = var.cluster_name
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_ids[0]  # Use public subnet
  private_subnet_ids  = module.network.private_subnet_ids     # All private subnets for SSM endpoints
  region              = var.region
  vpc_cidr            = var.vpc_cidr
  bastion_public_ip   = true  # Enable public IP for SSH access
  bastion_public_ssh_key = "~/.ssh/id_rsa.pub"

  tags = var.tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for all resource names (typically cluster name) | `string` | n/a | yes |
| vpc_id | ID of the VPC where the bastion will be deployed | `string` | n/a | yes |
| subnet_id | ID of the subnet where the bastion will be deployed | `string` | n/a | yes |
| private_subnet_ids | List of private subnet IDs where SSM VPC endpoints will be created. Required for SSM Session Manager access from private subnets | `list(string)` | n/a | yes |
| region | AWS region where the bastion will be deployed | `string` | n/a | yes |
| vpc_cidr | CIDR block of the VPC (used for sshuttle DNS configuration) | `string` | n/a | yes |
| bastion_public_ip | Whether the bastion should have a public IP address | `bool` | `false` | no |
| bastion_public_ssh_key | Path to SSH public key file | `string` | `"~/.ssh/id_rsa.pub"` | no |
| instance_type | EC2 instance type for the bastion host | `string` | `"t3.micro"` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| permissions_boundary_arn | ARN of the permission boundary policy for the bastion IAM role. If null, no boundary is applied | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| bastion_instance_id | Instance ID of the bastion host (for SSM Session Manager access) |
| bastion_public_ip | Public IP address (only set if bastion_public_ip is true) |
| bastion_private_ip | Private IP address of the bastion host |
| bastion_security_group_id | Security group ID of the bastion host |
| ssm_endpoint_ids | Map of SSM VPC endpoint IDs created by the bastion module |
| ssh_command | SSH command to connect (only if bastion_public_ip is true) |
| ssm_session_command | AWS SSM Session Manager command to connect to bastion |
| sshuttle_command | sshuttle command to create VPN-like access to VPC |
| ssh_tunnel_command | SSH tunnel command template for port forwarding |

## Access Methods

### 1. SSM Session Manager (Recommended)

```bash
# Connect to bastion via SSM
aws ssm start-session --target <bastion-instance-id> --region <region>

# Or use the output
aws ssm start-session --target $(terraform output -raw bastion_instance_id) --region <region>
```

### 2. SSH (if bastion_public_ip is true)

```bash
ssh ec2-user@<bastion-public-ip>
```

### 3. SSH Tunnel for Terraform/API Access

```bash
# Get cluster API URL
API_URL=$(terraform output -raw api_url | sed 's|https://||')

# Create SSH tunnel via SSM
ssh -f -N -L 6443:${API_URL}:443 \
  -o ProxyCommand="aws --region <region> ssm start-session --target <bastion-id> --document-name AWS-StartSSHSession --parameters portNumber=22" \
  ec2-user@<bastion-id>

# Now Terraform can access cluster API at https://localhost:6443
```

### 4. VPN-like Access with sshuttle

```bash
# Via SSM (no public IP)
sshuttle --ssh-cmd="ssh -o ProxyCommand='aws --region <region> ssm start-session --target <bastion-id> --document-name AWS-StartSSHSession --parameters portNumber=22'" \
  --remote ec2-user@<bastion-id> --dns <vpc-cidr>

# Via public IP (if enabled)
sshuttle --remote ec2-user@<bastion-public-ip> --dns <vpc-cidr>
```

## Pre-installed Tools

The bastion comes pre-installed with:
- OpenShift CLI (`oc`)
- Kubernetes CLI (`kubectl`)
- AWS CLI (via SSM Agent)
- System utilities (curl, wget, jq, bind-utils, podman, etc.)

## Security Considerations

- **SSM-only mode (bastion_public_ip = false)**: Most secure, no public IPs, no open ports
- **Public IP mode**: Less secure, requires SSH key management, exposes port 22
- **IAM-based access**: SSM uses IAM roles, eliminating SSH key management
- **Audit logging**: All SSM sessions are logged in CloudTrail

## Cost

- **t3.micro instance**: ~$7/month (~$0.0104/hour)
- **SSM Session Manager**: No additional cost
- **Data transfer**: Standard AWS data transfer pricing

## Integration with Private Clusters

This module is designed to work with:
- `modules/network-private` - Private VPC with PrivateLink API
- `modules/network-egress-zero` - Egress-zero VPC with no internet access

The bastion provides secure access to these private clusters without exposing them to the public internet.
