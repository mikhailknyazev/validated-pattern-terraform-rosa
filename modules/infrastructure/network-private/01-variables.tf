variable "name_prefix" {
  description = "Prefix for all resource names (typically cluster name). Ensures unique resource names across clusters."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# Note: availability_zones are automatically determined from AWS data source based on multi_az setting

variable "multi_az" {
  description = "Create resources across multiple availability zones for high availability"
  type        = bool
  default     = true
  nullable    = false
}

variable "subnet_cidr_size" {
  description = "CIDR size for each subnet (e.g., 20 for /20). If not provided, will be automatically calculated based on VPC CIDR size and number of subnets needed. Must be larger than VPC CIDR size."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.subnet_cidr_size == null || (var.subnet_cidr_size > 16 && var.subnet_cidr_size <= 28)
    error_message = "Subnet CIDR size must be between 17 and 28 if provided."
  }
}

variable "enable_nat_gateway" {
  description = "Enable Regional NAT Gateway for internet egress from private subnets. Requires an Internet Gateway but does not require public subnets."
  type        = bool
  default     = true
  nullable    = false
}

variable "zero_egress" {
  description = "Enable zero egress mode (no internet egress, only VPC endpoints). When true, creates worker node security group with limited egress rules and removes egress from VPC endpoint security group. Matches ROSA API property name."
  type        = bool
  default     = false
  nullable    = false
}

variable "flow_log_s3_bucket" {
  description = "S3 bucket name for VPC Flow Logs (optional, typically used with zero-egress mode for audit logging)"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

# Destroy Protection Variables
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "persists_through_sleep_network" {
  description = "Override persists_through_sleep for network resources. If null, uses persists_through_sleep value. Allows sleeping network resources while preserving other resources."
  type        = bool
  default     = null
  nullable    = true
}

variable "custom_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for the VPC flow log IAM role. If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}
