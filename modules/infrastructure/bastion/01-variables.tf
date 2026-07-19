variable "name_prefix" {
  description = "Prefix for all resource names (typically cluster name). Ensures unique resource names across clusters"
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the VPC where the bastion will be deployed"
  type        = string
  nullable    = false
}

variable "subnet_id" {
  description = "ID of the subnet where the bastion will be deployed. Use private subnet for SSM-only access, public subnet if bastion_public_ip is true"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where VPC endpoints for SSM will be created. Required for SSM Session Manager access from private subnets."
  type        = list(string)
  nullable    = false
}

variable "bastion_public_ip" {
  description = "Whether the bastion should have a public IP address. If false, access is via SSM Session Manager only (more secure)"
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ssh_key" {
  description = "Path to SSH public key file for bastion access. Required even if using SSM-only access (for sshuttle)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  nullable    = false
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
  nullable    = false
}

variable "region" {
  description = "AWS region where the bastion will be deployed"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used for sshuttle DNS configuration)"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for the bastion IAM role. If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}

# Sleep Protection Variable
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}
