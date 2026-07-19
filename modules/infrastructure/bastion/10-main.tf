# Data sources
data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# Find latest Amazon Linux 2 AMI
# Amazon Linux 2 has SSM agent pre-installed, which is essential for egress-zero clusters
# Reference: https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html
data "aws_ami" "amazon_linux2" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Name      = "${var.name_prefix}-bastion"
  })
}

# IAM Role for Bastion (enables SSM Session Manager)
resource "aws_iam_role" "bastion" {
  count = var.persists_through_sleep ? 1 : 0

  name                 = substr("${var.name_prefix}-bastion-iam-role", 0, 64)
  description          = "IAM role for bastion host with SSM Session Manager access"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach SSM Managed Instance Core policy (required for Session Manager)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count = var.persists_through_sleep ? 1 : 0

  role       = one(aws_iam_role.bastion[*].name)
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile for Bastion
resource "aws_iam_instance_profile" "bastion" {
  count = var.persists_through_sleep ? 1 : 0

  name = "${var.name_prefix}-bastion-instance-profile"
  role = one(aws_iam_role.bastion[*].name)

  tags = local.common_tags
}

# SSH Key Pair for Bastion
resource "aws_key_pair" "bastion" {
  count = var.persists_through_sleep ? 1 : 0

  key_name   = "${var.name_prefix}-bastion"
  public_key = file(var.bastion_public_ssh_key)

  tags = local.common_tags
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  count = var.persists_through_sleep ? 1 : 0

  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access - only needed if bastion_public_ip is true
  # When using SSM Session Manager, this ingress rule is not required
  ingress {
    description = "SSH from anywhere (only used if bastion_public_ip is true)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_public_ip ? ["0.0.0.0/0"] : []
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

# Security Group for SSM VPC Endpoints
resource "aws_security_group" "ssm_endpoint" {
  count = var.persists_through_sleep ? 1 : 0

  name        = "${var.name_prefix}-bastion-ssm-endpoint-sg"
  description = "Security group for SSM VPC endpoints (required for Session Manager)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssm-endpoint-sg"
  })
}

# SSM Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  count = var.persists_through_sleep ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssm-endpoint"
  })
}

# EC2 Messages Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ec2messages" {
  count = var.persists_through_sleep ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ec2messages-endpoint"
  })
}

# SSM Messages Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.persists_through_sleep ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssmmessages-endpoint"
  })
}

# Note: S3 Gateway endpoint is created by the network module (network-private with egress-zero mode)
# No need to create it here - the bastion instance can use the existing endpoint

# Bastion EC2 Instance
resource "aws_instance" "bastion" {
  count = var.persists_through_sleep ? 1 : 0

  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [one(aws_security_group.bastion[*].id)]
  iam_instance_profile        = one(aws_iam_instance_profile.bastion[*].name)
  associate_public_ip_address = var.bastion_public_ip
  key_name                    = one(aws_key_pair.bastion[*].key_name)

  tags = local.common_tags

  user_data = <<-EOF
#!/bin/bash
set -e -x

# Amazon Linux 2 has SSM agent pre-installed
# For egress-zero clusters, we cannot install additional packages (no internet access)
# Just ensure SSM agent is enabled and running

echo "Checking SSM agent status..."

# Verify SSM agent is installed (should always be true on Amazon Linux 2)
if rpm -q amazon-ssm-agent >/dev/null 2>&1; then
    echo "SSM agent package is installed"
elif command -v amazon-ssm-agent >/dev/null 2>&1; then
    echo "SSM agent binary found: $(command -v amazon-ssm-agent)"
else
    echo "ERROR: SSM agent not found. This is unexpected on Amazon Linux 2."
    echo "SSM agent should be pre-installed on Amazon Linux 2 AMIs."
    exit 1
fi

# Enable and start SSM Agent
echo "Enabling SSM agent..."
sudo systemctl enable amazon-ssm-agent || {
    echo "WARNING: Failed to enable SSM agent"
}

echo "Starting SSM agent..."
sudo systemctl start amazon-ssm-agent || {
    echo "ERROR: Failed to start SSM agent"
    exit 1
}

# Wait a moment for SSM agent to start and register
echo "Waiting for SSM agent to initialize..."
sleep 10

# Check SSM agent status
echo "SSM agent status:"
sudo systemctl status amazon-ssm-agent --no-pager -l || echo "SSM agent status check failed"

echo "Bastion initialization complete. SSM agent should be running and registering with AWS Systems Manager."
echo "Note: For egress-zero clusters, no additional packages are installed (no internet access)."
EOF

  # Ensure SSM Agent is running before considering instance ready
  user_data_replace_on_change = true
}
