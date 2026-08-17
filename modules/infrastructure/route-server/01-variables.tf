variable "cluster_name" {
  description = "Name prefix for all Route Server resources"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region for the cluster and Route Server (written into the BGP config Secrets Manager secret)"
  type        = string
  nullable    = false
}

variable "secrets_manager_role_name" {
  description = "IAM role name for External Secrets Operator. When set, attaches GetSecretValue on the BGP config secret. Null skips the attachment (enable_secrets_manager_iam must be true for ESO)."
  type        = string
  default     = null
  nullable    = true
}

variable "vpc_id" {
  description = "VPC ID to associate the Route Server with"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Route Server endpoints (2 endpoints per subnet)"
  type        = list(string)
  nullable    = false
}

variable "private_route_table_ids" {
  description = "List of private route table IDs for Route Server propagation"
  type        = list(string)
  nullable    = false
}

variable "public_route_table_ids" {
  description = "List of public route table IDs for Route Server propagation. Empty list if no public subnets."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL for the ROSA cluster (used for IRSA trust policy on the BGP operator IAM role)"
  type        = string
  nullable    = false
}

variable "route_server_asn" {
  description = "Amazon-side ASN for the VPC Route Server. Must not conflict with the BGP local ASN used by OpenShift FRR routers."
  type        = number
  default     = 64512
  nullable    = false
}

variable "persist_routes" {
  description = "Whether to persist routes when the BGP session is terminated ('enable' or 'disable')"
  type        = string
  default     = "disable"
  nullable    = false

  validation {
    condition     = contains(["enable", "disable"], var.persist_routes)
    error_message = "persist_routes must be 'enable' or 'disable'"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "persists_through_sleep" {
  description = "Whether resources should persist through sleep mode. When false, all resources are destroyed."
  type        = bool
  default     = true
  nullable    = false
}

variable "custom_permissions_boundary_arn" {
  description = "ARN of the permission boundary policy for the BGP operator IAM role. If null, no boundary is applied."
  type        = string
  default     = null
  nullable    = true
}
