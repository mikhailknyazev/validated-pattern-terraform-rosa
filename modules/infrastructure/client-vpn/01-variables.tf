#------------------------------------------------------------------------------
# Client VPN Module Variables
#
# Reference: ./reference/rosa-tf/modules/networking/client-vpn/variables.tf
#------------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the ROSA cluster (used for resource naming)."
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the VPC to attach the Client VPN endpoint to."
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (for authorization rules)."
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "List of subnet IDs to associate with the VPN endpoint. At least one required."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required for the VPN endpoint."
  }
}

variable "client_cidr_block" {
  description = <<-EOT
    CIDR block for VPN client IP addresses. Must not overlap with VPC CIDR.
    Minimum /22 (1024 addresses). AWS reserves half for HA.
    Example: "10.100.0.0/22"
  EOT
  type        = string
  default     = "10.100.0.0/22"
  nullable    = false
}

variable "dns_servers" {
  description = <<-EOT
    DNS servers for VPN clients. If null, uses VPC default DNS.
    For cluster DNS resolution, use the VPC DNS server (VPC CIDR base + 2).
    Example: ["10.0.0.2"] for a 10.0.0.0/16 VPC.
  EOT
  type        = list(string)
  default     = null
  nullable    = true
}

variable "service_cidr" {
  description = "Kubernetes service CIDR for authorization (optional)."
  type        = string
  default     = null
  nullable    = true
}

variable "split_tunnel" {
  description = <<-EOT
    Enable split tunnel mode. When true, only VPC-destined traffic goes through VPN.
    When false, all traffic routes through VPN.
    Recommended: true (better performance, lower bandwidth costs).
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "session_timeout_hours" {
  description = "VPN session timeout in hours (8-24)."
  type        = number
  default     = 12
  nullable    = false

  validation {
    condition     = var.session_timeout_hours >= 8 && var.session_timeout_hours <= 24
    error_message = "Session timeout must be between 8 and 24 hours."
  }
}

variable "certificate_validity_days" {
  description = "Validity period for generated certificates in days."
  type        = number
  default     = 365
  nullable    = false
}

variable "certificate_organization" {
  description = "Organization name for certificate subject."
  type        = string
  default     = "ROSA HCP"
  nullable    = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting VPN connection logs."
  type        = string
  default     = null
  nullable    = true
}

variable "output_dir" {
  description = "Directory where to write the .ovpn client configuration file."
  type        = string
  nullable    = false
}

variable "client_config_display_path" {
  description = <<-EOT
    Path to display in connection instructions, relative to project root.
    When set, used instead of the actual filesystem path (e.g. ./clusters/egress-zero/cluster-vpn-client.ovpn).
    When null, falls back to the actual filename.
  EOT
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_domain" {
  description = "Domain of the ROSA cluster for connection instructions (e.g., cluster-name.xxxx.p1.openshiftapps.com). Optional."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
