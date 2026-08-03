variable "enabled" {
  description = "When true, create the HTPasswd identity provider, user, and group membership. When false, no resources are created (apply with false destroys previously created resources)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_id" {
  description = "ROSA HCP cluster ID. Required when enabled is true."
  type        = string
  nullable    = true
  default     = null
}

variable "password" {
  description = "Optional HTPasswd password. When null, a random password is generated. When set, that value is used and random_password is not created."
  type        = string
  sensitive   = true
  nullable    = true
  default     = null

  validation {
    condition     = var.password == null || length(var.password) >= 14
    error_message = "HTPasswd password must be at least 14 characters when set (ROSA HTPasswd requirement)."
  }
}

variable "idp_name" {
  description = "Name of the HTPasswd identity provider"
  type        = string
  nullable    = false
}

variable "username" {
  description = "HTPasswd username"
  type        = string
  nullable    = false
}

variable "admin_group" {
  description = "OpenShift group to add the user to"
  type        = string
  default     = "cluster-admins"
  nullable    = false
}
